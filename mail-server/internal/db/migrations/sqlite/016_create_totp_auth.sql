-- R0001 stage 4 — 2FA TOTP. MailAnchor `totp_auth` 테이블의 Go 사이드카 정합본
-- (res/sql/migration/sqlite/_INIT_012_totp_auth_001.sql 대응). 사용자당 0/1행.
-- secret = base32 TOTP 시드, enabled = 활성화(앱 스캔+첫코드 검증) 여부,
-- recovery_codes = 1회용 복구코드 JSON 배열(TEXT). app_user 삭제 시 함께 정리.
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
