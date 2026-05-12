CREATE TABLE nodes (
    storage_uuid VARCHAR(36) NOT NULL,
    node_uuid VARCHAR(36),
    name VARCHAR(255) NOT NULL,
    type ENUM('file', 'folder') NOT NULL,
    parent_uuid VARCHAR(36) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    creator_uuid VARCHAR(36) DEFAULT NULL,
    modifier_uuid VARCHAR(36) DEFAULT NULL,
    PRIMARY KEY (storage_uuid, node_uuid)
);
