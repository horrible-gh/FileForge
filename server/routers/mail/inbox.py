from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List
from datetime import datetime, timedelta

from config import settings, db
from routers.login.auth import verify_token
import LogAssist.log as logger

from email import policy
from email.parser import BytesParser
import os


db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


# ========================================
# Unified inbox API
# ========================================

@router.get("/unified-inbox", dependencies=[Depends(verify_token)])
async def get_unified_inbox(
    user_uuid: str,
    page: int = 1,
    limit: int = 50,
    folder_type: Optional[str] = None,  # added: 'inbox', 'sent', 'drafts', 'trash', 'spam'
    unread_only: bool = False,
    starred_only: bool = False
):
    """
    Unified view across all accounts' inboxes

    - Sorts INBOX folder mail from all accounts newest-first
    - Supports paging
    - Can filter to unread-only / starred-only
    - folder_type can distinguish folders (inbox/sent/drafts/trash/spam)
    """

    offset = (page - 1) * limit

    # Build WHERE conditions
    # Fix: is_deleted = TRUE for trash, otherwise FALSE
    if folder_type == 'trash':
        where_conditions = ["m.is_deleted = TRUE"]
    else:
        where_conditions = ["m.is_deleted = FALSE"]

    # Add folder_type filter
    if folder_type:
        if folder_type == 'starred':
            where_conditions.append("m.is_starred = TRUE")
        elif folder_type != 'trash':  # trash is filtered by is_deleted, so exclude
            where_conditions.append("f.folder_type = %s")
    
    if unread_only:
        where_conditions.append("m.is_read = FALSE")
    
    if starred_only:
        where_conditions.append("m.is_starred = TRUE")
    
    where_clause = " AND ".join(where_conditions)
    
    query_integrated_mail1 = sqloader.load_sql("mail_anchor.json", "inbox.get_integrated_mail1")
    query_integrated_mail2 = sqloader.load_sql("mail_anchor.json", "inbox.get_integrated_mail2")

    # Unified mail query
    query = f"""
        {query_integrated_mail1}
          AND {where_clause}
        {query_integrated_mail2}
    """
    
    # Build params
    params = [user_uuid]
    if folder_type and folder_type not in ['starred', 'trash']:  # exclude trash too
        params.append(folder_type)
    params.extend([limit, offset])
    
    messages = db_instance.fetch_all(query, tuple(params))

    query_integrated_count = sqloader.load_sql("mail_anchor.json", "inbox.get_integrated_count")

    # Get total count
    count_query = f"""
        {query_integrated_count}
          AND {where_clause}
    """

    # count params (excluding limit/offset)
    count_params = [user_uuid]
    if folder_type and folder_type not in ['starred', 'trash']:  # exclude trash too
        count_params.append(folder_type)
    
    total_result = db_instance.fetch_one(count_query, tuple(count_params))
    total = total_result['total'] if total_result else 0
    
    logger.info(f"[Unified Inbox] 사용자 {user_uuid} - {len(messages)}개 메일 조회 (총 {total}개, folder_type: {folder_type})")
    
    return {
        "success": True,
        "messages": messages,
        "has_more": len(messages) == limit,
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": (total + limit - 1) // limit
        }
    }


# ========================================
# Mail search API
# ========================================

