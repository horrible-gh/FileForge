"""
Gmail OAuth2 Service
- OAuth2 token management
- Gmail API calls (for IMAP OAuth2 authentication)
"""
import httpx
from urllib.parse import urlencode
from typing import Optional, Dict, Any
from config import settings
import LogAssist.log as logger


class GmailOAuthService:
    """Gmail OAuth2 service"""

    # Google OAuth2 endpoints
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"
    REVOKE_URL = "https://oauth2.googleapis.com/revoke"
    
    # Scopes for Gmail IMAP/SMTP OAuth2
    SCOPES = [
        "https://mail.google.com/",  # full IMAP/SMTP permission
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]
    
    def __init__(self):
        self.client_id = settings.GOOGLE_CLIENT_ID
        self.client_secret = settings.GOOGLE_CLIENT_SECRET
        self.redirect_uri = f"{settings.GOOGLE_REDIRECT_URI}"
    
    def generate_auth_url(self, state: str) -> str:
        """Generate the OAuth2 authentication URL."""
        params = {
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "response_type": "code",
            "scope": " ".join(self.SCOPES),
            "access_type": "offline",      # required to receive a refresh_token
            "prompt": "consent",           # consent screen every time (guarantees refresh_token)
            "state": state,
        }
        logger.debug("OAuth Gmail params", params)
        return f"{self.AUTH_URL}?{urlencode(params)}"
    
    async def exchange_code_for_tokens(self, code: str) -> Dict[str, Any]:
        """Authorization code → token exchange"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.TOKEN_URL,
                data={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "code": code,
                    "grant_type": "authorization_code",
                    "redirect_uri": self.redirect_uri,
                },
            )
            
            if response.status_code != 200:
                error = response.json() if response.text else {}
                raise Exception(f"토큰 교환 실패: {error}")
            
            return response.json()
    
    async def refresh_access_token(self, refresh_token: str) -> Dict[str, Any]:
        """Refresh token → new access token"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.TOKEN_URL,
                data={
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                    "refresh_token": refresh_token,
                    "grant_type": "refresh_token",
                },
            )
            
            if response.status_code != 200:
                error = response.json() if response.text else {}
                raise Exception(f"토큰 갱신 실패: {error}")
            
            return response.json()
    
    async def get_user_info(self, access_token: str) -> Dict[str, Any]:
        """Fetch user info."""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                self.USERINFO_URL,
                headers={"Authorization": f"Bearer {access_token}"},
            )
            
            if response.status_code != 200:
                raise Exception(f"사용자 정보 조회 실패: {response.status_code}")
            
            return response.json()
    
    async def revoke_token(self, token: str) -> bool:
        """Revoke the token."""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.REVOKE_URL,
                data={"token": token},
            )
            return response.status_code in (200, 400)
    
    def generate_oauth2_string(self, email: str, access_token: str) -> str:
        """
        Generate the IMAP/SMTP XOAUTH2 authentication string.

        Usage:
            auth_string = gmail_oauth.generate_oauth2_string(email, access_token)
            imap_conn.authenticate('XOAUTH2', lambda x: auth_string)
        """
        import base64
        auth_string = f"user={email}\x01auth=Bearer {access_token}\x01\x01"
        return base64.b64encode(auth_string.encode()).decode()


