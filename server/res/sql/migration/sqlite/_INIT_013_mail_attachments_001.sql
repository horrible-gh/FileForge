-- Mail subsystem: attachments (SQLite).
CREATE TABLE IF NOT EXISTS mail_attachments (
    attachment_uuid TEXT PRIMARY KEY,
    message_uuid TEXT NOT NULL,
    filename TEXT NOT NULL,
    content_type TEXT,
    size_bytes INTEGER DEFAULT 0,
    file_path TEXT,
    is_inline INTEGER DEFAULT 0,
    content_id TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (message_uuid) REFERENCES mail_messages (message_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_att_message ON mail_attachments(message_uuid);
