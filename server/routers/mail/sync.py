from fastapi import Body, APIRouter, Depends, HTTPException, BackgroundTasks
from typing import Optional, Dict, List
from datetime import datetime
import email
from email.header import decode_header
from email.utils import parsedate_to_datetime, getaddresses
import os
import uuid
from pathlib import Path
from schemas.mail.sync import SyncRequest
import threading

from config import settings, db
from routers.login.auth import verify_token
from services.imap_service import IMAPService
from util.crypto import encrypt_password, decrypt_password
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

# 동기화 상태 추적 (인메모리)
sync_status: Dict[str, dict] = {}
# 계정별 동기화 실행 중 플래그
active_syncs: Dict[str, bool] = {}


# ========================================
# Helper Functions
# ========================================

def is_sync_running(account_uuid: str, folder: str) -> bool:
    """해당 계정/폴더가 현재 동기화 중인지 확인"""
    sync_key = f"{account_uuid}_{folder}"
    return active_syncs.get(sync_key, False)


def set_sync_running(account_uuid: str, folder: str, running: bool):
    """동기화 실행 상태 설정"""
    sync_key = f"{account_uuid}_{folder}"
    active_syncs[sync_key] = running

def parse_email_header(header_value):
    """이메일 헤더 디코딩"""
    if not header_value:
        return ""

    decoded_parts = decode_header(header_value)
    result = []

    for part, encoding in decoded_parts:
        if isinstance(part, bytes):
            try:
                result.append(part.decode(encoding or 'utf-8', errors='ignore'))
            except:
                result.append(part.decode('utf-8', errors='ignore'))
        else:
            result.append(str(part))

    return ''.join(result)


def extract_email_address(addr_string):
    """이메일 주소 추출 (From: "Name" <email@example.com> 형식 처리)"""
    if not addr_string:
        return "", ""

    # email 라이브러리로 파싱
    from email.utils import parseaddr
    name, email_addr = parseaddr(addr_string)

    return parse_email_header(name), email_addr


def decode_address_list(header_value) -> str:
    """Address-list 헤더(To/Cc)를 RFC2047 디코딩하여 'Name <addr>, ...' 문자열로.

    R0001 / 0017: To 헤더의 표시이름이 RFC2047 인코딩워드(=?..?B?..?=)로 와도
    From/Subject처럼 디코딩하여 저장한다. getaddresses로 콤마 안전하게 분리하고,
    표시이름만 parse_email_header로 디코딩한다(주소부는 ASCII이므로 그대로).
    """
    if not header_value:
        return ""
    out = []
    for name, addr in getaddresses([str(header_value)]):
        name = parse_email_header(name)
        # NOTE: build the display string by hand — formataddr() would RE-encode a
        # non-ASCII name back into an RFC2047 encoded-word, reintroducing R0001.
        if addr and name:
            out.append("%s <%s>" % (name, addr))
        elif addr:
            out.append(addr)
        elif name:
            out.append(name)
    return ', '.join(out)


def parse_email_message(raw_email: bytes) -> dict:
    """RFC822 메일 파싱"""
    msg = email.message_from_bytes(raw_email)

    # From 파싱
    from_header = msg.get('From', '')
    from_name, from_email = extract_email_address(from_header)

    # To 파싱 (RFC2047 인코딩워드 디코딩 — From/Subject와 대칭)
    to_emails = decode_address_list(msg.get('To', ''))

    # Cc 파싱 (compat 상세 응답의 cc 필드 채움)
    cc_emails = decode_address_list(msg.get('Cc', ''))

    # Subject 파싱
    subject = parse_email_header(msg.get('Subject', '(제목없음)'))

    # Date 파싱
    date_header = msg.get('Date')
    try:
        sent_date = parsedate_to_datetime(date_header) if date_header else datetime.now()
    except:
        sent_date = datetime.now()

    # 본문 추출
    body_text = ""
    body_html = ""
    attachments = []

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition", ""))

            # 첨부파일
            if "attachment" in content_disposition:
                filename = part.get_filename()
                if filename:
                    attachments.append({
                        "filename": parse_email_header(filename),
                        "content": part.get_payload(decode=True),
                        "content_type": content_type,
                        "size": len(part.get_payload(decode=True) or b'')
                    })
            # 본문
            elif content_type == "text/plain" and not body_text:
                try:
                    body_text = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                except:
                    body_text = str(part.get_payload())
            elif content_type == "text/html" and not body_html:
                try:
                    body_html = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                except:
                    body_html = str(part.get_payload())
    else:
        # Single part message
        content_type = msg.get_content_type()
        try:
            payload = msg.get_payload(decode=True)
            if content_type == "text/plain":
                body_text = payload.decode('utf-8', errors='ignore')
            elif content_type == "text/html":
                body_html = payload.decode('utf-8', errors='ignore')
        except:
            body_text = str(msg.get_payload())

    # Preview 생성 (본문 앞 100자)
    preview = (body_text or body_html)[:100].replace('\n', ' ').strip()

    return {
        "message_id": msg.get('Message-ID', ''),
        "from_email": from_email,
        "from_name": from_name,
        "to_emails": to_emails,
        "cc_emails": cc_emails,
        "subject": subject,
        "sent_date": sent_date,
        "body_text": body_text,
        "body_html": body_html,
        "preview": preview,
        "has_attachments": len(attachments) > 0,
        "attachments": attachments,
        "size_bytes": len(raw_email)
    }


