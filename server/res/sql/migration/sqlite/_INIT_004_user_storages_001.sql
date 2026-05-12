CREATE TABLE user_storages (
    group_uuid TEXT DEFAULT NULL
    , user_uuid TEXT
    , storage_uuid TEXT
    , is_default INTEGER DEFAULT 0
    , creator_uuid TEXT DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid TEXT DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP
    , PRIMARY KEY (user_uuid, storage_uuid)
);

CREATE INDEX IX_user_storages_001 ON user_storages (group_uuid, storage_uuid);
