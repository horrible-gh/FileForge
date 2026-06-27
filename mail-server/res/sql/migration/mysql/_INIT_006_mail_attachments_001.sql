-- 첨부파일
CREATE TABLE mail_attachments (
    attachment_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    message_uuid VARCHAR(36) NOT NULL,
    
    filename VARCHAR(255) NOT NULL,
    content_type VARCHAR(100),
    size_bytes INT DEFAULT 0,
    
    -- 파일 저장 경로 (로컬 파일시스템)
    file_path VARCHAR(500),
    
    -- 인라인 이미지 여부
    is_inline BOOLEAN DEFAULT FALSE,
    content_id VARCHAR(255) DEFAULT NULL,  -- Content-ID for inline images
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    INDEX idx_message_uuid (message_uuid)
);
