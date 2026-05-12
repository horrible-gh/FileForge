CREATE TABLE files (
    node_uuid VARCHAR(36) PRIMARY KEY,
    file_hash VARCHAR(64),
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    creator_uuid VARCHAR(36) DEFAULT NULL,
    modifier_uuid VARCHAR(36) DEFAULT NULL
);
