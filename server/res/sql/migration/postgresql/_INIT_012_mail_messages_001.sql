-- Mail subsystem: messages (PostgreSQL). UNIQUE(account,folder,uid)=sync idempotency.
CREATE TABLE mail_messages (
    message_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
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
    sent_date TIMESTAMP NOT NULL,
    received_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_read BOOLEAN DEFAULT FALSE,
    is_starred BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    has_attachments BOOLEAN DEFAULT FALSE,
    body_file_path VARCHAR(500),
    size_bytes INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_message UNIQUE (account_uuid, folder_uuid, uid),
    CONSTRAINT fk_mail_messages_account FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_mail_messages_folder FOREIGN KEY (folder_uuid) REFERENCES mail_folders (folder_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_msg_account_folder ON mail_messages(account_uuid, folder_uuid);
CREATE INDEX idx_msg_message_id ON mail_messages(message_id);
CREATE INDEX idx_msg_sent_date ON mail_messages(sent_date);
CREATE INDEX idx_msg_is_read ON mail_messages(is_read);
CREATE INDEX idx_msg_from_email ON mail_messages(from_email);
