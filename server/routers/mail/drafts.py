from fastapi import APIRouter, Depends, HTTPException, Form, UploadFile, File
from typing import Optional, List
from datetime import datetime
from util.mail_time import now_utc_naive
from pydantic import BaseModel

from config import settings, db, mail_storage_base
from routers.login.auth import verify_token
from .sync import make_preview
import LogAssist.log as logger

from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import make_msgid
import os
import uuid as uuid_lib
import time

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


# ========================================
# Request Models
# ========================================

class DraftSaveRequest(BaseModel):
    user_uuid: str
    account_uuid: str
    draft_uuid: Optional[str] = None  # when editing an existing draft
    to_addresses: str = ""
    cc_addresses: Optional[str] = None
    bcc_addresses: Optional[str] = None
    subject: str = ""
    body_text: str = ""
    body_html: str = ""


class DraftDeleteRequest(BaseModel):
    user_uuid: str
    draft_uuid: str


# ========================================
# Draft API
# ========================================

@router.post("/save", dependencies=[Depends(verify_token)])
async def save_draft(request: DraftSaveRequest):
    """
    Save a mail draft

    - If draft_uuid is present, update the existing draft
    - Otherwise create a new one
    """

    try:
        # Look up the drafts folder (create if missing)
        drafts_folder = db_instance.fetch_one(
            """
            SELECT folder_uuid 
            FROM mail_folders 
            WHERE account_uuid = %(account_uuid)s AND folder_type = 'drafts'
            LIMIT 1
            """,
            {"account_uuid": request.account_uuid}
        )
        
        if not drafts_folder:
            folder_uuid = str(uuid_lib.uuid4())
            db_instance.execute_query(
                """
                INSERT INTO mail_folders (folder_uuid, account_uuid, folder_name, folder_type, folder_path)
                VALUES (%(folder_uuid)s, %(account_uuid)s, %(folder_name)s, %(folder_type)s, %(folder_path)s)
                """,
                {
                    "folder_uuid": folder_uuid,
                    "account_uuid": request.account_uuid,
                    "folder_name": "임시보관함",
                    "folder_type": "drafts",
                    "folder_path": "[Gmail]/Drafts"
                }
            )
            drafts_folder = {"folder_uuid": folder_uuid}
            logger.info(f"[Drafts] drafts 폴더 생성: {folder_uuid}")
        
        # Look up account info
        account = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "get_account"),
            (request.account_uuid,)
        )

        if not account:
            raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")

        # Update an existing draft or create a new one
        if request.draft_uuid:
            # Update the existing draft
            message_uuid = request.draft_uuid

            # Update the .eml file
            eml_path = db_instance.fetch_one(
                "SELECT body_file_path FROM mail_messages WHERE message_uuid = %s",
                (message_uuid,)
            )
            
            if eml_path and eml_path['body_file_path']:
                eml_file_path = eml_path['body_file_path']
            else:
                eml_dir = os.path.join(mail_storage_base(account_uuid=request.account_uuid), request.account_uuid, "messages")
                os.makedirs(eml_dir, exist_ok=True)
                eml_file_path = os.path.join(eml_dir, f"{message_uuid}.eml")
            
            # Build the mail message
            msg = MIMEMultipart('alternative')
            msg['From'] = f"{account.get('account_name', '')} <{account['email']}>"
            msg['To'] = request.to_addresses
            if request.cc_addresses:
                msg['Cc'] = request.cc_addresses
            msg['Subject'] = request.subject
            msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S %z')
            
            if request.body_text:
                msg.attach(MIMEText(request.body_text, 'plain', 'utf-8'))
            if request.body_html:
                msg.attach(MIMEText(request.body_html, 'html', 'utf-8'))
            
            # Save the .eml file
            with open(eml_file_path, 'w', encoding='utf-8') as f:
                f.write(msg.as_string())

            # DB update
            db_instance.execute_query(
                """
                UPDATE mail_messages 
                SET to_emails = %(to_emails)s,
                    cc_emails = %(cc_emails)s,
                    bcc_emails = %(bcc_emails)s,
                    subject = %(subject)s,
                    preview = %(preview)s,
                    body_file_path = %(body_file_path)s,
                    modified_at = CURRENT_TIMESTAMP
                WHERE message_uuid = %(message_uuid)s
                """,
                {
                    "message_uuid": message_uuid,
                    "to_emails": request.to_addresses,
                    "cc_emails": request.cc_addresses or '',
                    "bcc_emails": request.bcc_addresses or '',
                    "subject": request.subject,
                    "preview": make_preview(request.body_text, request.body_html, 200),
                    "body_file_path": eml_file_path
                }
            )
            
            logger.info(f"[Drafts] 임시저장 업데이트: {message_uuid}")
            
        else:
            # Create a new draft
            message_uuid = str(uuid_lib.uuid4())
            message_id = make_msgid(domain=account['email'].split('@')[1])
            timestamp = int(time.time() * 1000000)
            uid = -timestamp

            # Create .eml file
            msg = MIMEMultipart('alternative')
            msg['From'] = f"{account.get('account_name', '')} <{account['email']}>"
            msg['To'] = request.to_addresses
            if request.cc_addresses:
                msg['Cc'] = request.cc_addresses
            msg['Subject'] = request.subject
            msg['Date'] = datetime.now().strftime('%a, %d %b %Y %H:%M:%S %z')
            msg['Message-ID'] = message_id
            
            if request.body_text:
                msg.attach(MIMEText(request.body_text, 'plain', 'utf-8'))
            if request.body_html:
                msg.attach(MIMEText(request.body_html, 'html', 'utf-8'))
            
            eml_dir = os.path.join(mail_storage_base(account_uuid=request.account_uuid), request.account_uuid, "messages")
            os.makedirs(eml_dir, exist_ok=True)
            eml_path = os.path.join(eml_dir, f"{message_uuid}.eml")
            
            with open(eml_path, 'w', encoding='utf-8') as f:
                f.write(msg.as_string())
            
            # Save to DB
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
                    "account_uuid": request.account_uuid,
                    "folder_uuid": drafts_folder['folder_uuid'],
                    "message_id": message_id,
                    "uid": uid,
                    "from_email": account['email'],
                    "from_name": account.get('account_name', ''),
                    "to_emails": request.to_addresses,
                    "cc_emails": request.cc_addresses or '',
                    "bcc_emails": request.bcc_addresses or '',
                    "subject": request.subject or '(제목 없음)',
                    "preview": make_preview(request.body_text, request.body_html, 200),
                    "sent_date": now_utc_naive(),       # naive-UTC convention (0025.0003-NR)
                    "received_date": now_utc_naive(),
                    "is_read": True,
                    "is_starred": False,
                    "is_deleted": False,
                    "has_attachments": False,
                    "body_file_path": eml_path
                }
            )
            
            logger.info(f"[Drafts] 임시저장 생성: {message_uuid}")
        
        return {
            "success": True,
            "message": "임시저장 완료",
            "draft_uuid": message_uuid
        }
        
    except Exception as e:
        logger.error(f"[Drafts] 임시저장 실패: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="임시저장 실패")


# ========================================
# Draft delete API
# ========================================

@router.post("/delete", dependencies=[Depends(verify_token)])
async def delete_draft(request: DraftDeleteRequest):
    """
    Delete a draft
    """

    try:
        # Soft-delete in the DB (is_deleted = TRUE)
        db_instance.execute_query(
            """
            UPDATE mail_messages 
            SET is_deleted = TRUE, modified_at = CURRENT_TIMESTAMP
            WHERE message_uuid = %s
            """,
            (request.draft_uuid,)
        )
        
        logger.info(f"[Drafts] 임시저장 삭제: {request.draft_uuid}")
        
        return {
            "success": True,
            "message": "임시저장 삭제 완료"
        }
        
    except Exception as e:
        logger.error(f"[Drafts] 임시저장 삭제 실패: {str(e)}")
        raise HTTPException(status_code=500, detail="임시저장 삭제 실패")
    