-- R0001 stage 4 — 2FA TOTP. MailAnchor `totp_auth` 테이블의 Go 사이드카 정합본 [MySQL]
-- (res/sql/migration/mysql/_INIT_012_totp_auth_001.sql 대응). 사용자당 0/1행.
-- secret = base32 TOTP 시드, enabled = 활성화 여부,
-- recovery_codes = 1회용 복구코드 JSON 배열(TEXT). app_user 삭제 시 함께 정리.
CREATE TABLE totp_auth (
    user_id        VARCHAR(64) NOT NULL,
    secret         VARCHAR(64) NOT NULL,
    enabled        BOOLEAN NOT NULL DEFAULT FALSE,
    recovery_codes TEXT,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_totp_auth_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE INDEX idx_totp_enabled ON totp_auth(enabled);