@router.get("/search", dependencies=[Depends(verify_token)])
async def search_mails(
    user_uuid: str,
    query: str = Query(..., min_length=1),
    account_uuid: Optional[str] = None,
    folder_uuid: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    has_attachments: Optional[bool] = None,
    unread_only: bool = False,
    starred_only: bool = False,
    page: int = 1,
    limit: int = 50
):
    """
    Mail search

    - Searches subject, sender, and body
    - Can filter by account/folder
    - Can specify a date range
    """

    offset = (page - 1) * limit

    # Build WHERE conditions
    where_conditions = [
        "m.is_deleted = FALSE",
        "a.user_uuid = %s",
        "a.status = 'active'"
    ]
    params = [user_uuid]
    
    # Search-term condition (subject, sender name, sender email, body)
    search_condition = """
        (m.subject LIKE %s 
         OR m.from_name LIKE %s 
         OR m.from_email LIKE %s)
    """
    search_pattern = f"%{query}%"
    where_conditions.append(search_condition)
    params.extend([search_pattern] * 3)
    
    # Account filter
    if account_uuid:
        where_conditions.append("m.account_uuid = %s")
        params.append(account_uuid)

    # Folder filter
    if folder_uuid:
        where_conditions.append("m.folder_uuid = %s")
        params.append(folder_uuid)

    # Date-range filter
    if date_from:
        where_conditions.append("m.sent_date >= %s")
        params.append(date_from)
    
    if date_to:
        where_conditions.append("m.sent_date <= %s")
        params.append(date_to)
    
    # Attachment filter
    if has_attachments is not None:
        where_conditions.append("m.has_attachments = %s")
        params.append(has_attachments)

    # Read/starred filter
    if unread_only:
        where_conditions.append("m.is_read = FALSE")
    
    if starred_only:
        where_conditions.append("m.is_starred = TRUE")
    
    where_clause = " AND ".join(where_conditions)
    
    # Search query
    search_query = f"""
        SELECT 
            m.message_uuid,
            m.account_uuid,
            m.folder_uuid,
            m.from_email,
            m.from_name,
            m.subject,
            m.preview,
            m.sent_date,
            m.is_read,
            m.is_starred,
            m.has_attachments,
            a.account_name,
            a.email as account_email,
            a.display_color,
            f.folder_name
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        LEFT JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
        WHERE {where_clause}
        ORDER BY m.sent_date DESC
        LIMIT %s OFFSET %s
    """

    logger.debug("search_query", search_query)
    logger.debug("where_clause", where_clause)
        
    params.extend([limit, offset])
    messages = db_instance.fetch_all(search_query, tuple(params))
    
    # Get total count
    count_query = f"""
        SELECT COUNT(*) as total
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        LEFT JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
        WHERE {where_clause}
    """

    # Use params excluding limit, offset
    count_params = params[:-2]
    total_result = db_instance.fetch_one(count_query, tuple(count_params))
    total = total_result['total'] if total_result else 0
    
    logger.info(f"[Search] 검색어: '{query}' - {len(messages)}개 메일 발견 (총 {total}개)")
    
    return {
        "success": True,
        "query": query,
        "messages": messages,
        "pagination": {
            "page": page,
            "limit": limit,
            "total": total,
            "total_pages": (total + limit - 1) // limit
        }
    }


# ========================================
# Statistics API
# ========================================
@router.get("/stats", dependencies=[Depends(verify_token)])
async def get_mail_stats(user_uuid: str):
    """
    Get mail statistics

    - Total mail count
    - Unread mail count
    - Starred mail count
    - Per-folder statistics
    - Per-account statistics
    """

    # Overall statistics
    total_query = """
        SELECT 
            COUNT(*) as total_mails,
            SUM(CASE WHEN is_read = FALSE THEN 1 ELSE 0 END) as unread_count,
            SUM(CASE WHEN is_starred = TRUE THEN 1 ELSE 0 END) as starred_count,
            SUM(CASE WHEN has_attachments = TRUE THEN 1 ELSE 0 END) as attachments_count
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND m.is_deleted = FALSE
    """
    
    total_stats = db_instance.fetch_one(total_query, (user_uuid,))
    
    # Per-folder statistics
    folder_query = """
        SELECT 
            f.folder_type,
            COUNT(m.message_uuid) as total_count,
            SUM(CASE WHEN m.is_read = FALSE THEN 1 ELSE 0 END) as unread_count
        FROM mail_folders f
        JOIN mail_accounts a ON f.account_uuid = a.account_uuid
        LEFT JOIN mail_messages m ON f.folder_uuid = m.folder_uuid AND m.is_deleted = FALSE
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND f.folder_type IN ('inbox', 'sent', 'drafts', 'trash', 'spam')
        GROUP BY f.folder_type
    """
    
    folder_stats_raw = db_instance.fetch_all(folder_query, (user_uuid,))
    
    # Starred-mailbox statistics (handled separately)
    starred_query = """
        SELECT 
            COUNT(*) as total_count,
            SUM(CASE WHEN is_read = FALSE THEN 1 ELSE 0 END) as unread_count
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND m.is_deleted = FALSE
          AND m.is_starred = TRUE
    """
    
    starred_stats = db_instance.fetch_one(starred_query, (user_uuid,))
    
    # Convert into dictionary form
    folder_stats = {}
    for row in folder_stats_raw:
        folder_stats[row['folder_type']] = {
            'total_count': row['total_count'] or 0,
            'unread_count': row['unread_count'] or 0
        }
    
    # Add starred mailbox
    folder_stats['starred'] = {
        'total_count': starred_stats['total_count'] or 0,
        'unread_count': starred_stats['unread_count'] or 0
    }
    
    # Trash statistics (is_deleted = TRUE)
    trash_query = """
        SELECT 
            COUNT(*) as total_count
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND m.is_deleted = TRUE
    """
    
    trash_stats = db_instance.fetch_one(trash_query, (user_uuid,))
    folder_stats['trash'] = {
        'total_count': trash_stats['total_count'] or 0,
        'unread_count': 0  # Trash does not show an unread count
    }
    
    # Per-account statistics
    account_query = """
        SELECT 
            a.account_uuid,
            a.account_name,
            a.email,
            a.display_color,
            COUNT(m.message_uuid) as total_mails,
            SUM(CASE WHEN m.is_read = FALSE THEN 1 ELSE 0 END) as unread_count
        FROM mail_accounts a
        LEFT JOIN mail_messages m ON a.account_uuid = m.account_uuid AND m.is_deleted = FALSE
        WHERE a.user_uuid = %s AND a.status = 'active'
        GROUP BY a.account_uuid, a.account_name, a.email, a.display_color
        ORDER BY a.display_order, a.created_at
    """
    
    account_stats = db_instance.fetch_all(account_query, (user_uuid,))
    
    return {
        "success": True,
        "total_stats": total_stats,
        "folder_stats": folder_stats,  # added
        "account_stats": account_stats
    }

