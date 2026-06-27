-- Mail subsystem: labels (PostgreSQL).
CREATE TABLE mail_labels (
    label_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,
    label_name VARCHAR(100) NOT NULL,
    label_color VARCHAR(7) DEFAULT '#4a6cf7',
    display_order INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_label UNIQUE (user_uuid, label_name),
    CONSTRAINT fk_mail_labels_user FOREIGN KEY (user_uuid) REFERENCES users (user_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_labels_user ON mail_labels(user_uuid);
