-- Mail subsystem: message<->label link (SQLite).
CREATE TABLE IF NOT EXISTS mail_message_labels (
    message_uuid TEXT NOT NULL,
    label_uuid TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_uuid, label_uuid),
    FOREIGN KEY (message_uuid) REFERENCES mail_messages (message_uuid) ON DELETE CASCADE,
    FOREIGN KEY (label_uuid) REFERENCES mail_labels (label_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_msglabels_label ON mail_message_labels(label_uuid, message_uuid);