# ========================================
# Recent mail API
# ========================================

@router.get("/recent", dependencies=[Depends(verify_token)])
async def get_recent_mails(
    user_uuid: str,
    hours: int = 24,
    limit: int = 20
):
    """
    Get mail that arrived within the last N hours

    - Default: last 24 hours
    - Unified inbox + time filter
    """
    
    since = datetime.now() - timedelta(hours=hours)
    
    query = """
        SELECT 
            m.message_uuid,
            m.account_uuid,
            m.from_email,
            m.from_name,
            m.subject,
            m.preview,
            m.sent_date,
            m.is_read,
            m.has_attachments,
            a.account_name,
            a.display_color
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND m.is_deleted = FALSE
          AND m.sent_date >= %s
        ORDER BY m.sent_date DESC
        LIMIT %s
    """
    
    messages = db_instance.fetch_all(query, (user_uuid, since, limit))
    
    return {
        "success": True,
        "hours": hours,
        "count": len(messages),
        "messages": messages
    }

# ========================================
# Mail detail API (DB-based)
# ========================================

@router.get("/messages/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_message_detail(message_uuid: str, user_uuid: str):
    """
    Get mail detail

    - Look up mail info from the DB
    - Read the .eml file at body_file_path
    - Parse the body HTML/text
    - Include the attachment list
    """

    # Look up mail info from the DB
    query = sqloader.load_sql("mail_anchor.json", "inbox.get_mail")
    message = db_instance.fetch_one(query, (message_uuid, user_uuid))
    
    if not message:
        raise HTTPException(status_code=404, detail="메일을 찾을 수 없습니다")
    
    # Read the .eml file
    body_html = None
    body_text = None
    attachments = []

    if message['body_file_path'] and os.path.exists(message['body_file_path']):
        try:
            with open(message['body_file_path'], 'rb') as f:
                msg = BytesParser(policy=policy.default).parse(f)

                # Extract body
                if msg.is_multipart():
                    for part in msg.walk():
                        content_type = part.get_content_type()
                        content_disposition = str(part.get("Content-Disposition", ""))

                        # When it is not an attachment
                        if "attachment" not in content_disposition:
                            if content_type == "text/html":
                                body_html = part.get_content()
                            elif content_type == "text/plain":
                                body_text = part.get_content()
                else:
                    # Single part
                    content_type = msg.get_content_type()
                    if content_type == "text/html":
                        body_html = msg.get_content()
                    elif content_type == "text/plain":
                        body_text = msg.get_content()
                        
        except Exception as e:
            logger.error(f"[Message Detail] .eml 파일 읽기 실패: {str(e)}")
            body_text = "메일 본문을 불러올 수 없습니다."
    
    # Look up attachment info
    attachment_query = sqloader.load_sql("mail_anchor.json", "inbox.get_attachment")
    attachments = db_instance.fetch_all(attachment_query, (message_uuid,))
    
    logger.info(f"[Message Detail] 메일 상세 조회: {message_uuid}")
    
    return {
        "success": True,
        "message": message,
        "body_html": body_html,
        "body_text": body_text,
        "attachments": attachments
    }

# ========================================
# Pinned mail API
# ========================================

@router.get("/pinned", dependencies=[Depends(verify_token)])
async def get_pinned_mails(user_uuid: str):
    """
    Get all pinned mail

    - Only mail with is_pinned = TRUE across all folders
    - Sorted newest-first
    """
    
    query = """
        SELECT 
            m.message_uuid,
            m.subject,
            m.from_email,
            m.from_name,
            m.sent_date,
            m.is_read,
            m.has_attachments
        FROM mail_messages m
        JOIN mail_accounts a ON m.account_uuid = a.account_uuid
        WHERE a.user_uuid = %s 
          AND a.status = 'active'
          AND m.is_deleted = FALSE
          AND m.is_pinned = TRUE
        ORDER BY m.sent_date DESC
        LIMIT 50
    """
    
    messages = db_instance.fetch_all(query, (user_uuid,))
    
    logger.info(f"[Pinned] 사용자 {user_uuid} - {len(messages)}개 핀 고정 메일 조회")
    
    return {
        "success": True,
        "messages": messages
    }
