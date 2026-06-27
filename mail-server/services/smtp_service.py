"""
MailAnchor - SMTP Service
메일 발송, 임시저장
"""

import smtplib
import ssl
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.image import MIMEImage
from email import encoders
from email.utils import formataddr, formatdate
from typing import Optional, List, Dict, Any, Union
import mimetypes
import os


class SMTPService:
    def __init__(self, host: str, port: int, username: str, password: str):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.connection: Optional[smtplib.SMTP] = None
    
    def connect(self) -> Dict[str, Any]:
        """SMTP 서버 연결"""
        try:
            context = ssl.create_default_context()
            
            if self.port == 465:
                # SSL 직접 연결
                self.connection = smtplib.SMTP_SSL(
                    self.host, 
                    self.port, 
                    context=context, 
                    timeout=30
                )
                self.connection.ehlo('localhost')  # 호스트네임 문제 해결
            elif self.port == 587:
                # STARTTLS
                self.connection = smtplib.SMTP(self.host, self.port, timeout=30)
                self.connection.ehlo('localhost')
                self.connection.starttls(context=context)
                self.connection.ehlo('localhost')
            else:
                return {"success": False, "message": f"지원하지 않는 포트: {self.port}"}
            
            self.connection.login(self.username, self.password)
            return {"success": True, "message": "SMTP 연결 성공"}
        
        except smtplib.SMTPAuthenticationError as e:
            return {"success": False, "message": f"인증 실패: {e}"}
        except smtplib.SMTPException as e:
            return {"success": False, "message": f"SMTP 에러: {e}"}
        except Exception as e:
            return {"success": False, "message": f"연결 실패: {e}"}
    
    def disconnect(self):
        """연결 종료"""
        if self.connection:
            try:
                self.connection.quit()
            except:
                pass
            self.connection = None
    
    def __enter__(self):
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()
    
    # ========================================
    # 메일 발송
    # ========================================
    
    def send_mail(
        self,
        from_name: str,
        from_email: str,
        to_addresses: List[str],
        subject: str,
        body_text: str = "",
        body_html: str = "",
        cc_addresses: Optional[List[str]] = None,
        bcc_addresses: Optional[List[str]] = None,
        attachments: Optional[List[Dict[str, Any]]] = None,
        reply_to: Optional[str] = None
    ) -> Dict[str, Any]:
        """메일 발송"""
        try:
            if not self.connection:
                # 연결 안 되어 있으면 연결 시도
                result = self.connect()
                if not result["success"]:
                    return result
            
            # 메일 메시지 생성
            msg = self._create_message(
                from_name=from_name,
                from_email=from_email,
                to_addresses=to_addresses,
                subject=subject,
                body_text=body_text,
                body_html=body_html,
                cc_addresses=cc_addresses,
                reply_to=reply_to,
                attachments=attachments
            )
            
            # 수신자 목록 합치기
            all_recipients = list(to_addresses)
            if cc_addresses:
                all_recipients.extend(cc_addresses)
            if bcc_addresses:
                all_recipients.extend(bcc_addresses)
            
            # 발송
            self.connection.send_message(msg, from_email, all_recipients)
            
            return {"success": True, "message": "메일 발송 완료"}
        
        except smtplib.SMTPRecipientsRefused as e:
            return {"success": False, "message": f"수신자 거부: {e}"}
        except smtplib.SMTPException as e:
            return {"success": False, "message": f"발송 실패: {e}"}
        except Exception as e:
            return {"success": False, "message": f"발송 실패: {e}"}
    
    def _create_message(
        self,
        from_name: str,
        from_email: str,
        to_addresses: List[str],
        subject: str,
        body_text: str = "",
        body_html: str = "",
        cc_addresses: Optional[List[str]] = None,
        reply_to: Optional[str] = None,
        attachments: Optional[List[Dict[str, Any]]] = None
    ) -> MIMEMultipart:
        """MIME 메시지 생성"""
        
        # 첨부파일 있으면 mixed, 없으면 alternative
        if attachments:
            msg = MIMEMultipart('mixed')
            body_part = MIMEMultipart('alternative')
        else:
            msg = MIMEMultipart('alternative')
            body_part = msg
        
        # 헤더 설정
        msg['From'] = formataddr((from_name, from_email))
        msg['To'] = ', '.join(to_addresses)
        msg['Subject'] = subject
        msg['Date'] = formatdate(localtime=True)
        
        if cc_addresses:
            msg['Cc'] = ', '.join(cc_addresses)
        
        if reply_to:
            msg['Reply-To'] = reply_to
        
        # 본문 추가 (text/plain -> text/html 순서)
        if body_text:
            body_part.attach(MIMEText(body_text, 'plain', 'utf-8'))
        
        if body_html:
            body_part.attach(MIMEText(body_html, 'html', 'utf-8'))
        elif body_text:
            # HTML 없으면 텍스트를 HTML로 변환
            html_body = f"<html><body><pre>{body_text}</pre></body></html>"
            body_part.attach(MIMEText(html_body, 'html', 'utf-8'))
        
        # 첨부파일이 있으면 본문 파트를 메인 메시지에 추가
        if attachments:
            msg.attach(body_part)
            
            # 첨부파일 추가
            for attachment in attachments:
                self._attach_file(msg, attachment)
        
        return msg
    
    def _attach_file(self, msg: MIMEMultipart, attachment: Dict[str, Any]):
        """첨부파일 추가"""
        filename = attachment.get('filename', 'attachment')
        content = attachment.get('content')  # bytes
        content_type = attachment.get('content_type', 'application/octet-stream')
        
        if not content:
            # 파일 경로가 주어진 경우
            filepath = attachment.get('filepath')
            if filepath and os.path.exists(filepath):
                with open(filepath, 'rb') as f:
                    content = f.read()
                if not filename or filename == 'attachment':
                    filename = os.path.basename(filepath)
                if content_type == 'application/octet-stream':
                    content_type = mimetypes.guess_type(filepath)[0] or content_type
        
        if not content:
            return
        
        # MIME 타입에 따라 처리
        maintype, subtype = content_type.split('/', 1) if '/' in content_type else ('application', 'octet-stream')
        
        if maintype == 'image':
            part = MIMEImage(content, _subtype=subtype)
        else:
            part = MIMEBase(maintype, subtype)
            part.set_payload(content)
            encoders.encode_base64(part)
        
        # 파일명 설정 (한글 파일명 처리)
        part.add_header(
            'Content-Disposition',
            'attachment',
            filename=('utf-8', '', filename)
        )
        
        msg.attach(part)
    
    # ========================================
    # 빠른 답장
    # ========================================
    
    def reply(
        self,
        from_name: str,
        from_email: str,
        to_email: str,
        original_subject: str,
        original_body: str,
        reply_body: str,
        reply_html: Optional[str] = None
    ) -> Dict[str, Any]:
        """답장 보내기"""
        # Re: 접두사 추가 (이미 있으면 추가 안 함)
        if not original_subject.lower().startswith('re:'):
            subject = f"Re: {original_subject}"
        else:
            subject = original_subject
        
        # 인용문 추가
        quoted_body = self._quote_original(original_body)
        full_body_text = f"{reply_body}\n\n{quoted_body}"
        
        if reply_html:
            quoted_html = f"<blockquote style='border-left: 2px solid #ccc; padding-left: 10px; margin-left: 10px; color: #666;'>{original_body}</blockquote>"
            full_body_html = f"{reply_html}<br><br>{quoted_html}"
        else:
            full_body_html = None
        
        return self.send_mail(
            from_name=from_name,
            from_email=from_email,
            to_addresses=[to_email],
            subject=subject,
            body_text=full_body_text,
            body_html=full_body_html or ""
        )
    
    def _quote_original(self, original_body: str) -> str:
        """원본 메일 인용"""
        lines = original_body.split('\n')
        quoted_lines = ['> ' + line for line in lines]
        return '\n'.join(quoted_lines)
    
    # ========================================
    # 전달
    # ========================================
    
    def forward(
        self,
        from_name: str,
        from_email: str,
        to_addresses: List[str],
        original_subject: str,
        original_from: str,
        original_date: str,
        original_body: str,
        forward_message: str = "",
        attachments: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """메일 전달"""
        # Fwd: 접두사 추가
        if not original_subject.lower().startswith('fwd:'):
            subject = f"Fwd: {original_subject}"
        else:
            subject = original_subject
        
        # 전달 헤더 추가
        forward_header = f"""
---------- Forwarded message ---------
From: {original_from}
Date: {original_date}
Subject: {original_subject}

"""
        
        body_text = f"{forward_message}\n{forward_header}{original_body}"
        
        return self.send_mail(
            from_name=from_name,
            from_email=from_email,
            to_addresses=to_addresses,
            subject=subject,
            body_text=body_text,
            attachments=attachments
        )


# ========================================
# 편의 함수
# ========================================

def send_simple_mail(
    smtp_host: str,
    smtp_port: int,
    smtp_username: str,
    smtp_password: str,
    from_name: str,
    to_email: str,
    subject: str,
    body: str,
    is_html: bool = False
) -> Dict[str, Any]:
    """간단한 메일 발송 (연결 → 발송 → 종료)"""
    with SMTPService(smtp_host, smtp_port, smtp_username, smtp_password) as smtp:
        return smtp.send_mail(
            from_name=from_name,
            from_email=smtp_username,
            to_addresses=[to_email],
            subject=subject,
            body_text="" if is_html else body,
            body_html=body if is_html else ""
        )


def test_smtp_connection(host: str, port: int, username: str, password: str) -> Dict[str, Any]:
    """SMTP 연결 테스트"""
    try:
        context = ssl.create_default_context()
        
        if port == 465:
            with smtplib.SMTP_SSL(host, port, context=context, timeout=30) as server:
                server.ehlo('localhost')
                server.login(username, password)
            return {"success": True, "message": "SMTP SSL 연결 성공"}
        
        elif port == 587:
            with smtplib.SMTP(host, port, timeout=30) as server:
                server.ehlo('localhost')
                server.starttls(context=context)
                server.ehlo('localhost')
                server.login(username, password)
            return {"success": True, "message": "SMTP TLS 연결 성공"}
        
        else:
            return {"success": False, "message": f"지원하지 않는 포트: {port}"}
            
    except smtplib.SMTPAuthenticationError as e:
        return {"success": False, "message": f"인증 실패 - 앱 비밀번호 확인 필요: {e}"}
    except smtplib.SMTPException as e:
        return {"success": False, "message": f"SMTP 에러: {e}"}
    except Exception as e:
        return {"success": False, "message": f"연결 실패: {e}"}
