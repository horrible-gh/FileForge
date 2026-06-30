from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from typing import Optional, List
from config import settings, db, mail_storage_base
from schemas.mail.accounts import AccountCreateRequest, AccountUpdateRequest, AccountGetRequest
from routers.login.auth import verify_token
from services.imap_service import IMAPService
from services.smtp_service import SMTPService, test_smtp_connection
from .sync import make_preview
from util.crypto import aes_encrypt, aes_decrypt, get_encryption_key, get_encryption_iv, encrypt_password, decrypt_password
from Crypto.Protocol.KDF import PBKDF2
import os
import LogAssist.log as logger
import uuid as uuid_lib
from datetime import datetime
from util.mail_time import now_utc_naive
from email.utils import make_msgid
from email.mime.multipart import MIMEMultipart  # added
from email.mime.text import MIMEText  # added
import os  # added
import time


db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

SECRET_KEY = os.getenv('SECRET_KEY')

# ========================================
# Account management API
# ========================================

@router.get("/accounts/list", dependencies=[Depends(verify_token)])
async def get_accounts(request: AccountGetRequest = Depends()):
    """Get account list"""
    data = request.model_dump()
    accounts = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "accounts.get_accounts"),
        data
    )
    return {"success": True, "accounts": accounts}


@router.post("/accounts/test", dependencies=[Depends(verify_token)])
async def test_account_connection(request: AccountCreateRequest):
    """Test account connection"""
    data = request.model_dump()

    # IMAP test
    imap_result = {"success": False, "message": ""}
    try:
        imap = IMAPService(
            host=data['imap_host'],
            port=data['imap_port'],
            username=data['imap_username'],
            password=data['imap_password'],
            use_ssl=data.get('imap_use_ssl', True)
        )
        imap_result = imap.connect()
        imap.disconnect()
    except Exception as e:
        imap_result = {"success": False, "message": str(e)}

    # SMTP test
    smtp_result = test_smtp_connection(
        host=data['smtp_host'],
        port=data['smtp_port'],
        username=data['smtp_username'],
        password=data['smtp_password']
    )

    return {"imap": imap_result, "smtp": smtp_result}


@router.post("/accounts/create", dependencies=[Depends(verify_token)])
async def create_account(request: AccountCreateRequest):
    """Create account"""
    data = request.model_dump()
    user_uuid = data['user_uuid']

    # Encrypt passwords
    encrypted_imap_pw = encrypt_password(user_uuid, data['imap_password'])
    encrypted_smtp_pw = encrypt_password(user_uuid, data['smtp_password'])

    query_data = {
        "user_uuid": user_uuid,
        "account_name": data['account_name'],
        "email": data['email'],
        "imap_host": data['imap_host'],
        "imap_port": data['imap_port'],
        "imap_use_ssl": data.get('imap_use_ssl', True),
        "imap_username": data['imap_username'],
        "imap_password_encrypted": encrypted_imap_pw,
        "smtp_host": data['smtp_host'],
        "smtp_port": data['smtp_port'],
        "smtp_use_tls": data.get('smtp_use_tls', True),
        "smtp_username": data['smtp_username'],
        "smtp_password_encrypted": encrypted_smtp_pw,
        "display_color": data.get('display_color', '#4285f4')
    }

    result = db_instance.execute_query(
        sqloader.load_sql("mail_anchor.json", "accounts.insert_account"),
        query_data
    )

    return {"success": True, "message": "계정 추가 완료", **result}


@router.put("/accounts/update", dependencies=[Depends(verify_token)])
async def update_account(request: AccountUpdateRequest):
    """Update account"""
    data = request.model_dump()
    user_uuid = data['user_uuid']

    query_data = {
        "account_uuid": data['account_uuid'],
        "user_uuid": user_uuid,
        "account_name": data.get('account_name'),
        "imap_password_encrypted": encrypt_password(user_uuid, data['imap_password']) if data.get('imap_password') else None,
        "smtp_password_encrypted": encrypt_password(user_uuid, data['smtp_password']) if data.get('smtp_password') else None,
        "display_color": data.get('display_color'),
        "sync_enabled": data.get('sync_enabled')
    }

    result = db_instance.execute_query(
        sqloader.load_sql("mail_anchor.json", "accounts.update_account"),
        query_data
    )

    return {"success": True, "message": "계정 수정 완료", **result}


