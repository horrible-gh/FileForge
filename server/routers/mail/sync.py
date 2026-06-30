from fastapi import Body, APIRouter, Depends, HTTPException, BackgroundTasks
from typing import Optional, Dict, List
from datetime import datetime
import email
from email.header import decode_header
from email.utils import parsedate_to_datetime, getaddresses
from util.mail_time import to_storage_utc, now_utc_naive
import os
import uuid
from pathlib import Path
from schemas.mail.sync import SyncRequest
import threading

from config import settings, db, mail_storage_base
from routers.login.auth import verify_token
from services.imap_service import IMAPService
from util.crypto import encrypt_password, decrypt_password
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

# Sync status tracking (in-memory)
sync_status: Dict[str, dict] = {}
# Per-account "sync in progress" flag
active_syncs: Dict[str, bool] = {}


# ========================================
# Helper Functions
# ========================================

def is_sync_running(account_uuid: str, folder: str) -> bool:
    """Check whether the given account/folder is currently syncing."""
    sync_key = f"{account_uuid}_{folder}"
    return active_syncs.get(sync_key, False)


def set_sync_running(account_uuid: str, folder: str, running: bool):
    """Set the sync running state."""
    sync_key = f"{account_uuid}_{folder}"
    active_syncs[sync_key] = running

def parse_email_header(header_value):
    """Decode an email header."""
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
    """Extract an email address (handles the From: "Name" <email@example.com> form)."""
    if not addr_string:
        return "", ""

    # Parse with the email library
    from email.utils import parseaddr
    name, email_addr = parseaddr(addr_string)

    return parse_email_header(name), email_addr


