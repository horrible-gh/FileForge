CREATE TABLE storages (
    storage_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY
    , storage_name VARCHAR(255) NOT NULL
    , storage_path VARCHAR(500) NOT NULL
    , status ENUM('active', 'inactive') DEFAULT 'active' -- Status: active or inactive
    , quota_limit BIGINT DEFAULT 10485760   -- bytes 단위, 기본 10MB
    , creator_uuid VARCHAR(36) DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid VARCHAR(36) DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO storages (storage_name, storage_path) VALUES ('System Root', '/');
