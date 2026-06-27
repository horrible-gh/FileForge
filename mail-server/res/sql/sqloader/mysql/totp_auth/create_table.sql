-- Create TOTP authentication table
CREATE TABLE IF NOT EXISTS totp_auth (
    user_id VARCHAR(255) PRIMARY KEY,
    secret VARCHAR(255) NOT NULL,
    enabled BOOLEAN DEFAULT FALSE,
    recovery_codes TEXT,
    created_at DATETIME NOT NULL,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_totp_auth_user_id ON totp_auth(user_id);
CREATE INDEX IF NOT EXISTS idx_totp_auth_enabled ON totp_auth(enabled);