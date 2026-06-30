"""
MailAnchor - Mail Account Service
Unified mail account management (IMAP/SMTP connection management)
"""

from typing import Optional, Dict, Any, List
from dataclasses import dataclass
from .imap_service import IMAPService
from .smtp_service import SMTPService, test_smtp_connection


# @dataclass
class MailAccount:
    """Mail account info."""
    account_id: str
    account_name: str
    email: str

    # IMAP settings
    imap_host: str
    imap_port: int
    imap_username: str
    imap_password: str
    imap_use_ssl: bool = True
    
    # SMTP settings
    smtp_host: str
    smtp_port: int
    smtp_username: str
    smtp_password: str
    
    # Display settings
    display_color: str = "#4285f4"
    display_name: Optional[str] = None  # sender name


class MailAccountService:
    """Unified mail account service."""
    
    def __init__(self):
        self._imap_connections: Dict[str, IMAPService] = {}
        self._smtp_connections: Dict[str, SMTPService] = {}
        self._accounts: Dict[str, MailAccount] = {}
    
    # ========================================
    # Account management
    # ========================================

    def add_account(self, account: MailAccount) -> Dict[str, Any]:
        """Add an account."""
        self._accounts[account.account_id] = account
        return {"success": True, "message": f"계정 '{account.account_name}' 추가됨"}
    
    def remove_account(self, account_id: str) -> Dict[str, Any]:
        """Remove an account."""
        # Close connections
        self.disconnect_imap(account_id)
        self.disconnect_smtp(account_id)
        
        if account_id in self._accounts:
            del self._accounts[account_id]
            return {"success": True, "message": "계정 제거됨"}
        return {"success": False, "message": "계정을 찾을 수 없음"}
    
    def get_account(self, account_id: str) -> Optional[MailAccount]:
        """Get an account."""
        return self._accounts.get(account_id)
    
    def get_all_accounts(self) -> List[MailAccount]:
        """List all accounts."""
        return list(self._accounts.values())
    
    # ========================================
    # Connection test
    # ========================================

    def test_connection(self, account: MailAccount) -> Dict[str, Any]:
        """IMAP/SMTP connection test."""
        results = {
            "imap": {"success": False, "message": ""},
            "smtp": {"success": False, "message": ""}
        }
        
        # IMAP test
        try:
            imap = IMAPService(
                host=account.imap_host,
                port=account.imap_port,
                username=account.imap_username,
                password=account.imap_password,
                use_ssl=account.imap_use_ssl
            )
            result = imap.connect()
            results["imap"] = result
            imap.disconnect()
        except Exception as e:
            results["imap"] = {"success": False, "message": str(e)}
        
        # SMTP test
        results["smtp"] = test_smtp_connection(
            host=account.smtp_host,
            port=account.smtp_port,
            username=account.smtp_username,
            password=account.smtp_password
        )
        
        return results
    
    # ========================================
    # IMAP connection management
    # ========================================

    def get_imap(self, account_id: str) -> Optional[IMAPService]:
        """Get the IMAP connection (create if absent)."""
        if account_id in self._imap_connections:
            return self._imap_connections[account_id]
        
        account = self._accounts.get(account_id)
        if not account:
            return None
        
        imap = IMAPService(
            host=account.imap_host,
            port=account.imap_port,
            username=account.imap_username,
            password=account.imap_password,
            use_ssl=account.imap_use_ssl
        )
        
        result = imap.connect()
        if result["success"]:
            self._imap_connections[account_id] = imap
            return imap
        
        return None
    
    def disconnect_imap(self, account_id: str):
        """Close the IMAP connection."""
        if account_id in self._imap_connections:
            self._imap_connections[account_id].disconnect()
            del self._imap_connections[account_id]
    
    # ========================================
    # SMTP connection management
    # ========================================

    def get_smtp(self, account_id: str) -> Optional[SMTPService]:
        """Get the SMTP connection (create if absent)."""
        if account_id in self._smtp_connections:
            return self._smtp_connections[account_id]
        
        account = self._accounts.get(account_id)
        if not account:
            return None
        
        smtp = SMTPService(
            host=account.smtp_host,
            port=account.smtp_port,
            username=account.smtp_username,
            password=account.smtp_password
        )
        
        result = smtp.connect()
        if result["success"]:
            self._smtp_connections[account_id] = smtp
            return smtp
        
        return None
    
    def disconnect_smtp(self, account_id: str):
        """Close the SMTP connection."""
        if account_id in self._smtp_connections:
            self._smtp_connections[account_id].disconnect()
            del self._smtp_connections[account_id]
    
    # ========================================
    # Unified features
    # ========================================

    def get_all_folders(self) -> Dict[str, Any]:
        """List folders across all accounts."""
        all_folders = {}
        
        for account_id, account in self._accounts.items():
            imap = self.get_imap(account_id)
            if imap:
                result = imap.get_folders()
                if result["success"]:
                    all_folders[account_id] = {
                        "account_name": account.account_name,
                        "email": account.email,
                        "color": account.display_color,
                        "folders": result["folders"]
                    }
        
        return {"success": True, "accounts": all_folders}
    
    def get_unified_inbox(self, page: int = 1, limit: int = 20) -> Dict[str, Any]:
        """Retrieve the unified inbox."""
        all_mails = []
        
        for account_id, account in self._accounts.items():
            imap = self.get_imap(account_id)
            if imap:
                result = imap.get_mail_list(folder="INBOX", page=1, limit=100)  # fetch a lot and merge
                if result["success"]:
                    for mail in result["mails"]:
                        mail["account_id"] = account_id
                        mail["account_name"] = account.account_name
                        mail["account_email"] = account.email
                        mail["account_color"] = account.display_color
                        all_mails.append(mail)
        
        # Sort by date
        all_mails.sort(key=lambda x: x.get("date", ""), reverse=True)

        # Paging
        total_count = len(all_mails)
        start_idx = (page - 1) * limit
        end_idx = start_idx + limit
        paged_mails = all_mails[start_idx:end_idx]
        
        return {
            "success": True,
            "mails": paged_mails,
            "total_count": total_count,
            "page": page,
            "limit": limit,
            "total_pages": (total_count + limit - 1) // limit
        }
    
    def send_mail(
        self,
        account_id: str,
        to_addresses: List[str],
        subject: str,
        body_text: str = "",
        body_html: str = "",
        cc_addresses: Optional[List[str]] = None,
        bcc_addresses: Optional[List[str]] = None,
        attachments: Optional[List[Dict[str, Any]]] = None
    ) -> Dict[str, Any]:
        """Send mail."""
        account = self._accounts.get(account_id)
        if not account:
            return {"success": False, "message": "계정을 찾을 수 없음"}
        
        smtp = self.get_smtp(account_id)
        if not smtp:
            return {"success": False, "message": "SMTP 연결 실패"}
        
        return smtp.send_mail(
            from_name=account.display_name or account.account_name,
            from_email=account.email,
            to_addresses=to_addresses,
            subject=subject,
            body_text=body_text,
            body_html=body_html,
            cc_addresses=cc_addresses,
            bcc_addresses=bcc_addresses,
            attachments=attachments
        )
    
    def disconnect_all(self):
        """Close all connections."""
        for account_id in list(self._imap_connections.keys()):
            self.disconnect_imap(account_id)
        
        for account_id in list(self._smtp_connections.keys()):
            self.disconnect_smtp(account_id)


# Global instance
mail_service = MailAccountService()
