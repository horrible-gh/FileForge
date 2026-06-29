-- SecureBolt absorption: per-user encrypted vault blobs (MySQL 8.x, utf8mb4).
-- One row per (user_uuid, data_type). content is a client-encrypted opaque
-- Base64 "Salted__…" string — the server never decrypts it (zero-knowledge).
-- See fileforge.securebolt.0001.0007-DB §3.2.
CREATE TABLE IF NOT EXISTS bolt_data (
    id          BIGINT NOT NULL AUTO_INCREMENT,
    user_uuid   VARCHAR(36) NOT NULL,
    data_type   VARCHAR(16) NOT NULL,
    content     LONGTEXT NOT NULL,
    version     VARCHAR(16) NOT NULL DEFAULT '3.0',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_bolt_user_type (user_uuid, data_type),
    CONSTRAINT chk_bolt_data_type CHECK (data_type IN ('password','category')),
    CONSTRAINT fk_bolt_user FOREIGN KEY (user_uuid) REFERENCES users(user_uuid) ON DELETE CASCADE
);
