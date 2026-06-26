CREATE TABLE shared_links (
    id SERIAL PRIMARY KEY,
    token VARCHAR(64) UNIQUE NOT NULL,
    node_uuid VARCHAR(64) NOT NULL,     -- file text folder
    node_type VARCHAR(10) NOT NULL,     -- 'file' or 'folder'
    password_hash VARCHAR(256),         -- NULLtext password None
    created_by VARCHAR(64) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_shared_links_token ON shared_links(token);
