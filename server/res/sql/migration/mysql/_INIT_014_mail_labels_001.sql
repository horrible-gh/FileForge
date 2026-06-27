-- Mail subsystem: labels. FK -> users ON DELETE CASCADE. UNIQUE(user,name).
CREATE TABLE mail_labels (
    label_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,

    label_name VARCHAR(100) NOT NULL,
    label_color VARCHAR(7) DEFAULT '#4a6cf7',
    display_order INT DEFAULT 0,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY unique_label (user_uuid, label_name),
    INDEX idx_labels_user (user_uuid),
    CONSTRAINT fk_mail_labels_user FOREIGN KEY (user_uuid)
        REFERENCES users (user_uuid) ON DELETE CASCADE
);
