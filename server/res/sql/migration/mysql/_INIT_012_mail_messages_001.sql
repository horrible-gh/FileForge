-- Mail subsystem: messages (body stored as .eml file path only).
-- UNIQUE(account,folder,uid) = sync idempotency (L0006 2.4 / DB0007 §5).
-- FK -> mail_accounts, mail_folders ON DELETE CASCADE.
CREATE TABLE mail_messages (
    message_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    folder_uuid VARCHAR(36) NOT NULL,

    message_id VARCHAR(500) NOT NULL,
    uid BIGINT NOT NULL,

    from_email VARCHAR(255) NOT NULL,
    from_name VARCHAR(255) DEFAULT NULL,
    to_emails TEXT,
    cc_emails TEXT,
    bcc_emails TEXT,
    reply_to VARCHAR(255) DEFAULT NULL,

    subject TEXT,
    preview TEXT,

    sent_date DATETIME NOT NULL,
    received_date DATETIME DEFAULT CURRENT_TIMESTAMP,

    is_read BOOLEAN DEFAULT FALSE,
    is_starred BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    has_attachments BOOLEAN DEFAULT FALSE,

    body_file_path VARCHAR(500),
    size_bytes INT DEFAULT 0,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_message (account_uuid, folder_uuid, uid),
    INDEX idx_msg_account_folder (account_uuid, folder_uuid),
    INDEX idx_msg_message_id (message_id),
    INDEX idx_msg_sent_date (sent_date),
    INDEX idx_msg_is_read (is_read),
    INDEX idx_msg_from_email (from_email),
    CONSTRAINT fk_mail_messages_account FOREIGN KEY (account_uuid)
        REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_mail_messages_folder FOREIGN KEY (folder_uuid)
        REFERENCES mail_folders (folder_uuid) ON DELETE CASCADE
);