def save_email_to_filesystem(account_uuid: str, message_uuid: str, raw_email: bytes) -> str:
    """메일 원본을 파일 시스템에 저장"""
    # {MAIL_STORAGE_BASE_PATH}/{account_uuid}/messages/{uuid[:2]}/{uuid}.eml
    base_path = Path(f"{settings.MAIL_STORAGE_BASE_PATH}/{account_uuid}/messages")
    subdir = message_uuid[:2]
    file_path = base_path / subdir / f"{message_uuid}.eml"

    # 디렉토리 생성
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # 파일 저장
    with open(file_path, 'wb') as f:
        f.write(raw_email)

    return str(file_path)


def save_attachment_to_filesystem(account_uuid: str, attachment_uuid: str, filename: str, content: bytes) -> str:
    """첨부파일을 파일 시스템에 저장"""
    # {MAIL_STORAGE_BASE_PATH}/{account_uuid}/attachments/{uuid[:2]}/{uuid}_{filename}
    base_path = Path(f"{settings.MAIL_STORAGE_BASE_PATH}/{account_uuid}/attachments")
    subdir = attachment_uuid[:2]
    file_path = base_path / subdir / f"{attachment_uuid}_{filename}"

    # 디렉토리 생성
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # 파일 저장
    with open(file_path, 'wb') as f:
        f.write(content)

    return str(file_path)


def get_or_create_folder_uuid(account_uuid: str, folder_name: str, folder_path: str = None) -> str:
    """폴더 UUID 조회 또는 생성"""
    # 기존 폴더 조회
    check_query = """
        SELECT folder_uuid FROM mail_folders
        WHERE account_uuid = %s AND folder_name = %s
    """
    existing = db_instance.fetch_one(check_query, (account_uuid, folder_name))

    if existing:
        return existing['folder_uuid']

    # 없으면 새로 생성
    folder_uuid = str(uuid.uuid4())
    folder_type = 'inbox' if folder_name.upper() == 'INBOX' else 'custom'

    insert_query = """
        INSERT INTO mail_folders
        (folder_uuid, account_uuid, folder_name, folder_path, folder_type)
        VALUES (%s, %s, %s, %s, %s)
    """

    db_instance.execute_query(insert_query, (
        folder_uuid,
        account_uuid,
        folder_name,
        folder_path or folder_name,
        folder_type
    ))

    logger.info(f"[Sync] 새 폴더 생성: {folder_name} ({folder_uuid})")
    return folder_uuid


