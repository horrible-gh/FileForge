-- 2FA TOTP Authentication Table
-- auth2fa 패키지를 위한 테이블 생성

CREATE TABLE IF NOT EXISTS totp_auth (
    user_id VARCHAR(64) PRIMARY KEY,
    secret VARCHAR(64) NOT NULL,
    enabled BOOLEAN DEFAULT FALSE,
    recovery_codes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 인덱스 추가
CREATE INDEX idx_totp_enabled ON totp_auth(enabled);
CREATE INDEX idx_totp_created_at ON totp_auth(created_at);
