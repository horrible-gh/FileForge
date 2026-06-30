from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from typing import Optional
from pathlib import Path
import email
from email import policy

from config import settings, db
from routers.login.auth import verify_token, current_user_uuid
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


# ========================================
# Attachment download API
# ========================================

@router.get("/attachment/{message_uuid}/{attachment_uuid}")
async def download_attachment(
    message_uuid: str,
    attachment_uuid: str,
    user_uuid: str = Depends(current_user_uuid)
):
    """
    Download an attachment

    - Derive user_uuid from the auth token (blocks IDOR): scope by
      mail_accounts.user_uuid so only attachments on mail belonging to an
      account the caller owns are retrievable.
    - Look up attachment info from the DB
    - Read the file from the filesystem and return it
    """

    # 1. Look up attachment info from the DB (user-scoped — blocks IDOR)
    query = sqloader.load_sql("mail_anchor.json", "inbox.get_attachment_for_download")

    attachment = db_instance.fetch_one(query, (attachment_uuid, message_uuid, user_uuid))
    
    if not attachment:
        raise HTTPException(status_code=404, detail="첨부파일을 찾을 수 없음")
    
    # 2. Verify file path
    file_path = Path(attachment['file_path'])

    if not file_path.exists():
        logger.error(f"[Attachment] 파일 없음: {file_path}")
        raise HTTPException(status_code=404, detail="첨부파일이 존재하지 않음")

    # 3. File download response
    return FileResponse(
        path=str(file_path),
        filename=attachment['filename'],
        media_type=attachment.get('content_type', 'application/octet-stream')
    )


# ========================================
# Full mail body API
# ========================================

@router.get("/body/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_mail_body(
    message_uuid: str,
    user_uuid: str
):
    """
    Get the full mail body

    - Only 1000 chars are stored in the DB
    - Parse and return the full body from the .eml file
    """

    # 1. Look up message info from the DB
    query = "SELECT * FROM mail_messages WHERE message_uuid = %s"
    message = db_instance.fetch_one(query, (message_uuid,))

    if not message:
        raise HTTPException(status_code=404, detail="메일을 찾을 수 없음")

    # 2. Verify .eml file path
    file_path = Path(message['file_path'])

    if not file_path.exists():
        logger.error(f"[Mail Body] 파일 없음: {file_path}")
        # If the file is missing, return at least the partial body stored in the DB
        return {
            "success": True,
            "message_uuid": message_uuid,
            "body_text": message.get('body_text', ''),
            "body_html": message.get('body_html', ''),
            "from_file": False
        }
    
    # 3. Parse the .eml file
    try:
        with open(file_path, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        body_text = ""
        body_html = ""
        
        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition", ""))
                
                # Skip attachments
                if "attachment" in content_disposition:
                    continue

                # Extract body
                if content_type == "text/plain" and not body_text:
                    try:
                        body_text = part.get_content()
                    except:
                        body_text = str(part.get_payload(decode=True), errors='ignore')
                
                elif content_type == "text/html" and not body_html:
                    try:
                        body_html = part.get_content()
                    except:
                        body_html = str(part.get_payload(decode=True), errors='ignore')
        else:
            # Single part message
            content_type = msg.get_content_type()
            try:
                content = msg.get_content()
                if content_type == "text/plain":
                    body_text = content
                elif content_type == "text/html":
                    body_html = content
            except:
                payload = msg.get_payload(decode=True)
                if content_type == "text/plain":
                    body_text = str(payload, errors='ignore')
                elif content_type == "text/html":
                    body_html = str(payload, errors='ignore')
        
        return {
            "success": True,
            "message_uuid": message_uuid,
            "body_text": body_text,
            "body_html": body_html,
            "from_file": True
        }
        
    except Exception as e:
        logger.error(f"[Mail Body] 파싱 실패: {str(e)}")
        raise HTTPException(status_code=500, detail=f"메일 본문 파싱 실패: {str(e)}")


# ========================================
# Attachment list API
# ========================================

@router.get("/attachments/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_mail_attachments(
    message_uuid: str,
    user_uuid: str
):
    """
    Get the attachment list for a specific mail
    """
    
    query = """
        SELECT attachment_uuid, filename, content_type, size_bytes, created_at
        FROM mail_attachments
        WHERE message_uuid = %s
        ORDER BY created_at
    """
    
    attachments = db_instance.fetch_all(query, (message_uuid,))
    
    return {
        "success": True,
        "message_uuid": message_uuid,
        "count": len(attachments),
        "attachments": attachments
    }


# ========================================
# Raw mail (.eml) download API
# ========================================

@router.get("/download/{message_uuid}", dependencies=[Depends(verify_token)])
async def download_mail_eml(
    message_uuid: str,
    user_uuid: str
):
    """
    Download the raw .eml mail file

    - Standard RFC822 format that can be opened in an email client
    """

    # 1. Look up message info from the DB
    query = "SELECT * FROM mail_messages WHERE message_uuid = %s"
    message = db_instance.fetch_one(query, (message_uuid,))

    if not message:
        raise HTTPException(status_code=404, detail="메일을 찾을 수 없음")

    # 2. Verify .eml file path
    file_path = Path(message['file_path'])

    if not file_path.exists():
        logger.error(f"[EML Download] 파일 없음: {file_path}")
        raise HTTPException(status_code=404, detail="메일 파일이 존재하지 않음")

    # 3. Build filename (based on subject)
    subject = message.get('subject', 'mail')
    # Remove characters that cannot be used in a filename
    safe_subject = "".join(c for c in subject if c.isalnum() or c in (' ', '-', '_')).strip()
    filename = f"{safe_subject[:50]}.eml" if safe_subject else f"{message_uuid}.eml"

    # 4. File download response
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type="message/rfc822"
    )