def sync_account_mails(account_uuid: str, user_uuid: str, folder: str = "INBOX") -> dict:
    """특정 계정의 메일 동기화 실제 로직"""

    # 중복 동기화 체크
    if is_sync_running(account_uuid, folder):
        logger.warn(f"[Sync] 이미 동기화 진행 중 - 계정: {account_uuid}, 폴더: {folder}")
        return {
            "success": False,
            "message": "이미 해당 계정/폴더가 동기화 진행 중입니다",
            "new_mails": 0,
            "total_mails": 0
        }

    # 동기화 시작 플래그 설정
    set_sync_running(account_uuid, folder, True)

    sync_id = f"{account_uuid}_{folder}_{datetime.now().timestamp()}"
    logger.debug(f"[Sync] sync_id 생성: {sync_id}")
    sync_status[sync_id] = {
        "status": "running",
        "progress": 0,
        "total": 0,
        "new_mails": 0,
        "errors": []
    }
    logger.debug(f"[Sync] sync_status에 추가됨: {list(sync_status.keys())}")

    try:
        # 1. 계정 정보 조회
        account = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "get_account"),
            (account_uuid,)
        )

        if not account:
            raise Exception("계정을 찾을 수 없음")

        # 2. Gmail이면 OAuth, 아니면 기존 방식
        if account.get('account_type') == 'gmail':
            from services.gmail_service import GmailIMAPService, GmailOAuthService

            refresh_token_encrypted = account.get('refresh_token_encrypted')
            if not refresh_token_encrypted:
                raise Exception("재인증이 필요합니다. (refresh_token 없음)")

            try:
                refresh_token = decrypt_password(settings.SECRET_KEY, user_uuid, refresh_token_encrypted)
                gmail_oauth = GmailOAuthService()

                import asyncio
                loop = asyncio.new_event_loop()
                asyncio.set_event_loop(loop)
                token_data = loop.run_until_complete(gmail_oauth.refresh_access_token(refresh_token))
                loop.close()

                access_token = token_data['access_token']

                # DB 업데이트
                encrypted_access = encrypt_password(settings.SECRET_KEY, user_uuid, access_token)
                db_instance.execute_query(
                    sqloader.load_sql("mail_anchor.json", "gmail.update_access_token"),
                    {
                        "account_uuid": account_uuid,
                        "access_token_encrypted": encrypted_access,
                        "token_expires_in": token_data.get("expires_in", 3600),
                    }
                )
                logger.info(f"[Sync] 토큰 갱신 성공 - 계정: {account_uuid}")

            except Exception as e:
                error_msg = str(e)
                if "invalid_grant" in error_msg:
                    raise Exception("재인증이 필요합니다. Google 계정을 다시 연결해주세요.")
                raise Exception(f"토큰 갱신 실패: {error_msg}")

            imap = GmailIMAPService(account['email'], access_token)

        else:
            imap_password = decrypt_password(settings.SECRET_KEY, user_uuid, account['imap_password_encrypted'])
            imap = IMAPService(
                host=account['imap_host'],
                port=account['imap_port'],
                username=account['imap_username'],
                password=imap_password,
                use_ssl=account.get('imap_use_ssl', True)
            )

        connect_result = imap.connect()

        if not connect_result["success"]:
            raise Exception(f"IMAP 연결 실패: {connect_result['message']}")

        # 4. 폴더 선택 전에 folder_uuid 확보
        folder_uuid = get_or_create_folder_uuid(account_uuid, folder, folder)

        # 5. 폴더 선택
        imap.connection.select(folder, readonly=True)


        # 6. 메일 UID 목록 가져오기
        last_uid_query = """
            SELECT MAX(uid) as last_uid
            FROM mail_messages
            WHERE account_uuid = %(account_uuid)s AND folder_uuid = %(folder_uuid)s
        """
        last_uid_row = db_instance.fetch_one(last_uid_query, {
            "account_uuid": account_uuid,
            "folder_uuid": folder_uuid
        })

        last_uid = last_uid_row['last_uid'] if last_uid_row and last_uid_row['last_uid'] else None

        # IMAP에서 전체 UID 가져오기
        status, messages = imap.connection.uid('search', None, 'ALL')
        if status != 'OK':
            raise Exception("메일 검색 실패")

        all_uids = messages[0].split()

        if last_uid:
            mail_uids = [uid for uid in all_uids if int(uid) > last_uid]
            if settings.ENVIRONMENT not in ("prd", "production"):
                mail_uids = mail_uids[-100:]
        else:
            if settings.ENVIRONMENT in ("prd", "production"):
                mail_uids = all_uids
            else:
                mail_uids = all_uids[-100:]

        total = len(mail_uids)

        if total == 0:
            logger.info(f"[Sync] 새 메일 없음")
            # 동기화 성공 기록하고 종료

        sync_status[sync_id]["total"] = total
        logger.info(f"[Sync] 계정 {account_uuid} - {folder} 폴더: {total}개 메일 발견")


        # 7. 이미 동기화된 UID 확인 (기존 코드 그대로)
        existing_uids = set()

        # 8. 메일 순회하며 저장 (기존 코드 그대로)
        new_count = 0
        for idx, uid in enumerate(mail_uids):
            uid_str = uid.decode()

            # 진행률 업데이트
            sync_status[sync_id]["current"] = idx + 1


            # 중복 체크
            if uid_str in existing_uids:
                continue

            try:
                # ✅ 여기 추가! (저장 전에 체크)
                uid_int = int(uid)
                existing = db_instance.fetch_one(
                    "SELECT message_uuid FROM mail_messages WHERE account_uuid = %(account_uuid)s AND folder_uuid = %(folder_uuid)s AND uid = %(uid)s",
                    {
                        "account_uuid": account_uuid,
                        "folder_uuid": folder_uuid,
                        "uid": uid_int
                    }
                )
                if existing:
                    logger.debug(f"[Sync] UID {uid} 이미 존재 - 스킵")
                    continue

                # 메일 fetch
                status, msg_data = imap.connection.uid('fetch', uid, '(RFC822)')
                if status != 'OK' or not msg_data or not msg_data[0]:
                    continue

                raw_email = msg_data[0][1]

                # 메일 파싱
                parsed = parse_email_message(raw_email)

                # UUID 생성
                message_uuid = str(uuid.uuid4())

                # 파일 시스템에 저장
                email_path = save_email_to_filesystem(account_uuid, message_uuid, raw_email)

                # DB에 메타데이터 저장
                insert_query = sqloader.load_sql("mail_anchor.json", "sync.insert_message")

                db_instance.execute_query(insert_query, {
                    "message_uuid": message_uuid,
                    "account_uuid": account_uuid,
                    "folder_uuid": folder_uuid,
                    "message_id": parsed['message_id'],
                    "uid": uid_str,
                    "from_email": parsed['from_email'],
                    "from_name": parsed['from_name'],
                    "to_emails": parsed['to_emails'],
                    "subject": parsed['subject'],
                    "preview": parsed['preview'],
                    "sent_date": parsed['sent_date'],
                    "has_attachments": parsed['has_attachments'],
                    "body_file_path": email_path,
                    "size_bytes": parsed['size_bytes']
                })  # 딕셔너리!

                # 첨부파일 저장
                if parsed['attachments']:
                    for attach in parsed['attachments']:
                        attachment_uuid = str(uuid.uuid4())
                        attach_path = save_attachment_to_filesystem(
                            account_uuid,
                            attachment_uuid,
                            attach['filename'],
                            attach['content']
                        )

                        attach_query = """
                            INSERT INTO mail_attachments
                            (attachment_uuid, message_uuid, filename, content_type, size_bytes, file_path)
                            VALUES (%s, %s, %s, %s, %s, %s)
                        """

                        db_instance.execute_query(attach_query, (
                            attachment_uuid,
                            message_uuid,
                            attach['filename'],
                            attach['content_type'],
                            attach['size'],
                            attach_path
                        ))

                new_count += 1

            except Exception as e:
                logger.error(f"[Sync] 메일 {uid_str} 처리 실패: {str(e)}")
                sync_status[sync_id]["errors"].append(f"UID {uid_str}: {str(e)}")

            # 진행상황 업데이트
            sync_status[sync_id]["progress"] = idx + 1

        # 8. IMAP 연결 종료
        imap.disconnect()

        # 9. 동기화 로그 저장
        log_query = sqloader.load_sql("mail_anchor.json", "sync.insert_sync_log")


        db_instance.execute_query(log_query, {
            "account_uuid": account_uuid,
            "sync_type": "manual",
            "status": "completed",
            "messages_fetched": total,
            "messages_updated": new_count
        })  # ← 딕셔너리!

        # 10. 계정의 last_sync_at 업데이트
        update_query = """
            UPDATE mail_accounts
            SET last_sync_at = NOW()
            WHERE account_uuid = %(account_uuid)s
        """
        db_instance.execute_query(update_query, {"account_uuid": account_uuid})

        sync_status[sync_id]["status"] = "completed"
        sync_status[sync_id]["new_mails"] = new_count
        sync_status[sync_id]["new_count"] = new_count

        def clear_sync():
            import time
            time.sleep(5)
            if sync_id in sync_status:
                del sync_status[sync_id]

        threading.Thread(target=clear_sync, daemon=True).start()

        # 동기화 완료 플래그 해제
        set_sync_running(account_uuid, folder, False)

        logger.info(f"[Sync] 완료 - 신규 {new_count}개 / 전체 {total}개")

        return {
            "success": True,
            "new_mails": new_count,
            "total_mails": total,
            "errors": sync_status[sync_id]["errors"]
        }

    except Exception as e:
        logger.error(f"[Sync] 동기화 실패: {str(e)}")
        sync_status[sync_id]["status"] = "failed"
        sync_status[sync_id]["errors"].append(str(e))

        # 동기화 실패 시에도 플래그 해제
        set_sync_running(account_uuid, folder, False)

        # 실패한 sync_status도 5초 후 삭제
        def clear_sync():
            import time
            time.sleep(5)
            if sync_id in sync_status:
                del sync_status[sync_id]

        threading.Thread(target=clear_sync, daemon=True).start()

        # 실패 로그 저장
        try:
            log_query = sqloader.load_sql("mail_anchor.json", "sync.insert_sync_log")
            db_instance.execute_query(log_query, {
                "account_uuid": account_uuid,
                "sync_type": "manual",
                "status": "failed",
                "error_message": str(e)
            })
        except:
            pass

        return {
            "success": False,
            "message": str(e),
            "errors": sync_status[sync_id]["errors"]
        }