@router.delete("/accounts/delete/{account_uuid}", dependencies=[Depends(verify_token)])
async def delete_account(account_uuid: str):
    """Delete account"""
    result = db_instance.execute_query(
        sqloader.load_sql("mail_anchor.json", "accounts.remove_account"),
        {"account_uuid": account_uuid}
    )
    return {"success": True, "message": "계정 삭제 완료", **result}


# ========================================
# Folder API
# ========================================

@router.get("/folders/{account_uuid}", dependencies=[Depends(verify_token)])
async def get_account_folders(account_uuid: str, user_uuid: str):
    """Folder list for a specific account (fetched from IMAP)"""
    # Look up account info from the DB
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "get_account"),
        (account_uuid,)
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")

    # Decrypt password
    imap_password = decrypt_password(user_uuid, account['imap_password_encrypted'])

    # IMAP connection
    imap = IMAPService(
        host=account['imap_host'],
        port=account['imap_port'],
        username=account['imap_username'],
        password=imap_password,
        use_ssl=account.get('imap_use_ssl', True)
    )

    connect_result = imap.connect()
    if not connect_result["success"]:
        raise HTTPException(status_code=500, detail="IMAP 연결 실패: " + connect_result["message"])

    folders_result = imap.get_folders()
    imap.disconnect()

    if not folders_result["success"]:
        raise HTTPException(status_code=500, detail="폴더 조회 실패")

    return folders_result


# ========================================
# Mail list API
# ========================================

@router.get("/list/{account_uuid}", dependencies=[Depends(verify_token)])
async def get_mail_list(
    account_uuid: str,
    user_uuid: str,
    folder: str = "INBOX",
    page: int = 1,
    limit: int = 20,
    search: Optional[str] = None
):
    """Mail list for a specific account/folder"""
    # Look up account info from the DB
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "get_account"),
        (account_uuid,)
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")

    # Decrypt password
    imap_password = decrypt_password(user_uuid, account['imap_password_encrypted'])

    # IMAP connection
    imap = IMAPService(
        host=account['imap_host'],
        port=account['imap_port'],
        username=account['imap_username'],
        password=imap_password,
        use_ssl=account.get('imap_use_ssl', True)
    )

    connect_result = imap.connect()
    if not connect_result["success"]:
        raise HTTPException(status_code=500, detail="IMAP 연결 실패")

    mail_list = imap.get_mail_list(
        folder=folder,
        page=page,
        limit=limit,
        search_query=search
    )

    imap.disconnect()

    return mail_list


# ========================================
# Mail detail API
# ========================================

@router.get("/detail/{account_uuid}/{mail_uid}", dependencies=[Depends(verify_token)])
async def get_mail_detail(
    account_uuid: str,
    mail_uid: str,
    user_uuid: str,
    folder: str = "INBOX"
):
    """Get mail detail"""
    # Look up account info from the DB
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "get_account"),
        (account_uuid,)
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")

    # Decrypt password
    imap_password = decrypt_password(settings.SECRET_KEY, user_uuid, account['imap_password_encrypted'])

    # IMAP connection
    imap = IMAPService(
        host=account['imap_host'],
        port=account['imap_port'],
        username=account['imap_username'],
        password=imap_password,
        use_ssl=account.get('imap_use_ssl', True)
    )

    connect_result = imap.connect()
    if not connect_result["success"]:
        raise HTTPException(status_code=500, detail="IMAP 연결 실패")

    mail_detail = imap.get_mail_detail(folder=folder, mail_uid=mail_uid)
    imap.disconnect()

    if not mail_detail["success"]:
        raise HTTPException(status_code=404, detail=mail_detail["message"])

    return mail_detail


# ========================================
# Mail send API
# ========================================

