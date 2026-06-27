-- Mail subsystem: folders (SQLite).
CREATE TABLE IF NOT EXISTS mail_folders (
    folder_uuid TEXT PRIMARY KEY,
    account_uuid TEXT NOT NULL,
    folder_name TEXT NOT NULL,
    folder_path TEXT NOT NULL,
    folder_type TEXT NOT NULL DEFAULT 'custom' CHECK (folder_type IN ('inbox','sent','drafts','trash','spam','custom')),
    uidvalidity INTEGER DEFAULT NULL,
    last_uid INTEGER DEFAULT NULL,
    display_order INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (account_uuid, folder_path),
    FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_folders_account ON mail_folders(account_uuid);
CREATE INDEX IF NOT EXISTS idx_folders_type ON mail_folders(folder_type);
