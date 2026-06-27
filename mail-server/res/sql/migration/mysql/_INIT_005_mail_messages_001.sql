-- 메일 메시지
CREATE TABLE mail_messages (
    message_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    folder_uuid VARCHAR(36) NOT NULL,
    
    -- IMAP 정보
    message_id VARCHAR(500) NOT NULL,  -- RFC822 Message-ID
    uid BIGINT NOT NULL,  -- IMAP UID
    
    -- 발신자/수신자
    from_email VARCHAR(255) NOT NULL,
    from_name VARCHAR(255) DEFAULT NULL,
    to_emails TEXT,  -- JSON array: ["email1", "email2"]
    cc_emails TEXT,  -- JSON array
    bcc_emails TEXT,  -- JSON array
    reply_to VARCHAR(255) DEFAULT NULL,
    
    -- 내용
    subject TEXT,
    preview TEXT,  -- 본문 미리보기 (200자)
    
    -- 날짜/시간
    sent_date DATETIME NOT NULL,
    received_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    
    -- 플래그
    is_read BOOLEAN DEFAULT FALSE,
    is_starred BOOLEAN DEFAULT FALSE,
    is_pinned BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    has_attachments BOOLEAN DEFAULT FALSE,
    
    -- 본문은 파일 경로만 저장
    body_file_path VARCHAR(500),  -- /data/mails/{account_uuid}/{message_uuid}.eml
    
    -- 메타데이터
    size_bytes INT DEFAULT 0,
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY unique_message (account_uuid, folder_uuid, uid),
    INDEX idx_account_folder (account_uuid, folder_uuid),
    INDEX idx_message_id (message_id),
    INDEX idx_sent_date (sent_date),
    INDEX idx_is_read (is_read),
    INDEX idx_from_email (from_email)
);
