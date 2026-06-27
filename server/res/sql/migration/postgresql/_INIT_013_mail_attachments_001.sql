-- Mail subsystem: attachments (PostgreSQL).
CREATE TABLE mail_attachments (
    attachment_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
    message_uuid VARCHAR(36) NOT NULL,
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes INTEGER DEFAULT 0,
    file_path VARCHAR(500),
    is_inline BOOLEAN DEFAULT FALSE,
    content_id VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_mail_attachments_message FOREIGN KEY (message_uuid) REFERENCES mail_messages (message_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_att_message ON mail_attachments(message_uuid);