def decode_address_list(header_value) -> str:
    """RFC2047-decode an address-list header (To/Cc) into a 'Name <addr>, ...' string.

    R0001 / 0017: even when a To header's display name arrives as an RFC2047
    encoded-word (=?..?B?..?=), decode it before storing, just like From/Subject.
    Split safely on commas with getaddresses, and decode only the display name with
    parse_email_header (the address part is ASCII, so it is left as-is).
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


import re

# Non-displayed element blocks whose *inner content* must be dropped (not just the
# tags) before a preview is taken — otherwise CSS inside <style>, JS inside
# <script>, <head>/<title> metadata and HTML comments leak into the snippet as
# raw text. Mirrors the client's stripHtmlToText policy (mail_body_render.dart).
_NON_DISPLAYED_BLOCK_RE = re.compile(
    r"<!--.*?-->"
    r"|<style\b[^>]*>.*?</style\s*>"
    r"|<script\b[^>]*>.*?</script\s*>"
    r"|<head\b[^>]*>.*?</head\s*>"
    r"|<title\b[^>]*>.*?</title\s*>",
    re.IGNORECASE | re.DOTALL,
)
_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


def strip_html_to_text(html: str) -> str:
    """Strip HTML to readable plain text for a preview/snippet.

    B0001 / 0018: HTML-only mail (no text/plain part) used to surface the raw
    first 100 chars of markup — comments + ``<html><head>…`` — as the list
    snippet. Drop non-displayed block *content* first (so <style>/<script>/
    comments can't leak), then remove the remaining tags and collapse whitespace.
    """
    if not html:
        return ""
    text = _NON_DISPLAYED_BLOCK_RE.sub("", html)
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"</p\s*>", " ", text, flags=re.IGNORECASE)
    text = _TAG_RE.sub("", text)
    text = (text.replace("&nbsp;", " ").replace("&amp;", "&")
                .replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"'))
    return _WS_RE.sub(" ", text).strip()


def make_preview(body_text: str, body_html: str, limit: int = 100) -> str:
    """Build a clean snippet: prefer plain text; otherwise strip the HTML body.

    Never returns raw markup (B0001) — the HTML branch is always tag-stripped.
    """
    if body_text and body_text.strip():
        # Plain text wins, but drop HTML comment / style / script blocks: Gmail's
        # text/plain alternative routinely leaks `<!--[if !mso]>` conditional-comment
        # fragments into the body. Genuine bracketed content (`<https://url>`,
        # `<a@b>`) is not a comment block and is preserved.
        src = _NON_DISPLAYED_BLOCK_RE.sub("", body_text)
    else:
        src = strip_html_to_text(body_html)
    return _WS_RE.sub(" ", src).strip()[:limit]


def _decode_part_text(part) -> str:
    """Decode a MIME text part using its declared charset (not a hardcoded utf-8).

    B0001 / 0018 defect 2: hardcoding ``utf-8`` mangled EUC-KR / ISO-2022-JP
    bodies (the snippet showed ESC sequences / mojibake). Honour the part's
    Content-Type charset, fall back to utf-8, and replace undecodable bytes.
    """
    payload = part.get_payload(decode=True)
    if payload is None:
        return ""
    charset = part.get_content_charset() or "utf-8"
    try:
        primary = payload.decode(charset, errors="replace")
    except (LookupError, TypeError):
        primary = payload.decode("utf-8", errors="replace")
    # Some senders mislabel the charset (e.g. declare iso-2022-jp on a UTF-8 body —
    # B0001/0018), which produces a body full of U+FFFD replacement chars. If the
    # declared decode looks corrupt, retry as utf-8 and keep whichever is cleaner.
    if charset.lower() not in ("utf-8", "utf8") and primary.count("�") > 2:
        alt = payload.decode("utf-8", errors="replace")
        if alt.count("�") < primary.count("�"):
            return alt
    return primary


def parse_email_message(raw_email: bytes) -> dict:
    """Parse an RFC822 email."""
    msg = email.message_from_bytes(raw_email)

    # Parse From
    from_header = msg.get('From', '')
    from_name, from_email = extract_email_address(from_header)

    # Parse To (RFC2047 encoded-word decoding — symmetric with From/Subject)
    to_emails = decode_address_list(msg.get('To', ''))

    # Parse Cc (fills the cc field of the compat detail response)
    cc_emails = decode_address_list(msg.get('Cc', ''))

    # Parse Subject
    subject = parse_email_header(msg.get('Subject', '(제목없음)'))

    # Parse Date — preserve the sender's offset, normalize to UTC, then store
    # (naive-UTC convention). Previously an aware datetime was inserted as-is, so
    # the driver dropped the offset and the sender's local wall clock got stored
    # (R0001 "that damn UTC" / 0025.0003-NR). to_storage_utc always stores only the
    # UTC wall clock, and the display serializer (compat._iso) appends +00:00.
    date_header = msg.get('Date')
    try:
        sent_date = to_storage_utc(parsedate_to_datetime(date_header)) if date_header else now_utc_naive()
    except Exception:
        sent_date = now_utc_naive()

    # Extract body
    body_text = ""
    body_html = ""
    attachments = []

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            content_disposition = str(part.get("Content-Disposition", ""))

            # Attachment
            if "attachment" in content_disposition:
                filename = part.get_filename()
                if filename:
                    attachments.append({
                        "filename": parse_email_header(filename),
                        "content": part.get_payload(decode=True),
                        "content_type": content_type,
                        "size": len(part.get_payload(decode=True) or b'')
                    })
            # Body (decode honoring the part charset — B0001/0018 defect 2)
            elif content_type == "text/plain" and not body_text:
                try:
                    body_text = _decode_part_text(part)
                except:
                    body_text = str(part.get_payload())
            elif content_type == "text/html" and not body_html:
                try:
                    body_html = _decode_part_text(part)
                except:
                    body_html = str(part.get_payload())
    else:
        # Single part message
        content_type = msg.get_content_type()
        try:
            if content_type == "text/plain":
                body_text = _decode_part_text(msg)
            elif content_type == "text/html":
                body_html = _decode_part_text(msg)
        except:
            body_text = str(msg.get_payload())

    # Build preview: prefer plain text; if HTML-only, strip tags to plain text (no raw markup — B0001/0018)
    preview = make_preview(body_text, body_html, 100)

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
    """Save the raw email to the filesystem."""
    # {mail_storage_base(account)}/{account_uuid}/messages/{uuid[:2]}/{uuid}.eml
    base_path = Path(mail_storage_base(account_uuid=account_uuid)) / account_uuid / "messages"
    subdir = message_uuid[:2]
    file_path = base_path / subdir / f"{message_uuid}.eml"

    # Create directory
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # Save file
    with open(file_path, 'wb') as f:
        f.write(raw_email)

    return str(file_path)


def save_attachment_to_filesystem(account_uuid: str, attachment_uuid: str, filename: str, content: bytes) -> str:
    """Save an attachment to the filesystem."""
    # {mail_storage_base(account)}/{account_uuid}/attachments/{uuid[:2]}/{uuid}_{filename}
    base_path = Path(mail_storage_base(account_uuid=account_uuid)) / account_uuid / "attachments"
    subdir = attachment_uuid[:2]
    file_path = base_path / subdir / f"{attachment_uuid}_{filename}"

    # Create directory
    file_path.parent.mkdir(parents=True, exist_ok=True)

    # Save file
    with open(file_path, 'wb') as f:
        f.write(content)

    return str(file_path)


def get_or_create_folder_uuid(account_uuid: str, folder_name: str, folder_path: str = None) -> str:
    """Look up or create a folder UUID."""
    # Look up existing folder
    check_query = """
        SELECT folder_uuid FROM mail_folders
        WHERE account_uuid = %s AND folder_name = %s
    """
    existing = db_instance.fetch_one(check_query, (account_uuid, folder_name))

    if existing:
        return existing['folder_uuid']

    # Create a new one if it does not exist
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
    """Actual logic for syncing a specific account's mail."""

    # Duplicate-sync check
    if is_sync_running(account_uuid, folder):
        logger.warn(f"[Sync] 이미 동기화 진행 중 - 계정: {account_uuid}, 폴더: {folder}")
        return {
            "success": False,
            "message": "이미 해당 계정/폴더가 동기화 진행 중입니다",
            "new_mails": 0,
            "total_mails": 0
        }

    # Set the sync-start flag
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
        # 1. Look up account info
        account = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "get_account"),
            (account_uuid,)
        )

        if not account:
            raise Exception("계정을 찾을 수 없음")

        # 2. OAuth for Gmail, otherwise the legacy approach
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

                # DB update
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

        # 4. Secure folder_uuid before selecting the folder
        folder_uuid = get_or_create_folder_uuid(account_uuid, folder, folder)

        # 5. Select folder
        imap.connection.select(folder, readonly=True)


        # 6. Fetch the mail UID list
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

        # Fetch all UIDs from IMAP
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
            # Record sync success and finish

        sync_status[sync_id]["total"] = total
        logger.info(f"[Sync] 계정 {account_uuid} - {folder} 폴더: {total}개 메일 발견")


        # 7. Check already-synced UIDs (kept as-is from the original code)
        existing_uids = set()

        # 8. Iterate over mails and store them (kept as-is from the original code)
        new_count = 0
        for idx, uid in enumerate(mail_uids):
            uid_str = uid.decode()

            # Update progress
            sync_status[sync_id]["current"] = idx + 1


            # Duplicate check
            if uid_str in existing_uids:
                continue

            try:
                # Added here! (check before storing)
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

                # Fetch mail
                status, msg_data = imap.connection.uid('fetch', uid, '(RFC822)')
                if status != 'OK' or not msg_data or not msg_data[0]:
                    continue

                raw_email = msg_data[0][1]

                # Parse mail
                parsed = parse_email_message(raw_email)

                # Generate UUID
                message_uuid = str(uuid.uuid4())

                # Save to filesystem
                email_path = save_email_to_filesystem(account_uuid, message_uuid, raw_email)

                # Save metadata to DB
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
                })  # dictionary!

                # Save attachments
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

            # Update progress
            sync_status[sync_id]["progress"] = idx + 1

        # 8. Close IMAP connection
        imap.disconnect()

        # 9. Save sync log
        log_query = sqloader.load_sql("mail_anchor.json", "sync.insert_sync_log")


        db_instance.execute_query(log_query, {
            "account_uuid": account_uuid,
            "sync_type": "manual",
            "status": "completed",
            "messages_fetched": total,
            "messages_updated": new_count
        })  # ← dictionary!

        # 10. Update the account's last_sync_at
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

        # Clear the sync-complete flag
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

        # Clear the flag on sync failure too
        set_sync_running(account_uuid, folder, False)

        # Delete the failed sync_status after 5 seconds too
        def clear_sync():
            import time
            time.sleep(5)
            if sync_id in sync_status:
                del sync_status[sync_id]

        threading.Thread(target=clear_sync, daemon=True).start()

        # Save failure log
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
    Sync mail for all accounts

    - Only accounts with sync_enabled = TRUE are synced
    - Only each account's INBOX is synced
    """

    request = request_params.model_dump()
    logger.debug(request)
    user_uuid = request['user_uuid']

    # Look up the list of enabled accounts
    accounts = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "accounts.get_accounts"),
        {"user_uuid": user_uuid}
    )

    # Filter to only accounts with sync_enabled = TRUE
    active_accounts = [acc for acc in accounts if acc.get('sync_enabled', True)]

    if not active_accounts:
        return {"success": False, "message": "동기화할 계정이 없습니다"}

    logger.info(f"[Sync All] {len(active_accounts)}개 계정 동기화 시작")

    # Run sync in the background
    for account in active_accounts:
        background_tasks.add_task(
            sync_account_mails,
            account['account_uuid'],
            user_uuid,
            "INBOX"
        )

    # Return immediately (sync proceeds in the background)
    return {
        "success": True,
        "message": f"{len(active_accounts)}개 계정 동기화 시작",
    }


@router.post("/{account_uuid}", dependencies=[Depends(verify_token)])
async def sync_account(
    account_uuid: str,
    request: SyncRequest,
    background_tasks: BackgroundTasks,  # removed = None
    folder: str = "INBOX"
):
    """
    Sync mail for a specific account (IMAP → DB)

    - Syncs the INBOX folder by default
    - Another folder can be specified via the folder parameter
    - Runs in the background
    """

    user_uuid = request.user_uuid

    logger.info(f"[Sync] 동기화 시작 - 계정: {account_uuid}, 폴더: {folder}")

    # Run in the background
    background_tasks.add_task(
        sync_account_mails,
        account_uuid,
        user_uuid,
        folder
    )

    # Respond immediately
    return {
        "success": True,
        "message": f"계정 {account_uuid} 동기화 시작"
    }

@router.get("/status", dependencies=[Depends(verify_token)])
async def get_sync_status():
    """
    Get the status of syncs currently in progress
    """

    logger.debug(f"[SyncStatus] 현재 sync_status: {sync_status}")
    return {
        "syncs": sync_status  # active_syncs → syncs
    }


@router.get("/logs/{account_uuid}", dependencies=[Depends(verify_token)])
async def get_sync_logs(account_uuid: str, limit: int = 20):
    """
    Get the sync logs for a specific account
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
