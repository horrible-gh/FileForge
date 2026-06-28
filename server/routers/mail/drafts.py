from fastapi import APIRouter, Depends, HTTPException, Form, UploadFile, File
from typing import Optional, List
from datetime import datetime
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
    draft_uuid: Optional[str] = None  # 기존 임시저장 수정 시
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
# 임시저장 API
# ========================================

@router.post("/save", dependencies=[Depends(verify_token)])
async def save_draft(request: DraftSaveRequest):
    """
    메일 임시저장
    
    - draft_uuid가 있으면 기존 임시저장 업데이트
    - 없으면 새로 생성
    """
    
    try:
        # drafts 폴더 조회 (없으면 생성)
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
        
        # 계정 정보 조회
        account = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "get_account"),
            (request.account_uuid,)
        )
        
        if not account:
            raise HTTPException(status_code=404, detail="계정을 찾을 수 없음")
        
        # 기존 임시저장 수정 또는 신규 생성
        if request.draft_uuid:
            # 기존 임시저장 업데이트
            message_uuid = request.draft_uuid
            
            # .eml 파일 업데이트
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
            
            # 메일 메시지 생성
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
            
            # .eml 파일 저장
            with open(eml_file_path, 'w', encoding='utf-8') as f:
                f.write(msg.as_string())
            
            # DB 업데이트
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
            # 신규 임시저장 생성
            message_uuid = str(uuid_lib.uuid4())
            message_id = make_msgid(domain=account['email'].split('@')[1])
            timestamp = int(time.time() * 1000000)
            uid = -timestamp
            
            # .eml 파일 생성
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
            
            # DB 저장
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
                    "sent_date": datetime.now(),
                    "received_date": datetime.now(),
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
# 임시저장 삭제 API
# ========================================

@router.post("/delete", dependencies=[Depends(verify_token)])
async def delete_draft(request: DraftDeleteRequest):
    """
    임시저장 삭제
    """
    
    try:
        # DB에서 삭제 (is_deleted = TRUE)
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
    