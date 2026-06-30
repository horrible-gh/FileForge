from fastapi import APIRouter, Depends, HTTPException
from typing import List, Optional
from pydantic import BaseModel

from config import settings, db
from routers.login.auth import verify_token
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


# ========================================
# Request Models
# ========================================

class MarkReadRequest(BaseModel):
    message_uuids: List[str]
    user_uuid: str


class MarkReadAllRequest(BaseModel):
    user_uuid: str

class MarkStarRequest(BaseModel):
    message_uuid: str
    user_uuid: str


class MoveMailRequest(BaseModel):
    message_uuids: List[str]
    target_folder_uuid: str
    user_uuid: str


class DeleteMailRequest(BaseModel):
    message_uuids: List[str]
    user_uuid: str
    permanent: bool = False  # True = permanent delete, False = move to trash


# ========================================
# Read/unread API
# ========================================

@router.post("/mark-read", dependencies=[Depends(verify_token)])
async def mark_as_read(request: MarkReadRequest):
    """
    Mark mail as read

    - Can process multiple mails at once
    """

    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")

    # Build %s placeholders for the number of mails
    placeholders = ','.join(['%s'] * len(request.message_uuids))
    
    query = f"""
        UPDATE mail_messages 
        SET is_read = TRUE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid IN ({placeholders})
    """
    
    result = db_instance.execute_query(query, tuple(request.message_uuids))
    
    logger.info(f"[Mark Read] {len(request.message_uuids)}개 메일 읽음 처리")
    
    return {
        "success": True,
        "message": f"{len(request.message_uuids)}개 메일 읽음 처리 완료",
        "count": len(request.message_uuids)
    }


@router.post("/mark-unread", dependencies=[Depends(verify_token)])
async def mark_as_unread(request: MarkReadRequest):
    """
    Mark mail as unread
    """
    
    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")
    
    placeholders = ','.join(['%s'] * len(request.message_uuids))
    
    query = f"""
        UPDATE mail_messages 
        SET is_read = FALSE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid IN ({placeholders})
    """
    
    result = db_instance.execute_query(query, tuple(request.message_uuids))
    
    logger.info(f"[Mark Unread] {len(request.message_uuids)}개 메일 안읽음 처리")
    
    return {
        "success": True,
        "message": f"{len(request.message_uuids)}개 메일 안읽음 처리 완료",
        "count": len(request.message_uuids)
    }

@router.post("/mark-all-read", dependencies=[Depends(verify_token)])
async def mark_all_as_read(request: MarkReadAllRequest):
    """
    Mark all inbox mail as read

    - Marks all mail in the user's inbox as read
    """

    user_uuid = request.user_uuid
    
    query = """
        UPDATE mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
        SET m.is_read = TRUE, m.modified_at = CURRENT_TIMESTAMP
        WHERE a.user_uuid = %s
          AND a.status = 'active'
          AND f.folder_type = 'inbox'
          AND m.is_deleted = FALSE
          AND m.is_read = FALSE
    """
    
    affected_rows = db_instance.execute_query(query, (user_uuid,))
    
    logger.info(f"[Mark All Read] 사용자 {user_uuid} - {affected_rows}개 메일 읽음 처리")
    
    return {
        "success": True,
        "message": f"{affected_rows}개 메일을 읽음 처리했습니다",
        "count": affected_rows
    }

# ========================================
# Star API
# ========================================

@router.post("/star", dependencies=[Depends(verify_token)])
async def add_star(request: MarkStarRequest):
    """
    Add a star to a mail
    """
    
    query = """
        UPDATE mail_messages 
        SET is_starred = TRUE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid = %s
    """
    
    result = db_instance.execute_query(query, (request.message_uuid,))
    
    logger.info(f"[Star] 메일 {request.message_uuid} 별표 추가")
    
    return {
        "success": True,
        "message": "별표 추가 완료",
        "message_uuid": request.message_uuid
    }


@router.post("/unstar", dependencies=[Depends(verify_token)])
async def remove_star(request: MarkStarRequest):
    """
    Remove a star from a mail
    """
    
    query = """
        UPDATE mail_messages 
        SET is_starred = FALSE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid = %s
    """
    
    result = db_instance.execute_query(query, (request.message_uuid,))
    
    logger.info(f"[Unstar] 메일 {request.message_uuid} 별표 제거")
    
    return {
        "success": True,
        "message": "별표 제거 완료",
        "message_uuid": request.message_uuid
    }


# ========================================
# Mail move API
# ========================================

