-- Persistent OAuth SecretStore. credential_blob is either "plain:" + JSON in dev or
-- "gcm1:" + nonce/ciphertext/tag when MAILANCHOR_SECRET_ENCRYPTION_KEY is configured.
CREATE TABLE oauth_secret (
    oauth_ref       VARCHAR(64) NOT NULL,
    credential_blob LONGBLOB NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (oauth_ref)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
