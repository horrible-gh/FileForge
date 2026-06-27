"""
Gmail 토큰 갱신 헬퍼
기존 IMAP/SMTP 서비스에서 Gmail OAuth 계정 사용 시 토큰 자동 갱신
"""
from datetime import datetime, timedelta
from typing import Optional, Tuple
from config import settings, db
from util.crypto import encrypt_password, decrypt_password
from services.gmail_service import GmailOAuthService

SECRET_KEY = settings.SECRET_KEY
db_instance = db.db_instance
sqloader = db.sqloader

gmail_oauth = GmailOAuthService()


async def get_valid_gmail_credentials(
    account_uuid: str, 
    user_uuid: str
) -> Tuple[Optional[str], Optional[str]]:
    """
    유효한 Gmail 자격 증명 반환 (필요시 토큰 갱신)
    
    Returns:
        (email, access_token) 또는 실패 시 (None, None)
    
    Usage:
        email, access_token = await get_valid_gmail_credentials(account_uuid, user_uuid)
        if access_token:
            with GmailIMAPService(email, access_token) as imap:
                # 메일 조회...
    """
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.check_token_expiry"),
        {"account_uuid": account_uuid}
    )
    
    if not account:
        return None, None
    
    email = account["email"]
    
    # 토큰이 5분 이내 만료되거나 이미 만료된 경우 갱신
    if account.get("needs_refresh") or account.get("is_expired"):
        if not account.get("refresh_token_encrypted"):
            return None, None  # 재인증 필요
        
        try:
            # refresh_token 복호화
            refresh_token = decrypt_password(
                SECRET_KEY, user_uuid, account["refresh_token_encrypted"]
            )
            
            # 토큰 갱신
            token_data = await gmail_oauth.refresh_access_token(refresh_token)
            
            # 새 토큰 암호화 및 저장
            encrypted_access = encrypt_password(
                SECRET_KEY, user_uuid, token_data["access_token"]
            )
            
            db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.update_access_token"),
                {
                    "account_uuid": account_uuid,
                    "access_token_encrypted": encrypted_access,
                    "token_expires_in": token_data.get("expires_in", 3600),
                }
            )
            
            return email, token_data["access_token"]
            
        except Exception as e:
            print(f"Gmail 토큰 갱신 실패: {e}")
            return None, None
    
    # 토큰이 아직 유효한 경우
    try:
        access_token = decrypt_password(
            SECRET_KEY, user_uuid, account["access_token_encrypted"]
        )
        return email, access_token
    except:
        return None, None


def is_gmail_account(account: dict) -> bool:
    """계정이 Gmail OAuth 계정인지 확인"""
    return account.get("account_type") == "gmail"
