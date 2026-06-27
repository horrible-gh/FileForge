CREATE TABLE groups (
    group_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY
    , group_name VARCHAR(255) NOT NULL
    , status ENUM('active', 'inactive') DEFAULT 'active' -- Status: active or inactive
    , creator_uuid VARCHAR(36) DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid VARCHAR(36) DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO groups(group_name) VALUES ('Anonymous group');