@router.post("/send", dependencies=[Depends(verify_token)])
async def send_mail(
    account_uuid: str = Form(...),
    user_uuid: str = Form(...),
    to_addresses: str = Form(...),
    subject: str = Form(...),
    body_text: str = Form(""),
    body_html: str = Form(""),
    cc_addresses: Optional[str] = Form(None),
    bcc_addresses: Optional[str] = Form(None),
    files: List[UploadFile] = File(default=[])
):
    """Send mail"""
    # Look up account info from the DB
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "get_account"),
        (account_uuid,)
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")

    # Parse addresses
    to_list = [addr.strip() for addr in to_addresses.split(",")]
    cc_list = [addr.strip() for addr in cc_addresses.split(",")] if cc_addresses else None
    bcc_list = [addr.strip() for addr in bcc_addresses.split(",")] if bcc_addresses else None

    # Handle attachments
    attachments = []
    for file in files:
        content = await file.read()
        attachments.append({
            "filename": file.filename,
            "content": content,
            "content_type": file.content_type or "application/octet-stream"
        })

    # Gmail OAuth vs regular SMTP
    if account.get('account_type') == 'gmail':
        from services.gmail_service import GmailSMTPService, GmailOAuthService

        smtp = None
        try:
            if not account.get('refresh_token_encrypted'):
                raise HTTPException(status_code=500, detail="Gmail refresh token이 없습니다. 재인증이 필요합니다.")

            refresh_token = decrypt_password(settings.SECRET_KEY, user_uuid, account['refresh_token_encrypted'])
            gmail_oauth = GmailOAuthService()

            token_data = await gmail_oauth.refresh_access_token(refresh_token)
            access_token = token_data['access_token']

            smtp = GmailSMTPService(account['email'], access_token)
            connect_result = smtp.connect()
            if not connect_result["success"]:
                raise HTTPException(status_code=500, detail=f"Gmail SMTP 연결 실패: {connect_result['message']}")

            # GmailSMTPService.send_mail is a simple version, so send directly
            from email.mime.multipart import MIMEMultipart
            from email.mime.text import MIMEText
            from email.mime.base import MIMEBase
            from email import encoders

            msg = MIMEMultipart('mixed')
            msg['From'] = f"{account.get('account_name', '')} <{account['email']}>"
            msg['To'] = ', '.join(to_list)
            if cc_list:
                msg['Cc'] = ', '.join(cc_list)
            msg['Subject'] = subject

            # Body
            if body_html:
                msg.attach(MIMEText(body_html, 'html', 'utf-8'))
            elif body_text:
                msg.attach(MIMEText(body_text, 'plain', 'utf-8'))

            # Attachments
            for attach in attachments:
                part = MIMEBase('application', 'octet-stream')
                part.set_payload(attach['content'])
                encoders.encode_base64(part)
                part.add_header('Content-Disposition', f'attachment; filename="{attach["filename"]}"')
                msg.attach(part)

            all_recipients = to_list + (cc_list or []) + (bcc_list or [])
            smtp.connection.sendmail(account['email'], all_recipients, msg.as_string())
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"[Send Mail] Gmail 발송 실패: {str(e)}")
            raise HTTPException(status_code=500, detail=f"Gmail 메일 발송 실패: {str(e)}")
        finally:
            if smtp:
                smtp.disconnect()

        send_result = {"success": True, "message": "메일 발송 완료"}

    else:
        # Legacy SMTP approach
        smtp = None
        try:
            smtp_password = decrypt_password(settings.SECRET_KEY, user_uuid, account['smtp_password_encrypted'])

            smtp = SMTPService(
                host=account['smtp_host'],
                port=account['smtp_port'],
                username=account['smtp_username'],
                password=smtp_password
            )

            connect_result = smtp.connect()
            if not connect_result["success"]:
                raise HTTPException(status_code=500, detail=f"SMTP 연결 실패: {connect_result['message']}")

            send_result = smtp.send_mail(
                from_name=account.get('account_name', account['email']),
                from_email=account['email'],
                to_addresses=to_list,
                subject=subject,
                body_text=body_text,
                body_html=body_html,
                cc_addresses=cc_list,
                bcc_addresses=bcc_list,
                attachments=attachments if attachments else None
            )
        except HTTPException:
            raise
        except Exception as e:
            logger.error(f"[Send Mail] SMTP 발송 실패: {str(e)}")
            raise HTTPException(status_code=500, detail=f"메일 발송 실패: {str(e)}")
        finally:
            if smtp:
                smtp.disconnect()

    if not send_result["success"]:
        raise HTTPException(status_code=500, detail=send_result["message"])

    # Save to the sent mailbox
    # Save to the sent mailbox
    try:
        # Look up the sent folder (create if missing)
        sent_folder = db_instance.fetch_one(
            """
            SELECT folder_uuid
            FROM mail_folders
            WHERE account_uuid = %(account_uuid)s AND folder_type = 'sent'
            LIMIT 1
            """,
            {"account_uuid": account_uuid}
        )

        # Create the sent folder if missing
        if not sent_folder:
            folder_uuid = str(uuid_lib.uuid4())
            db_instance.execute_query(
                """
                INSERT INTO mail_folders (folder_uuid, account_uuid, folder_name, folder_type, folder_path)
                VALUES (%(folder_uuid)s, %(account_uuid)s, %(folder_name)s, %(folder_type)s, %(folder_path)s)
                """,
                {
                    "folder_uuid": folder_uuid,
                    "account_uuid": account_uuid,
                    "folder_name": "보낸편지함",
                    "folder_type": "sent",
                    "folder_path": "[Gmail]/Sent Mail"
                }
            )
            sent_folder = {"folder_uuid": folder_uuid}
            logger.info(f"[Send Mail] sent 폴더 생성: {folder_uuid}")

        message_uuid = str(uuid_lib.uuid4())
        timestamp = int(time.time() * 1000000)  # microseconds
        message_id = f"<{message_uuid}.{timestamp}@{account['email'].split('@')[1]}>"
        uid = -timestamp  # set negative (IMAP UIDs use positive values only)

        # Create .eml file
        msg = MIMEMultipart('alternative')
        msg['From'] = f"{account.get('account_name', '')} <{account['email']}>"
        msg['To'] = to_addresses
        if cc_addresses:
            msg['Cc'] = cc_addresses
        msg['Subject'] = subject
        msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S %z')
        msg['Message-ID'] = message_id

        # Add body
        if body_text:
            msg.attach(MIMEText(body_text, 'plain', 'utf-8'))
        if body_html:
            msg.attach(MIMEText(body_html, 'html', 'utf-8'))

        # .eml file save path
        eml_dir = os.path.join(mail_storage_base(account_uuid=account_uuid), account_uuid, "messages")
        os.makedirs(eml_dir, exist_ok=True)
        eml_path = os.path.join(eml_dir, f"{message_uuid}.eml")

        with open(eml_path, 'w', encoding='utf-8') as f:
            f.write(msg.as_string())

        logger.info(f"[Send Mail] .eml 파일 저장: {eml_path}")

        # Save the mail message to the DB
        db_instance.execute_query(
            """
            INSERT INTO mail_messages (
                message_uuid, account_uuid, folder_uuid,
                message_id, uid,
                from_email, from_name, to_emails, cc_emails, bcc_emails,
                subject, preview, sent_date, received_date,
                is_read, is_starred, is_deleted, has_attachments,
                body_file_path
            ) VALUES (
                %(message_uuid)s, %(account_uuid)s, %(folder_uuid)s,
                %(message_id)s, %(uid)s,
                %(from_email)s, %(from_name)s, %(to_emails)s, %(cc_emails)s, %(bcc_emails)s,
                %(subject)s, %(preview)s, %(sent_date)s, %(received_date)s,
                %(is_read)s, %(is_starred)s, %(is_deleted)s, %(has_attachments)s,
                %(body_file_path)s
            )
            """,
            {
                "message_uuid": message_uuid,
                "account_uuid": account_uuid,
                "folder_uuid": sent_folder['folder_uuid'],
                "message_id": message_id,
                "uid": uid,
                "from_email": account['email'],
                "from_name": account.get('account_name', ''),
                "to_emails": to_addresses,
                "cc_emails": cc_addresses or '',
                "bcc_emails": bcc_addresses or '',
                "subject": subject,
                "preview": make_preview(body_text, body_html, 200),
                "sent_date": now_utc_naive(),       # naive-UTC convention (0025.0003-NR)
                "received_date": now_utc_naive(),
                "is_read": True,
                "is_starred": False,
                "is_deleted": False,
                "has_attachments": len(attachments) > 0,
                "body_file_path": eml_path  # added
            }
        )

        logger.info(f"[Send Mail] 보낸편지함에 저장 완료: {message_uuid}")

    except Exception as e:
        logger.error(f"[Send Mail] 보낸편지함 저장 실패: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())

    return send_result
