"""
MailAnchor - Services Package
"""

from .imap_service import IMAPService
from .smtp_service import SMTPService, test_smtp_connection, send_simple_mail
from .mail_service import MailAccount, MailAccountService, mail_service
from .gmail_service import GmailOAuthService

__all__ = [
    'IMAPService',
    'SMTPService',
    'test_smtp_connection',
    'send_simple_mail',
    'MailAccount',
    'MailAccountService',
    'mail_service',
    'GmailOAuthService',
]
