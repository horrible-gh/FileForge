"""
Gmail token refresh helper
Auto-refresh tokens when a Gmail OAuth account is used in the existing IMAP/SMTP services
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
    Return valid Gmail credentials (refreshing the token if needed).

    Returns:
        (email, access_token), or (None, None) on failure

    Usage:
        email, access_token = await get_valid_gmail_credentials(account_uuid, user_uuid)
        if access_token:
            with GmailIMAPService(email, access_token) as imap:
                # fetch mail...
    """
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.check_token_expiry"),
        {"account_uuid": account_uuid}
    )
    
    if not account:
        return None, None
    
    email = account["email"]
    
    # Refresh if the token expires within 5 minutes or is already expired
    if account.get("needs_refresh") or account.get("is_expired"):
        if not account.get("refresh_token_encrypted"):
            return None, None  # re-authentication required

        try:
            # Decrypt the refresh_token
            refresh_token = decrypt_password(
                SECRET_KEY, user_uuid, account["refresh_token_encrypted"]
            )

            # Refresh the token
            token_data = await gmail_oauth.refresh_access_token(refresh_token)

            # Encrypt and store the new token
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
    
    # Token is still valid
    try:
        access_token = decrypt_password(
            SECRET_KEY, user_uuid, account["access_token_encrypted"]
        )
        return email, access_token
    except:
        return None, None


def is_gmail_account(account: dict) -> bool:
    """Check whether the account is a Gmail OAuth account."""
    return account.get("account_type") == "gmail"
