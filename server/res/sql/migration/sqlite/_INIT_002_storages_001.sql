CREATE TABLE storages (
    storage_uuid TEXT PRIMARY KEY
    , storage_name TEXT NOT NULL
    , storage_path TEXT NOT NULL
    , status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive'))
    , quota_limit INTEGER DEFAULT 10485760
    , creator_uuid TEXT DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid TEXT DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO storages (storage_uuid, storage_name, storage_path) VALUES ('00000000-0000-0000-0000-000000000001', 'System Root', '/');