class GmailIMAPService:
    """
    Gmail IMAP with OAuth2
    Extends the existing IMAPService - adds OAuth2 authentication support
    """
    
    IMAP_HOST = "imap.gmail.com"
    IMAP_PORT = 993
    SMTP_HOST = "smtp.gmail.com"
    SMTP_PORT = 587
    
    def __init__(self, email: str, access_token: str):
        self.email = email
        self.access_token = access_token
        self.connection = None
    
    def connect(self) -> Dict[str, Any]:
        """Gmail IMAP OAuth2 connection."""
        import imaplib
        
        try:
            self.connection = imaplib.IMAP4_SSL(self.IMAP_HOST, self.IMAP_PORT)
            
            # XOAUTH2 authentication
            auth_string = self._generate_auth_string()
            self.connection.authenticate('XOAUTH2', lambda x: auth_string)
            
            return {"success": True, "message": "Gmail IMAP 연결 성공"}
        except imaplib.IMAP4.error as e:
            error_msg = str(e)
            if "AUTHENTICATIONFAILED" in error_msg:
                return {"success": False, "message": "인증 실패 - 토큰 갱신 필요", "need_refresh": True}
            return {"success": False, "message": f"IMAP 연결 실패: {error_msg}"}
        except Exception as e:
            return {"success": False, "message": f"연결 실패: {str(e)}"}
    
    def _generate_auth_string(self) -> bytes:
        """XOAUTH2 authentication string."""
        auth_string = f"user={self.email}\x01auth=Bearer {self.access_token}\x01\x01"
        return auth_string.encode()
    
    def disconnect(self):
        """Close the connection."""
        if self.connection:
            try:
                self.connection.logout()
            except:
                pass
            self.connection = None
    
    def __enter__(self):
        result = self.connect()
        if not result["success"]:
            raise Exception(result["message"])
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()


class GmailSMTPService:
    """Gmail SMTP with OAuth2"""
    
    SMTP_HOST = "smtp.gmail.com"
    SMTP_PORT = 587
    
    def __init__(self, email: str, access_token: str):
        self.email = email
        self.access_token = access_token
        self.connection = None
    
    def connect(self) -> Dict[str, Any]:
        """Gmail SMTP OAuth2 connection."""
        import smtplib
        import base64
        
        try:
            # local_hostname is forced to 'localhost': some environments resolve a
            # malformed FQDN via socket.getfqdn() (e.g. an ISP reverse-DNS that
            # contains a space), which smtplib would send as the EHLO argument and
            # Gmail rejects with 501 syntax error → STARTTLS appears "unsupported"
            # → connect fails → caller returns 502. Mirrors smtp_service.py's
            # `ehlo('localhost')  # hostname issue fix`.
            self.connection = smtplib.SMTP(
                self.SMTP_HOST, self.SMTP_PORT, local_hostname="localhost")
            self.connection.ehlo("localhost")
            self.connection.starttls()
            self.connection.ehlo("localhost")
            
            # XOAUTH2 authentication
            auth_string = f"user={self.email}\x01auth=Bearer {self.access_token}\x01\x01"
            auth_b64 = base64.b64encode(auth_string.encode()).decode()
            
            code, response = self.connection.docmd("AUTH", f"XOAUTH2 {auth_b64}")
            
            if code != 235:
                return {"success": False, "message": f"SMTP 인증 실패: {response}", "need_refresh": True}
            
            return {"success": True, "message": "Gmail SMTP 연결 성공"}
        except Exception as e:
            return {"success": False, "message": f"SMTP 연결 실패: {str(e)}"}
    
    def disconnect(self):
        """Close the connection."""
        if self.connection:
            try:
                self.connection.quit()
            except:
                pass
            self.connection = None
    
    def send_mail(self, to: str, subject: str, body: str, html: bool = False) -> Dict[str, Any]:
        """Send mail."""
        from email.mime.text import MIMEText
        from email.mime.multipart import MIMEMultipart
        
        try:
            if not self.connection:
                result = self.connect()
                if not result["success"]:
                    return result
            
            msg = MIMEMultipart("alternative")
            msg["From"] = self.email
            msg["To"] = to
            msg["Subject"] = subject
            
            content_type = "html" if html else "plain"
            msg.attach(MIMEText(body, content_type, "utf-8"))
            
            self.connection.sendmail(self.email, [to], msg.as_string())
            
            return {"success": True, "message": "메일 발송 완료"}
        except Exception as e:
            return {"success": False, "message": f"메일 발송 실패: {str(e)}"}
    
    def __enter__(self):
        result = self.connect()
        if not result["success"]:
            raise Exception(result["message"])
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()
