-- 메일 계정 (IMAP/SMTP 설정)
CREATE TABLE mail_accounts (
    account_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,
    account_name VARCHAR(255) NOT NULL,  -- 별칭 (예: "개인 메일")
    email VARCHAR(255) NOT NULL,
    
    -- IMAP 설정
    imap_host VARCHAR(255) NOT NULL,
    imap_port INT NOT NULL DEFAULT 993,
    imap_use_ssl BOOLEAN DEFAULT TRUE,
    imap_username VARCHAR(255) NOT NULL,
    imap_password_encrypted TEXT NOT NULL,  -- 암호화된 비밀번호
    
    -- SMTP 설정
    smtp_host VARCHAR(255) NOT NULL,
    smtp_port INT NOT NULL DEFAULT 587,
    smtp_use_tls BOOLEAN DEFAULT TRUE,
    smtp_username VARCHAR(255) NOT NULL,
    smtp_password_encrypted TEXT NOT NULL,  -- 암호화된 비밀번호
    
    -- 동기화 설정
    sync_enabled BOOLEAN DEFAULT TRUE,
    sync_interval INT DEFAULT 300,  -- 초 단위 (기본 5분)
    last_sync_at DATETIME DEFAULT NULL,
    
    -- 표시 설정
    display_color VARCHAR(7) DEFAULT '#4285f4',  -- 계정 구분 색상
    display_order INT DEFAULT 0,
    
    status ENUM('active', 'inactive', 'error') DEFAULT 'active',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_user_uuid (user_uuid),
    INDEX idx_email (email)
);
