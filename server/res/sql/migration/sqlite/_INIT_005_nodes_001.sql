CREATE TABLE nodes (
    storage_uuid TEXT NOT NULL,
    node_uuid TEXT,
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('file', 'folder')),
    parent_uuid TEXT DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    creator_uuid TEXT DEFAULT NULL,
    modifier_uuid TEXT DEFAULT NULL,
    PRIMARY KEY (storage_uuid, node_uuid)
);
