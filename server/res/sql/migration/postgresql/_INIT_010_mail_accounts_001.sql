-- Mail subsystem: accounts (IMAP/SMTP + Gmail OAuth). Canonical PostgreSQL DDL (DB0007).
-- Consolidates legacy _INIT_003/010/011 + adds FK CASCADE (Gap C).
CREATE TABLE mail_accounts (
    account_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,
    account_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    account_type VARCHAR(20) NOT NULL DEFAULT 'imap' CHECK (account_type IN ('imap','gmail')),
    imap_host VARCHAR(255) DEFAULT NULL,
    imap_port INTEGER DEFAULT NULL,
    imap_use_ssl BOOLEAN DEFAULT NULL,
    imap_username VARCHAR(255) DEFAULT NULL,
    imap_password_encrypted TEXT DEFAULT NULL,
    smtp_host VARCHAR(255) DEFAULT NULL,
    smtp_port INTEGER DEFAULT NULL,
    smtp_use_tls BOOLEAN DEFAULT NULL,
    smtp_username VARCHAR(255) DEFAULT NULL,
    smtp_password_encrypted TEXT DEFAULT NULL,
    access_token_encrypted TEXT DEFAULT NULL,
    refresh_token_encrypted TEXT DEFAULT NULL,
    token_expires_at TIMESTAMP DEFAULT NULL,
    picture VARCHAR(500) DEFAULT NULL,
    sync_enabled BOOLEAN DEFAULT TRUE,
    sync_interval INTEGER DEFAULT 300,
    last_sync_at TIMESTAMP DEFAULT NULL,
    display_color VARCHAR(7) DEFAULT '#4285f4',
    display_order INTEGER DEFAULT 0,
    status VARCHAR(10) NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','error')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mail_accounts_user FOREIGN KEY (user_uuid) REFERENCES users (user_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_accounts_user ON mail_accounts(user_uuid);
CREATE INDEX idx_accounts_email ON mail_accounts(email);
CREATE INDEX idx_accounts_type ON mail_accounts(account_type);
CREATE INDEX idx_accounts_token_expires ON mail_accounts(token_expires_at);
