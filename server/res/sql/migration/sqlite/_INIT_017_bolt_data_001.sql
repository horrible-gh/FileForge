-- SecureBolt absorption: per-user encrypted vault blobs (SQLite).
-- One row per (user_uuid, data_type). content is a client-encrypted opaque
-- Base64 "Salted__…" string — the server never decrypts it (zero-knowledge).
-- See fileforge.securebolt.0001.0007-DB §3.2.
CREATE TABLE IF NOT EXISTS bolt_data (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_uuid   TEXT NOT NULL,
    data_type   TEXT NOT NULL CHECK (data_type IN ('password','category')),
    content     TEXT NOT NULL,
    version     TEXT NOT NULL DEFAULT '3.0',
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE (user_uuid, data_type),
    FOREIGN KEY (user_uuid) REFERENCES users(user_uuid) ON DELETE CASCADE
);
