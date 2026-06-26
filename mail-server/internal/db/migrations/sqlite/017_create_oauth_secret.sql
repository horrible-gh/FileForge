-- Persistent OAuth SecretStore. credential_blob is either "plain:" + JSON in dev or
-- "gcm1:" + nonce/ciphertext/tag when MAILANCHOR_SECRET_ENCRYPTION_KEY is configured.
CREATE TABLE oauth_secret (
    oauth_ref       TEXT NOT NULL PRIMARY KEY,
    credential_blob BLOB NOT NULL,
    created_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at      TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
