-- name: delete
DELETE FROM totp_auth WHERE user_id = :user_id;
