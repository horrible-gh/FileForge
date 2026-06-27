# schemas/mail/accounts.py
from typing import List, Optional
from pydantic import BaseModel

class AccountGetRequest(BaseModel):
    user_uuid: str

class AccountCreateRequest(BaseModel):
    user_uuid: str
    account_name: str
    email: str
    imap_host: str
    imap_port: int = 993
    imap_use_ssl: bool = True
    imap_username: str
    imap_password: str
    smtp_host: str
    smtp_port: int = 587
    smtp_use_tls: bool = True
    smtp_username: str
    smtp_password: str
    display_color: Optional[str] = '#4285f4'

class AccountUpdateRequest(BaseModel):
    user_uuid: str
    account_uuid: str
    account_name: Optional[str] = None
    imap_password: Optional[str] = None
    smtp_password: Optional[str] = None
    display_color: Optional[str] = None
    sync_enabled: Optional[bool] = None
    