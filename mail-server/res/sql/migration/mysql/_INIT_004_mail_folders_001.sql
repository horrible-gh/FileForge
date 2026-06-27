-- 메일 폴더
CREATE TABLE mail_folders (
    folder_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    folder_name VARCHAR(255) NOT NULL,  -- INBOX, Sent, Drafts, Trash, etc
    folder_path VARCHAR(500) NOT NULL,  -- IMAP 폴더 경로
    folder_type ENUM('inbox', 'sent', 'drafts', 'trash', 'spam', 'custom') DEFAULT 'custom',
    
    -- IMAP 동기화 정보
    uidvalidity BIGINT DEFAULT NULL,
    last_uid BIGINT DEFAULT NULL,
    
    display_order INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY unique_folder (account_uuid, folder_path),
    INDEX idx_account_uuid (account_uuid),
    INDEX idx_folder_type (folder_type)
);