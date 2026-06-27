-- 2FA TOTP Authentication Table (SQLite)
-- auth2fa 패키지를 위한 테이블 생성

CREATE TABLE IF NOT EXISTS totp_auth (
    user_id TEXT PRIMARY KEY,
    secret TEXT NOT NULL,
    enabled INTEGER DEFAULT 0,  -- SQLite에서는 BOOLEAN이 INTEGER로 저장됨
    recovery_codes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 인덱스 추가
CREATE INDEX IF NOT EXISTS idx_totp_enabled ON totp_auth(enabled);
CREATE INDEX IF NOT EXISTS idx_totp_created_at ON totp_auth(created_at);
