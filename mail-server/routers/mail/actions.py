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
    permanent: bool = False  # True면 완전 삭제, False면 휴지통 이동


# ========================================
# 읽음/안읽음 처리 API
# ========================================

@router.post("/mark-read", dependencies=[Depends(verify_token)])
async def mark_as_read(request: MarkReadRequest):
    """
    메일 읽음 처리
    
    - 여러 메일을 한번에 처리 가능
    """
    
    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")
    
    # 메일 개수만큼 %s 생성
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
    메일 안읽음 처리
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
    받은편지함 전체 메일 읽음 처리
    
    - 해당 사용자의 받은편지함(inbox) 모든 메일을 읽음 처리
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
# 별표 처리 API
# ========================================

@router.post("/star", dependencies=[Depends(verify_token)])
async def add_star(request: MarkStarRequest):
    """
    메일에 별표 추가
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
    메일 별표 제거
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
# 메일 이동 API
# ========================================

@router.post("/move", dependencies=[Depends(verify_token)])
async def move_mails(request: MoveMailRequest):
    """
    메일을 다른 폴더로 이동
    
    - 여러 메일을 한번에 이동 가능
    - IMAP 서버와 동기화는 하지 않음 (로컬 DB만 변경)
    """
    
    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")
    
    # 대상 폴더 존재 확인
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
# 메일 삭제 API
# ========================================

@router.post("/delete", dependencies=[Depends(verify_token)])
async def delete_mails(request: DeleteMailRequest):
    """
    메일 삭제
    
    - permanent=False: is_deleted 플래그만 설정 (휴지통 이동)
    - permanent=True: DB에서 완전 삭제 (파일은 남겨둠)
    """
    
    if not request.message_uuids:
        raise HTTPException(status_code=400, detail="message_uuids가 비어있음")
    
    placeholders = ','.join(['%s'] * len(request.message_uuids))
    
    if request.permanent:
        # 완전 삭제 (DB에서 삭제)
        query = f"""
            DELETE FROM mail_messages 
            WHERE message_uuid IN ({placeholders})
        """
        action = "완전 삭제"
    else:
        # 소프트 삭제 (is_deleted 플래그)
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
# 메일 복원 API (휴지통에서 복원)
# ========================================

@router.post("/restore", dependencies=[Depends(verify_token)])
async def restore_mails(request: MarkReadRequest):
    """
    삭제된 메일 복원
    
    - is_deleted 플래그를 FALSE로 변경
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
# 핀 고정 API
# ========================================

@router.post("/pin", dependencies=[Depends(verify_token)])
async def pin_mail(request: MarkStarRequest):
    """
    메일 핀 고정
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
    메일 핀 고정 해제
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