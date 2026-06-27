from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse, StreamingResponse
from typing import Optional
from pathlib import Path
import email
from email import policy

from config import settings, db
from routers.login.auth import verify_token
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


# ========================================
# 첨부파일 다운로드 API
# ========================================

@router.get("/attachment/{message_uuid}/{attachment_uuid}", dependencies=[Depends(verify_token)])
async def download_attachment(
    message_uuid: str,
    attachment_uuid: str,
    user_uuid: str
):
    """
    첨부파일 다운로드
    
    - DB에서 첨부파일 정보 조회
    - 파일 시스템에서 파일 읽어서 반환
    """
    
    # 1. DB에서 첨부파일 정보 조회
    query = """
        SELECT a.*, m.account_uuid 
        FROM mail_attachments a
        JOIN mail_messages m ON a.message_uuid = m.message_uuid
        WHERE a.attachment_uuid = %s AND a.message_uuid = %s
    """
    
    attachment = db_instance.fetch_one(query, (attachment_uuid, message_uuid))
    
    if not attachment:
        raise HTTPException(status_code=404, detail="첨부파일을 찾을 수 없음")
    
    # 2. 파일 경로 확인
    file_path = Path(attachment['file_path'])
    
    if not file_path.exists():
        logger.error(f"[Attachment] 파일 없음: {file_path}")
        raise HTTPException(status_code=404, detail="첨부파일이 존재하지 않음")
    
    # 3. 파일 다운로드 응답
    return FileResponse(
        path=str(file_path),
        filename=attachment['filename'],
        media_type=attachment.get('content_type', 'application/octet-stream')
    )


# ========================================
# 메일 본문 전체 조회 API
# ========================================

@router.get("/body/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_mail_body(
    message_uuid: str,
    user_uuid: str
):
    """
    메일 본문 전체 조회
    
    - DB에는 1000자만 저장되어 있음
    - .eml 파일에서 전체 본문 파싱해서 반환
    """
    
    # 1. DB에서 메시지 정보 조회
    query = "SELECT * FROM mail_messages WHERE message_uuid = %s"
    message = db_instance.fetch_one(query, (message_uuid,))
    
    if not message:
        raise HTTPException(status_code=404, detail="메일을 찾을 수 없음")
    
    # 2. .eml 파일 경로 확인
    file_path = Path(message['file_path'])
    
    if not file_path.exists():
        logger.error(f"[Mail Body] 파일 없음: {file_path}")
        # 파일이 없으면 DB에 저장된 부분 본문이라도 반환
        return {
            "success": True,
            "message_uuid": message_uuid,
            "body_text": message.get('body_text', ''),
            "body_html": message.get('body_html', ''),
            "from_file": False
        }
    
    # 3. .eml 파일 파싱
    try:
        with open(file_path, 'rb') as f:
            msg = email.message_from_binary_file(f, policy=policy.default)
        
        body_text = ""
        body_html = ""
        
        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition", ""))
                
                # 첨부파일은 스킵
                if "attachment" in content_disposition:
                    continue
                
                # 본문 추출
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
# 첨부파일 목록 조회 API
# ========================================

@router.get("/attachments/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_mail_attachments(
    message_uuid: str,
    user_uuid: str
):
    """
    특정 메일의 첨부파일 목록 조회
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
# 메일 원본 다운로드 API (.eml)
# ========================================

@router.get("/download/{message_uuid}", dependencies=[Depends(verify_token)])
async def download_mail_eml(
    message_uuid: str,
    user_uuid: str
):
    """
    메일 원본 .eml 파일 다운로드
    
    - 이메일 클라이언트에서 열 수 있는 표준 RFC822 형식
    """
    
    # 1. DB에서 메시지 정보 조회
    query = "SELECT * FROM mail_messages WHERE message_uuid = %s"
    message = db_instance.fetch_one(query, (message_uuid,))
    
    if not message:
        raise HTTPException(status_code=404, detail="메일을 찾을 수 없음")
    
    # 2. .eml 파일 경로 확인
    file_path = Path(message['file_path'])
    
    if not file_path.exists():
        logger.error(f"[EML Download] 파일 없음: {file_path}")
        raise HTTPException(status_code=404, detail="메일 파일이 존재하지 않음")
    
    # 3. 파일명 생성 (제목 기반)
    subject = message.get('subject', 'mail')
    # 파일명에 사용할 수 없는 문자 제거
    safe_subject = "".join(c for c in subject if c.isalnum() or c in (' ', '-', '_')).strip()
    filename = f"{safe_subject[:50]}.eml" if safe_subject else f"{message_uuid}.eml"
    
    # 4. 파일 다운로드 응답
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type="message/rfc822"
    )