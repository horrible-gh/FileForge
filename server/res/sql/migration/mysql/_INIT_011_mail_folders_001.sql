-- Mail subsystem: folders. FK -> mail_accounts ON DELETE CASCADE (DB0007 §5).
CREATE TABLE mail_folders (
    folder_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    folder_name VARCHAR(255) NOT NULL,
    folder_path VARCHAR(500) NOT NULL,
    folder_type ENUM('inbox', 'sent', 'drafts', 'trash', 'spam', 'custom') DEFAULT 'custom',

    uidvalidity BIGINT DEFAULT NULL,
    last_uid BIGINT DEFAULT NULL,

    display_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_folder (account_uuid, folder_path),
    INDEX idx_folders_account (account_uuid),
    INDEX idx_folders_type (folder_type),
    CONSTRAINT fk_mail_folders_account FOREIGN KEY (account_uuid)
        REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