# ========================================
# API Endpoints
# ========================================
@router.post("/all", dependencies=[Depends(verify_token)])
async def sync_all_accounts(request_params: SyncRequest, background_tasks: BackgroundTasks):
    """
    모든 계정의 메일 동기화

    - sync_enabled = TRUE인 계정만 동기화
    - 각 계정의 INBOX만 동기화
    """

    request = request_params.model_dump()
    logger.debug(request)
    user_uuid = request['user_uuid']

    # 활성화된 계정 목록 조회
    accounts = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "accounts.get_accounts"),
        {"user_uuid": user_uuid}
    )

    # sync_enabled = TRUE인 계정만 필터링
    active_accounts = [acc for acc in accounts if acc.get('sync_enabled', True)]

    if not active_accounts:
        return {"success": False, "message": "동기화할 계정이 없습니다"}

    logger.info(f"[Sync All] {len(active_accounts)}개 계정 동기화 시작")

    # 백그라운드에서 동기화 실행
    for account in active_accounts:
        background_tasks.add_task(
            sync_account_mails,
            account['account_uuid'],
            user_uuid,
            "INBOX"
        )

    # 즉시 응답 반환 (동기화는 백그라운드에서 진행)
    return {
        "success": True,
        "message": f"{len(active_accounts)}개 계정 동기화 시작",
    }


