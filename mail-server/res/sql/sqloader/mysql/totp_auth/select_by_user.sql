-- name: select_by_user
SELECT * FROM totp_auth WHERE user_id = :user_id;
