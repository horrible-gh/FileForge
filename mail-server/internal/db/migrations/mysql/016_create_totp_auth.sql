-- R0001 stage 4 — 2FA TOTP. MailAnchor `totp_auth` translated text Go translated text compatibilitytext [MySQL]
-- (res/sql/migration/mysql/_INIT_012_totp_auth_001.sql text). translated text 0/1text.
-- secret = base32 TOTP text, enabled = translated text text,
-- recovery_codes = 1text translated text JSON text(TEXT). app_user delete text text text.
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
