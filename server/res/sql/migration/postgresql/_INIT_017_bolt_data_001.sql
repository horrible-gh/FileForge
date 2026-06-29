-- SecureBolt absorption: per-user encrypted vault blobs (PostgreSQL).
-- One row per (user_uuid, data_type). content is a client-encrypted opaque
-- Base64 "Salted__…" string — the server never decrypts it (zero-knowledge).
-- See fileforge.securebolt.0001.0007-DB §3.2.
CREATE TABLE IF NOT EXISTS bolt_data (
    id          BIGSERIAL PRIMARY KEY,
    user_uuid   VARCHAR(36) NOT NULL,
    data_type   VARCHAR(16) NOT NULL CHECK (data_type IN ('password','category')),
    content     TEXT NOT NULL,
    version     VARCHAR(16) NOT NULL DEFAULT '3.0',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_bolt_user_type UNIQUE (user_uuid, data_type),
    CONSTRAINT fk_bolt_user FOREIGN KEY (user_uuid) REFERENCES users(user_uuid) ON DELETE CASCADE
);
