-- name: update
UPDATE totp_auth SET enabled = :enabled, recovery_codes = :recovery_codes WHERE user_id = :user_id;
