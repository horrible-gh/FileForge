-- Mail subsystem: accounts (IMAP/SMTP + Gmail OAuth).
-- Absorbed from legacy mail-server _INIT_003/010/011, consolidated per DB0007 §3
-- (account_type / oauth tokens / nullable IMAP inlined into CREATE) + FK CASCADE (Gap C).
CREATE TABLE mail_accounts (
    account_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,
    account_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    account_type VARCHAR(20) NOT NULL DEFAULT 'imap',

    -- IMAP (nullable: gmail accounts have no IMAP host)
    imap_host VARCHAR(255) DEFAULT NULL,
    imap_port INT DEFAULT NULL,
    imap_use_ssl BOOLEAN DEFAULT NULL,
    imap_username VARCHAR(255) DEFAULT NULL,
    imap_password_encrypted TEXT DEFAULT NULL,

    -- SMTP (nullable)
    smtp_host VARCHAR(255) DEFAULT NULL,
    smtp_port INT DEFAULT NULL,
    smtp_use_tls BOOLEAN DEFAULT NULL,
    smtp_username VARCHAR(255) DEFAULT NULL,
    smtp_password_encrypted TEXT DEFAULT NULL,

    -- Gmail OAuth (encrypted at rest, L0006 2.3)
    access_token_encrypted TEXT DEFAULT NULL,
    refresh_token_encrypted TEXT DEFAULT NULL,
    token_expires_at DATETIME DEFAULT NULL,
    picture VARCHAR(500) DEFAULT NULL,

    -- Sync
    sync_enabled BOOLEAN DEFAULT TRUE,
    sync_interval INT DEFAULT 300,
    last_sync_at DATETIME DEFAULT NULL,

    -- Display
    display_color VARCHAR(7) DEFAULT '#4285f4',
    display_order INT DEFAULT 0,

    status ENUM('active', 'inactive', 'error') DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT chk_mail_accounts_type CHECK (account_type IN ('imap', 'gmail')),
    INDEX idx_accounts_user (user_uuid),
    INDEX idx_accounts_email (email),
    INDEX idx_accounts_type (account_type),
    INDEX idx_accounts_token_expires (token_expires_at),
    CONSTRAINT fk_mail_accounts_user FOREIGN KEY (user_uuid)
        REFERENCES users (user_uuid) ON DELETE CASCADE
);
