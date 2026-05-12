CREATE TABLE user_storages (
    group_uuid VARCHAR(36) DEFAULT NULL
    , user_uuid VARCHAR(36)
    , storage_uuid VARCHAR(36)
    , is_default TINYINT(1) DEFAULT 0
    , creator_uuid VARCHAR(36) DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid VARCHAR(36) DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    , PRIMARY KEY (user_uuid, storage_uuid)
);

CREATE INDEX IX_user_storages_001 ON user_storages (group_uuid, storage_uuid);

INSERT INTO user_storages (user_uuid, storage_uuid, is_default) VALUES (
    (SELECT user_uuid FROM users WHERE user_id = 'fileforge'),
    (SELECT storage_uuid FROM storages WHERE storage_name = 'System Root'),
    1
);