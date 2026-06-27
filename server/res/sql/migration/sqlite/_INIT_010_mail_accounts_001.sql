-- Mail subsystem: accounts. SQLite equivalent (DB0007). BOOLEAN->INTEGER 0/1, app-supplied UUID.
CREATE TABLE IF NOT EXISTS mail_accounts (
    account_uuid TEXT PRIMARY KEY,
    user_uuid TEXT NOT NULL,
    account_name TEXT NOT NULL,
    email TEXT NOT NULL,
    account_type TEXT NOT NULL DEFAULT 'imap' CHECK (account_type IN ('imap','gmail')),
    imap_host TEXT DEFAULT NULL,
    imap_port INTEGER DEFAULT NULL,
    imap_use_ssl INTEGER DEFAULT NULL,
    imap_username TEXT DEFAULT NULL,
    imap_password_encrypted TEXT DEFAULT NULL,
    smtp_host TEXT DEFAULT NULL,
    smtp_port INTEGER DEFAULT NULL,
    smtp_use_tls INTEGER DEFAULT NULL,
    smtp_username TEXT DEFAULT NULL,
    smtp_password_encrypted TEXT DEFAULT NULL,
    access_token_encrypted TEXT DEFAULT NULL,
    refresh_token_encrypted TEXT DEFAULT NULL,
    token_expires_at DATETIME DEFAULT NULL,
    picture TEXT DEFAULT NULL,
    sync_enabled INTEGER DEFAULT 1,
    sync_interval INTEGER DEFAULT 300,
    last_sync_at DATETIME DEFAULT NULL,
    display_color TEXT DEFAULT '#4285f4',
    display_order INTEGER DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','error')),
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_uuid) REFERENCES users (user_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_accounts_user ON mail_accounts(user_uuid);
CREATE INDEX IF NOT EXISTS idx_accounts_email ON mail_accounts(email);
CREATE INDEX IF NOT EXISTS idx_accounts_type ON mail_accounts(account_type);
CREATE INDEX IF NOT EXISTS idx_accounts_token_expires ON mail_accounts(token_expires_at);
