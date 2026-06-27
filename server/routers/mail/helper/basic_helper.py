import imaplib
import smtplib
import ssl

def test_imap_connection(host, port, username, password, use_ssl=True):
    try:
        if use_ssl:
            mail = imaplib.IMAP4_SSL(host, port)
        else:
            mail = imaplib.IMAP4(host, port)
        
        mail.login(username, password)
        mail.select('INBOX')  # INBOX 접근 테스트
        mail.logout()
        
        return {"success": True, "message": "IMAP connection successful"}
    except Exception as e:
        return {"success": False, "message": str(e)}

def test_smtp_connection(host, port, username, password):
    """Gmail SMTP 연결 테스트"""
    try:
        context = ssl.create_default_context()
        
        if port == 465:
            with smtplib.SMTP_SSL(host, port, context=context, timeout=30) as server:
                server.set_debuglevel(2)  # 상세 로그
                server.ehlo('localhost')  # ← 이거 추가
                server.login(username, password)
            return {"success": True, "message": "SMTP SSL connection successful"}
        
        elif port == 587:
            with smtplib.SMTP(host, port, timeout=30) as server:
                server.set_debuglevel(2)  # 상세 로그
                server.ehlo('localhost')  # ← 이거 추가
                server.starttls(context=context)
                server.ehlo('localhost')  # ← starttls 후에도 다시
                server.login(username, password)
            return {"success": True, "message": "SMTP TLS connection successful"}
        
        else:
            return {"success": False, "message": f"Unsupported port: {port}"}
            
    except smtplib.SMTPAuthenticationError as e:
        return {"success": False, "message": f"인증 실패 - 앱 비밀번호 확인 필요: {e}"}
    except smtplib.SMTPException as e:
        return {"success": False, "message": f"SMTP 에러: {e}"}
    except Exception as e:
        return {"success": False, "message": f"연결 실패: {e}"}

