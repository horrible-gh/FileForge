CREATE TABLE files (
    node_uuid TEXT PRIMARY KEY,
    file_hash TEXT,
    file_size INTEGER NOT NULL,
    mime_type TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    creator_uuid TEXT DEFAULT NULL,
    modifier_uuid TEXT DEFAULT NULL
);
