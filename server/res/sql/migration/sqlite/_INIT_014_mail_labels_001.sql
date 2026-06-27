-- Mail subsystem: labels (SQLite).
CREATE TABLE IF NOT EXISTS mail_labels (
    label_uuid TEXT PRIMARY KEY,
    user_uuid TEXT NOT NULL,
    label_name TEXT NOT NULL,
    label_color TEXT DEFAULT '#4a6cf7',
    display_order INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_uuid, label_name),
    FOREIGN KEY (user_uuid) REFERENCES users (user_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_labels_user ON mail_labels(user_uuid);
