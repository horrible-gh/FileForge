-- 1. 새 컬럼 추가 (기존 테이블에)
ALTER TABLE mail_accounts 
ADD COLUMN IF NOT EXISTS account_type VARCHAR(20) DEFAULT 'imap' COMMENT 'imap | gmail',
ADD COLUMN IF NOT EXISTS access_token_encrypted TEXT COMMENT 'Gmail OAuth access_token (암호화)',
ADD COLUMN IF NOT EXISTS refresh_token_encrypted TEXT COMMENT 'Gmail OAuth refresh_token (암호화)',
ADD COLUMN IF NOT EXISTS token_expires_at DATETIME COMMENT 'access_token 만료 시간',
ADD COLUMN IF NOT EXISTS picture VARCHAR(500) COMMENT 'Google 프로필 이미지 URL';

-- 2. 기존 계정들 타입 설정
UPDATE mail_accounts SET account_type = 'imap' WHERE account_type IS NULL;

-- 3. 인덱스 추가
CREATE INDEX IF NOT EXISTS idx_mail_accounts_type ON mail_accounts(account_type);
CREATE INDEX IF NOT EXISTS idx_mail_accounts_token_expires ON mail_accounts(token_expires_at);
