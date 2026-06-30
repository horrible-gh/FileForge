"""
MailAnchor - IMAP Service
Mail reading, folder management, mail status changes
"""

import imaplib
import email
from email.header import decode_header
from email.utils import parsedate_to_datetime
from typing import Optional, List, Dict, Any, Tuple
import re
from datetime import datetime


class IMAPService:
    def __init__(self, host: str, port: int, username: str, password: str, use_ssl: bool = True):
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.use_ssl = use_ssl
        self.connection: Optional[imaplib.IMAP4] = None
    
    def connect(self) -> Dict[str, Any]:
        """Connect to the IMAP server."""
        try:
            if self.use_ssl:
                self.connection = imaplib.IMAP4_SSL(self.host, self.port)
            else:
                self.connection = imaplib.IMAP4(self.host, self.port)
            
            self.connection.login(self.username, self.password)
            return {"success": True, "message": "IMAP 연결 성공"}
        except Exception as e:
            return {"success": False, "message": f"IMAP 연결 실패: {str(e)}"}
    
    def disconnect(self):
        """Close the connection."""
        if self.connection:
            try:
                self.connection.logout()
            except:
                pass
            self.connection = None
    
    def __enter__(self):
        self.connect()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()
    
    # ========================================
    # Folder management
    # ========================================

    def get_folders(self) -> Dict[str, Any]:
        """List folders."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            status, folder_list = self.connection.list()
            if status != 'OK':
                return {"success": False, "message": "폴더 목록 조회 실패"}
            
            folders = []
            for folder_data in folder_list:
                if folder_data:
                    # Parse folder info: b'(\\HasNoChildren) "/" "INBOX"'
                    decoded = folder_data.decode('utf-8')
                    match = re.search(r'\(([^)]*)\)\s+"([^"]+)"\s+"?([^"]+)"?', decoded)
                    if match:
                        flags, delimiter, name = match.groups()
                        
                        # Count unread mail per folder
                        unread_count = self._get_unread_count(name)
                        
                        folders.append({
                            "name": name,
                            "flags": flags,
                            "delimiter": delimiter,
                            "unread_count": unread_count,
                            "display_name": self._get_display_name(name)
                        })
            
            return {"success": True, "folders": folders}
        except Exception as e:
            return {"success": False, "message": f"폴더 조회 실패: {str(e)}"}
    
    def _get_display_name(self, folder_name: str) -> str:
        """Translate folder names to Korean display names."""
        mapping = {
            "INBOX": "받은편지함",
            "[Gmail]/Sent Mail": "보낸편지함",
            "[Gmail]/Drafts": "임시보관함",
            "[Gmail]/Trash": "휴지통",
            "[Gmail]/Spam": "스팸",
            "[Gmail]/Starred": "별표편지함",
            "[Gmail]/Important": "중요",
            "[Gmail]/All Mail": "전체보관함",
        }
        return mapping.get(folder_name, folder_name)
    
    def _get_unread_count(self, folder_name: str) -> int:
        """Count unread mail."""
        try:
            # If the folder name has spaces or special chars, wrap it in quotes
            if ' ' in folder_name or '/' in folder_name:
                folder_name = f'"{folder_name}"'
            
            status, data = self.connection.select(folder_name, readonly=True)
            if status != 'OK':
                return 0
            
            status, messages = self.connection.search(None, 'UNSEEN')
            if status != 'OK':
                return 0
            
            message_ids = messages[0].split()
            return len(message_ids)
        except:
            return 0
    
    def create_folder(self, folder_name: str) -> Dict[str, Any]:
        """Create a folder."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            status, _ = self.connection.create(folder_name)
            if status == 'OK':
                return {"success": True, "message": f"폴더 '{folder_name}' 생성 완료"}
            return {"success": False, "message": "폴더 생성 실패"}
        except Exception as e:
            return {"success": False, "message": f"폴더 생성 실패: {str(e)}"}
    
    def delete_folder(self, folder_name: str) -> Dict[str, Any]:
        """Delete a folder."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            status, _ = self.connection.delete(folder_name)
            if status == 'OK':
                return {"success": True, "message": f"폴더 '{folder_name}' 삭제 완료"}
            return {"success": False, "message": "폴더 삭제 실패"}
        except Exception as e:
            return {"success": False, "message": f"폴더 삭제 실패: {str(e)}"}
    
    # ========================================
    # Mail list retrieval
    # ========================================
    
    def get_mail_list(
        self, 
        folder: str = "INBOX", 
        page: int = 1, 
        limit: int = 20,
        search_query: Optional[str] = None
    ) -> Dict[str, Any]:
        """Retrieve the mail list."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}

            # Select the folder
            if ' ' in folder or '/' in folder:
                folder = f'"{folder}"'

            status, data = self.connection.select(folder, readonly=True)
            if status != 'OK':
                return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}

            total_messages = int(data[0])

            # Search criteria
            if search_query:
                # Search subject, sender, body
                search_criteria = f'(OR OR SUBJECT "{search_query}" FROM "{search_query}" BODY "{search_query}")'
                status, messages = self.connection.search(None, search_criteria)
            else:
                status, messages = self.connection.search(None, 'ALL')
            
            if status != 'OK':
                return {"success": False, "message": "메일 검색 실패"}
            
            message_ids = messages[0].split()
            message_ids.reverse()  # sort newest first

            # Paging
            total_count = len(message_ids)
            start_idx = (page - 1) * limit
            end_idx = start_idx + limit
            page_message_ids = message_ids[start_idx:end_idx]

            # Retrieve the mail list
            mails = []
            for msg_id in page_message_ids:
                mail_info = self._get_mail_summary(msg_id)
                if mail_info:
                    mails.append(mail_info)
            
            return {
                "success": True,
                "mails": mails,
                "total_count": total_count,
                "page": page,
                "limit": limit,
                "total_pages": (total_count + limit - 1) // limit
            }
        except Exception as e:
            return {"success": False, "message": f"메일 목록 조회 실패: {str(e)}"}
    
    def _get_mail_summary(self, msg_id: bytes) -> Optional[Dict[str, Any]]:
        """Retrieve mail summary info (for the list)."""
        try:
            # Fetch only ENVELOPE and FLAGS for a fast lookup
            status, data = self.connection.fetch(msg_id, '(FLAGS ENVELOPE BODYSTRUCTURE RFC822.SIZE)')
            if status != 'OK':
                return None
            
            # Parse FLAGS
            flags_match = re.search(rb'FLAGS \(([^)]*)\)', data[0][0])
            flags = flags_match.group(1).decode() if flags_match else ""
            is_read = '\\Seen' in flags
            is_starred = '\\Flagged' in flags

            # Fetch only the header to parse the ENVELOPE
            status, header_data = self.connection.fetch(msg_id, '(BODY.PEEK[HEADER])')
            if status != 'OK':
                return None
            
            raw_header = header_data[0][1]
            msg = email.message_from_bytes(raw_header)
            
            # Decode the header
            subject = self._decode_header(msg.get('Subject', '(제목 없음)'))
            from_addr = self._decode_header(msg.get('From', ''))
            date_str = msg.get('Date', '')

            # Parse the date
            try:
                date = parsedate_to_datetime(date_str)
            except:
                date = datetime.now()

            # Parse the sender
            sender_name, sender_email = self._parse_address(from_addr)
            
            return {
                "uid": msg_id.decode(),
                "subject": subject,
                "sender_name": sender_name,
                "sender_email": sender_email,
                "date": date.isoformat(),
                "is_read": is_read,
                "is_starred": is_starred,
                "has_attachment": self._has_attachment(data[0][0]),
                "preview": ""  # preview comes from the detail lookup
            }
        except Exception as e:
            print(f"메일 요약 조회 실패: {e}")
            return None
    
    def _decode_header(self, header_value: str) -> str:
        """Decode a header value (handles MIME encoding)."""
        if not header_value:
            return ""
        
        try:
            decoded_parts = decode_header(header_value)
            result = []
            for part, charset in decoded_parts:
                if isinstance(part, bytes):
                    charset = charset or 'utf-8'
                    try:
                        result.append(part.decode(charset, errors='replace'))
                    except:
                        result.append(part.decode('utf-8', errors='replace'))
                else:
                    result.append(part)
            return ''.join(result)
        except:
            return str(header_value)
    
    def _parse_address(self, address: str) -> Tuple[str, str]:
        """Split the name and email from an address."""
        # Form like "Display Name <hong@example.com>"
        match = re.match(r'^"?([^"<]*)"?\s*<?([^>]*)>?$', address.strip())
        if match:
            name, email_addr = match.groups()
            name = name.strip().strip('"')
            email_addr = email_addr.strip()
            if not name:
                name = email_addr.split('@')[0] if email_addr else "알 수 없음"
            return name, email_addr
        return address, address
    
    def _has_attachment(self, fetch_response: bytes) -> bool:
        """Check whether an attachment exists."""
        # Check for attachment in BODYSTRUCTURE
        return b'attachment' in fetch_response.lower()
    
    # ========================================
    # Mail detail retrieval
    # ========================================

    def get_mail_detail(self, folder: str, mail_uid: str) -> Dict[str, Any]:
        """Retrieve mail detail."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            # Select the folder
            if ' ' in folder or '/' in folder:
                folder = f'"{folder}"'
            
            status, _ = self.connection.select(folder)
            if status != 'OK':
                return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}
            
            # Fetch the entire mail
            status, data = self.connection.fetch(mail_uid.encode(), '(RFC822 FLAGS)')
            if status != 'OK':
                return {"success": False, "message": "메일 조회 실패"}
            
            raw_email = data[0][1]
            msg = email.message_from_bytes(raw_email)
            
            # Parse flags
            flags_match = re.search(rb'FLAGS \(([^)]*)\)', data[0][0])
            flags = flags_match.group(1).decode() if flags_match else ""

            # Header info
            subject = self._decode_header(msg.get('Subject', '(제목 없음)'))
            from_addr = self._decode_header(msg.get('From', ''))
            to_addr = self._decode_header(msg.get('To', ''))
            cc_addr = self._decode_header(msg.get('Cc', ''))
            date_str = msg.get('Date', '')
            
            sender_name, sender_email = self._parse_address(from_addr)
            
            try:
                date = parsedate_to_datetime(date_str)
            except:
                date = datetime.now()
            
            # Extract the body
            body_html, body_text = self._extract_body(msg)

            # Attachment list
            attachments = self._extract_attachments(msg)
            
            return {
                "success": True,
                "mail": {
                    "uid": mail_uid,
                    "subject": subject,
                    "sender_name": sender_name,
                    "sender_email": sender_email,
                    "to": to_addr,
                    "cc": cc_addr,
                    "date": date.isoformat(),
                    "body_html": body_html,
                    "body_text": body_text,
                    "is_read": '\\Seen' in flags,
                    "is_starred": '\\Flagged' in flags,
                    "attachments": attachments
                }
            }
        except Exception as e:
            return {"success": False, "message": f"메일 상세 조회 실패: {str(e)}"}
    
    def _extract_body(self, msg: email.message.Message) -> Tuple[str, str]:
        """Extract the mail body (HTML, Text)."""
        body_html = ""
        body_text = ""
        
        if msg.is_multipart():
            for part in msg.walk():
                content_type = part.get_content_type()
                content_disposition = str(part.get("Content-Disposition", ""))
                
                # Exclude attachments
                if "attachment" in content_disposition:
                    continue
                
                try:
                    payload = part.get_payload(decode=True)
                    if payload:
                        charset = part.get_content_charset() or 'utf-8'
                        decoded = payload.decode(charset, errors='replace')
                        
                        if content_type == "text/html":
                            body_html = decoded
                        elif content_type == "text/plain":
                            body_text = decoded
                except:
                    pass
        else:
            # Single-part mail
            try:
                payload = msg.get_payload(decode=True)
                if payload:
                    charset = msg.get_content_charset() or 'utf-8'
                    decoded = payload.decode(charset, errors='replace')
                    
                    if msg.get_content_type() == "text/html":
                        body_html = decoded
                    else:
                        body_text = decoded
            except:
                pass
        
        return body_html, body_text
    
    def _extract_attachments(self, msg: email.message.Message) -> List[Dict[str, Any]]:
        """Extract the attachment list."""
        attachments = []
        
        if msg.is_multipart():
            for idx, part in enumerate(msg.walk()):
                content_disposition = str(part.get("Content-Disposition", ""))
                
                if "attachment" in content_disposition:
                    filename = part.get_filename()
                    if filename:
                        filename = self._decode_header(filename)
                    else:
                        filename = f"attachment_{idx}"
                    
                    content_type = part.get_content_type()
                    size = len(part.get_payload(decode=True) or b"")
                    
                    attachments.append({
                        "index": idx,
                        "filename": filename,
                        "content_type": content_type,
                        "size": size
                    })
        
        return attachments
    
    def get_attachment(self, folder: str, mail_uid: str, attachment_index: int) -> Dict[str, Any]:
        """Download an attachment."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            # Select the folder
            if ' ' in folder or '/' in folder:
                folder = f'"{folder}"'
            
            status, _ = self.connection.select(folder)
            if status != 'OK':
                return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}
            
            status, data = self.connection.fetch(mail_uid.encode(), '(RFC822)')
            if status != 'OK':
                return {"success": False, "message": "메일 조회 실패"}
            
            raw_email = data[0][1]
            msg = email.message_from_bytes(raw_email)
            
            current_idx = 0
            for part in msg.walk():
                content_disposition = str(part.get("Content-Disposition", ""))
                
                if "attachment" in content_disposition:
                    if current_idx == attachment_index:
                        filename = part.get_filename()
                        if filename:
                            filename = self._decode_header(filename)
                        else:
                            filename = f"attachment_{attachment_index}"
                        
                        content = part.get_payload(decode=True)
                        content_type = part.get_content_type()
                        
                        return {
                            "success": True,
                            "filename": filename,
                            "content_type": content_type,
                            "content": content
                        }
                    current_idx += 1
            
            return {"success": False, "message": "첨부파일을 찾을 수 없음"}
        except Exception as e:
            return {"success": False, "message": f"첨부파일 다운로드 실패: {str(e)}"}
    
    # ========================================
    # Mail status changes
    # ========================================

    def mark_as_read(self, folder: str, mail_uid: str) -> Dict[str, Any]:
        """Mark as read."""
        return self._set_flag(folder, mail_uid, '\\Seen', True)

    def mark_as_unread(self, folder: str, mail_uid: str) -> Dict[str, Any]:
        """Mark as unread."""
        return self._set_flag(folder, mail_uid, '\\Seen', False)

    def mark_as_starred(self, folder: str, mail_uid: str) -> Dict[str, Any]:
        """Add a star."""
        return self._set_flag(folder, mail_uid, '\\Flagged', True)

    def unmark_starred(self, folder: str, mail_uid: str) -> Dict[str, Any]:
        """Remove a star."""
        return self._set_flag(folder, mail_uid, '\\Flagged', False)

    def _set_flag(self, folder: str, mail_uid: str, flag: str, add: bool) -> Dict[str, Any]:
        """Set/clear a flag."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            if ' ' in folder or '/' in folder:
                folder = f'"{folder}"'
            
            status, _ = self.connection.select(folder)
            if status != 'OK':
                return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}
            
            if add:
                status, _ = self.connection.store(mail_uid.encode(), '+FLAGS', flag)
            else:
                status, _ = self.connection.store(mail_uid.encode(), '-FLAGS', flag)
            
            if status == 'OK':
                return {"success": True, "message": "처리 완료"}
            return {"success": False, "message": "처리 실패"}
        except Exception as e:
            return {"success": False, "message": f"처리 실패: {str(e)}"}
    
    # ========================================
    # Mail move/delete
    # ========================================

    def move_mail(self, folder: str, mail_uid: str, target_folder: str) -> Dict[str, Any]:
        """Move mail."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}
            
            if ' ' in folder or '/' in folder:
                folder = f'"{folder}"'
            if ' ' in target_folder or '/' in target_folder:
                target_folder = f'"{target_folder}"'
            
            status, _ = self.connection.select(folder)
            if status != 'OK':
                return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}
            
            # Copy then delete
            status, _ = self.connection.copy(mail_uid.encode(), target_folder)
            if status != 'OK':
                return {"success": False, "message": "메일 복사 실패"}

            # Mark the original deleted
            self.connection.store(mail_uid.encode(), '+FLAGS', '\\Deleted')
            self.connection.expunge()
            
            return {"success": True, "message": "메일 이동 완료"}
        except Exception as e:
            return {"success": False, "message": f"메일 이동 실패: {str(e)}"}
    
    def delete_mail(self, folder: str, mail_uid: str, permanent: bool = False) -> Dict[str, Any]:
        """Delete mail."""
        try:
            if not self.connection:
                return {"success": False, "message": "연결되지 않음"}

            if permanent:
                # Permanent delete
                if ' ' in folder or '/' in folder:
                    folder = f'"{folder}"'
                
                status, _ = self.connection.select(folder)
                if status != 'OK':
                    return {"success": False, "message": f"폴더 '{folder}' 선택 실패"}
                
                self.connection.store(mail_uid.encode(), '+FLAGS', '\\Deleted')
                self.connection.expunge()
                return {"success": True, "message": "메일 영구 삭제 완료"}
            else:
                # Move to trash
                return self.move_mail(folder, mail_uid, '[Gmail]/Trash')
        except Exception as e:
            return {"success": False, "message": f"메일 삭제 실패: {str(e)}"}
