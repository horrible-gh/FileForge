-- Add 'mail' as a first-class storage_type (MailAnchor absorption).
-- SQLite cannot ALTER an existing CHECK constraint, so the table is rebuilt
-- with the widened constraint (file/note/password/mail). No FOREIGN KEY
-- references storages in this schema, so the drop/rename is safe.
-- All statements run inside a single migration transaction (see DatabaseMigrator).
CREATE TABLE storages_new (
    storage_uuid TEXT PRIMARY KEY
    , storage_name TEXT NOT NULL
    , storage_path TEXT NOT NULL
    , status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive'))
    , quota_limit INTEGER DEFAULT 10485760
    , creator_uuid TEXT DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid TEXT DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP
    , storage_type TEXT DEFAULT 'file' CHECK (storage_type IN ('file', 'note', 'password', 'mail'))
);

INSERT INTO storages_new (
    storage_uuid, storage_name, storage_path, status, quota_limit,
    creator_uuid, created_at, modifier_uuid, modified_at, storage_type
)
SELECT
    storage_uuid, storage_name, storage_path, status, quota_limit,
    creator_uuid, created_at, modifier_uuid, modified_at, storage_type
FROM storages;

DROP TABLE storages;

ALTER TABLE storages_new RENAME TO storages;
