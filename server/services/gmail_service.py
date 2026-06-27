"""
Gmail OAuth2 Service
- OAuth2 토큰 관리
- Gmail API 호출 (IMAP OAuth2 인증용)
"""
import httpx
from urllib.parse import urlencode
from typing import Optional, Dict, Any
from config import settings
import LogAssist.log as logger


class GmailOAuthService:
    """Gmail OAuth2 서비스"""
    
    # Google OAuth2 엔드포인트
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"
    REVOKE_URL = "https://oauth2.googleapis.com/revoke"
    
    # Gmail IMAP/SMTP OAuth2용 스코프
    SCOPES = [
        "https://mail.google.com/",  # IMAP/SMTP 전체 권한
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
    ]
    
    def __init__(self):
        self.client_id = settings.GOOGLE_CLIENT_ID
        self.client_secret = settings.GOOGLE_CLIENT_SECRET
        self.redirect_uri = f"{settings.GOOGLE_REDIRECT_URI}"
    
    def generate_auth_url(self, state: str) -> str:
        """OAuth2 인증 URL 생성"""
        params = {
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "response_type": "code",
            "scope": " ".join(self.SCOPES),
            "access_type": "offline",      # refresh_token 받기 위해 필수
            "prompt": "consent",           # 매번 동의 화면 (refresh_token 보장)
            "state": state,
        }
        logger.debug("OAuth Gmail params", params)
        return f"{self.AUTH_URL}?{urlencode(params)}"
    
    async def exchange_code_for_tokens(self, code: str) -> Dict[str, Any]:
        """Authorization code → 토큰 교환"""
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
        """Refresh token → 새 access token"""
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
        """사용자 정보 조회"""
        async with httpx.AsyncClient() as client:
            response = await client.get(
                self.USERINFO_URL,
                headers={"Authorization": f"Bearer {access_token}"},
            )
            
            if response.status_code != 200:
                raise Exception(f"사용자 정보 조회 실패: {response.status_code}")
            
            return response.json()
    
    async def revoke_token(self, token: str) -> bool:
        """토큰 폐기"""
        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.REVOKE_URL,
                data={"token": token},
            )
            return response.status_code in (200, 400)
    
    def generate_oauth2_string(self, email: str, access_token: str) -> str:
        """
        IMAP/SMTP XOAUTH2 인증 문자열 생성
        
        사용법:
            auth_string = gmail_oauth.generate_oauth2_string(email, access_token)
            imap_conn.authenticate('XOAUTH2', lambda x: auth_string)
        """
        import base64
        auth_string = f"user={email}\x01auth=Bearer {access_token}\x01\x01"
        return base64.b64encode(auth_string.encode()).decode()


class GmailIMAPService:
    """
    Gmail IMAP with OAuth2
    기존 IMAPService 확장 - OAuth2 인증 지원
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
        """Gmail IMAP OAuth2 연결"""
        import imaplib
        
        try:
            self.connection = imaplib.IMAP4_SSL(self.IMAP_HOST, self.IMAP_PORT)
            
            # XOAUTH2 인증
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
        """XOAUTH2 인증 문자열"""
        auth_string = f"user={self.email}\x01auth=Bearer {self.access_token}\x01\x01"
        return auth_string.encode()
    
    def disconnect(self):
        """연결 종료"""
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
        """Gmail SMTP OAuth2 연결"""
        import smtplib
        import base64
        
        try:
            self.connection = smtplib.SMTP(self.SMTP_HOST, self.SMTP_PORT)
            self.connection.ehlo()
            self.connection.starttls()
            self.connection.ehlo()
            
            # XOAUTH2 인증
            auth_string = f"user={self.email}\x01auth=Bearer {self.access_token}\x01\x01"
            auth_b64 = base64.b64encode(auth_string.encode()).decode()
            
            code, response = self.connection.docmd("AUTH", f"XOAUTH2 {auth_b64}")
            
            if code != 235:
                return {"success": False, "message": f"SMTP 인증 실패: {response}", "need_refresh": True}
            
            return {"success": True, "message": "Gmail SMTP 연결 성공"}
        except Exception as e:
            return {"success": False, "message": f"SMTP 연결 실패: {str(e)}"}
    
    def disconnect(self):
        """연결 종료"""
        if self.connection:
            try:
                self.connection.quit()
            except:
                pass
            self.connection = None
    
    def send_mail(self, to: str, subject: str, body: str, html: bool = False) -> Dict[str, Any]:
        """메일 발송"""
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