@router.post("/{account_uuid}", dependencies=[Depends(verify_token)])
async def sync_account(
    account_uuid: str,
    request: SyncRequest,
    background_tasks: BackgroundTasks,  # ✅ = None 제거
    folder: str = "INBOX"
):
    """
    특정 계정의 메일 동기화 (IMAP → DB)

    - 기본적으로 INBOX 폴더 동기화
    - folder 파라미터로 다른 폴더 지정 가능
    - 백그라운드에서 실행
    """

    user_uuid = request.user_uuid

    logger.info(f"[Sync] 동기화 시작 - 계정: {account_uuid}, 폴더: {folder}")

    # ✅ 백그라운드로 실행
    background_tasks.add_task(
        sync_account_mails,
        account_uuid,
        user_uuid,
        folder
    )

    # ✅ 즉시 응답
    return {
        "success": True,
        "message": f"계정 {account_uuid} 동기화 시작"
    }

@router.get("/status", dependencies=[Depends(verify_token)])
async def get_sync_status():
    """
    현재 진행 중인 동기화 상태 조회
    """

    logger.debug(f"[SyncStatus] 현재 sync_status: {sync_status}")
    return {
        "syncs": sync_status  # active_syncs → syncs
    }


@router.get("/logs/{account_uuid}", dependencies=[Depends(verify_token)])
async def get_sync_logs(account_uuid: str, limit: int = 20):
    """
    특정 계정의 동기화 로그 조회
    """
    query = """
        SELECT * FROM sync_logs
        WHERE account_uuid = %s
        ORDER BY created_at DESC
        LIMIT %s
    """

    logs = db_instance.fetch_all(query, (account_uuid, limit))

    return {
        "success": True,
        "logs": logs
    }
