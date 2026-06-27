-- Mail subsystem: attachments. FK -> mail_messages ON DELETE CASCADE.
CREATE TABLE mail_attachments (
    attachment_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    message_uuid VARCHAR(36) NOT NULL,

    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes INT DEFAULT 0,
    file_path VARCHAR(500),

    is_inline BOOLEAN DEFAULT FALSE,
    content_id VARCHAR(255) DEFAULT NULL,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,

    INDEX idx_att_message (message_uuid),
    CONSTRAINT fk_mail_attachments_message FOREIGN KEY (message_uuid)
        REFERENCES mail_messages (message_uuid) ON DELETE CASCADE
);
