-- Mail subsystem: folders (PostgreSQL).
CREATE TABLE mail_folders (
    folder_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    folder_name VARCHAR(255) NOT NULL,
    folder_path VARCHAR(500) NOT NULL,
    folder_type VARCHAR(10) NOT NULL DEFAULT 'custom' CHECK (folder_type IN ('inbox','sent','drafts','trash','spam','custom')),
    uidvalidity BIGINT DEFAULT NULL,
    last_uid BIGINT DEFAULT NULL,
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_folder UNIQUE (account_uuid, folder_path),
    CONSTRAINT fk_mail_folders_account FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_folders_account ON mail_folders(account_uuid);
CREATE INDEX idx_folders_type ON mail_folders(folder_type);