@router.post("/move", dependencies=[Depends(verify_token)])
async def move_mails(request: MoveMailRequest):
    """
    Move mail to another folder

    - Can move multiple mails at once
    - Does not sync with the IMAP server (changes the local DB only)
    """

    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")

    # Verify the target folder exists
    folder_check = db_instance.fetch_one(
        "SELECT folder_uuid FROM mail_folders WHERE folder_uuid = %s",
        (request.target_folder_uuid,)
    )
    
    if not folder_check:
        raise HTTPException(status_code=404, detail="대상 폴더를 찾을 수 없음")
    
    placeholders = ','.join(['%s'] * len(request.message_uuids))
    
    query = f"""
        UPDATE mail_messages 
        SET folder_uuid = %s, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid IN ({placeholders})
    """
    
    params = [request.target_folder_uuid] + request.message_uuids
    result = db_instance.execute_query(query, tuple(params))
    
    logger.info(f"[Move] {len(request.message_uuids)}개 메일을 폴더 {request.target_folder_uuid}로 이동")
    
    return {
        "success": True,
        "message": f"{len(request.message_uuids)}개 메일 이동 완료",
        "count": len(request.message_uuids),
        "target_folder_uuid": request.target_folder_uuid
    }


# ========================================
# Mail delete API
# ========================================

@router.post("/delete", dependencies=[Depends(verify_token)])
async def delete_mails(request: DeleteMailRequest):
    """
    Delete mail

    - permanent=False: only sets the is_deleted flag (move to trash)
    - permanent=True: permanently deletes from the DB (files are kept)
    """

    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")

    placeholders = ','.join(['%s'] * len(request.message_uuids))

    if request.permanent:
        # Permanent delete (delete from DB)
        query = f"""
            DELETE FROM mail_messages
            WHERE message_uuid IN ({placeholders})
        """
        action = "완전 삭제"
    else:
        # Soft delete (is_deleted flag)
        query = f"""
            UPDATE mail_messages 
            SET is_deleted = TRUE, modified_at = CURRENT_TIMESTAMP
            WHERE message_uuid IN ({placeholders})
        """
        action = "휴지통 이동"
    
    result = db_instance.execute_query(query, tuple(request.message_uuids))
    
    logger.info(f"[Delete] {len(request.message_uuids)}개 메일 {action}")
    
    return {
        "success": True,
        "message": f"{len(request.message_uuids)}개 메일 {action} 완료",
        "count": len(request.message_uuids),
        "permanent": request.permanent
    }


# ========================================
# Mail restore API (restore from trash)
# ========================================

@router.post("/restore", dependencies=[Depends(verify_token)])
async def restore_mails(request: MarkReadRequest):
    """
    Restore deleted mail

    - Changes the is_deleted flag to FALSE
    """
    
    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")
    
    placeholders = ','.join(['%s'] * len(request.message_uuids))
    
    query = f"""
        UPDATE mail_messages 
        SET is_deleted = FALSE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid IN ({placeholders})
    """
    
    result = db_instance.execute_query(query, tuple(request.message_uuids))
    
    logger.info(f"[Restore] {len(request.message_uuids)}개 메일 복원")
    
    return {
        "success": True,
        "message": f"{len(request.message_uuids)}개 메일 복원 완료",
        "count": len(request.message_uuids)
    }

# ========================================
# Pin API
# ========================================

@router.post("/pin", dependencies=[Depends(verify_token)])
async def pin_mail(request: MarkStarRequest):
    """
    Pin a mail
    """
    
    query = """
        UPDATE mail_messages 
        SET is_pinned = TRUE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid = %s
    """
    
    result = db_instance.execute_query(query, (request.message_uuid,))
    
    logger.info(f"[Pin] 메일 핀 고정: {request.message_uuid}")
    
    return {
        "success": True,
        "message": "메일 핀 고정 완료"
    }


@router.post("/unpin", dependencies=[Depends(verify_token)])
async def unpin_mail(request: MarkStarRequest):
    """
    Unpin a mail
    """
    
    query = """
        UPDATE mail_messages 
        SET is_pinned = FALSE, modified_at = CURRENT_TIMESTAMP
        WHERE message_uuid = %s
    """
    
    result = db_instance.execute_query(query, (request.message_uuid,))
    
    logger.info(f"[Unpin] 메일 핀 고정 해제: {request.message_uuid}")
    
    return {
        "success": True,
        "message": "메일 핀 고정 해제 완료"
    }