-- 메일-라벨 연결
CREATE TABLE mail_message_labels (
    message_uuid VARCHAR(36) NOT NULL,
    label_uuid VARCHAR(36) NOT NULL,
    
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    
    PRIMARY KEY (message_uuid, label_uuid)
);