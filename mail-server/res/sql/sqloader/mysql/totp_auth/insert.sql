-- name: insert
INSERT INTO totp_auth (user_id, secret, enabled, recovery_codes, created_at)
VALUES (:user_id, :secret, :enabled, :recovery_codes, :created_at)
ON CONFLICT (user_id) DO UPDATE
SET secret = EXCLUDED.secret,
    enabled = EXCLUDED.enabled,
    recovery_codes = EXCLUDED.recovery_codes;
