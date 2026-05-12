CREATE TABLE shared_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT UNIQUE NOT NULL,
    node_uuid TEXT NOT NULL,
    node_type TEXT NOT NULL,
    password_hash TEXT,
    created_by TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_shared_links_token ON shared_links(token);
