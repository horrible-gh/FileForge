-- R0001 stage 4 — 2FA TOTP. MailAnchor `totp_auth` translated text Go translated text compatibilitytext
-- (res/sql/migration/sqlite/_INIT_012_totp_auth_001.sql text). translated text 0/1text.
-- secret = base32 TOTP text, enabled = translated text(text text+translated text verify) text,
-- recovery_codes = 1text translated text JSON text(TEXT). app_user delete text text text.
CREATE TABLE totp_auth (
    user_id        TEXT NOT NULL PRIMARY KEY,
    secret         TEXT NOT NULL,
    enabled        INTEGER NOT NULL DEFAULT 0,  -- SQLite BOOLEAN = INTEGER(0/1)
    recovery_codes TEXT,
    created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE
);
CREATE INDEX idx_totp_enabled ON totp_auth(enabled);
