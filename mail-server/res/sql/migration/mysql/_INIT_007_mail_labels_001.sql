-- 라벨/태그
CREATE TABLE mail_labels (
    label_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    user_uuid VARCHAR(36) NOT NULL,
    
    label_name VARCHAR(100) NOT NULL,
    label_color VARCHAR(7) DEFAULT '#4a6cf7',
    display_order INT DEFAULT 0,
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY unique_label (user_uuid, label_name),
    INDEX idx_user_uuid (user_uuid)
);