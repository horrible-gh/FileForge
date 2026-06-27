-- Mail subsystem: messages (SQLite).
CREATE TABLE IF NOT EXISTS mail_messages (
    message_uuid TEXT PRIMARY KEY,
    account_uuid TEXT NOT NULL,
    folder_uuid TEXT NOT NULL,
    message_id TEXT NOT NULL,
    uid INTEGER NOT NULL,
    from_email TEXT NOT NULL,
    from_name TEXT DEFAULT NULL,
    to_emails TEXT,
    cc_emails TEXT,
    bcc_emails TEXT,
    reply_to TEXT DEFAULT NULL,
    subject TEXT,
    preview TEXT,
    sent_date DATETIME NOT NULL,
    received_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_read INTEGER DEFAULT 0,
    is_starred INTEGER DEFAULT 0,
    is_pinned INTEGER DEFAULT 0,
    is_deleted INTEGER DEFAULT 0,
    has_attachments INTEGER DEFAULT 0,
    body_file_path TEXT,
    size_bytes INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (account_uuid, folder_uuid, uid),
    FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE,
    FOREIGN KEY (folder_uuid) REFERENCES mail_folders (folder_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_msg_account_folder ON mail_messages(account_uuid, folder_uuid);
CREATE INDEX IF NOT EXISTS idx_msg_message_id ON mail_messages(message_id);
CREATE INDEX IF NOT EXISTS idx_msg_sent_date ON mail_messages(sent_date);
CREATE INDEX IF NOT EXISTS idx_msg_is_read ON mail_messages(is_read);
CREATE INDEX IF NOT EXISTS idx_msg_from_email ON mail_messages(from_email);
