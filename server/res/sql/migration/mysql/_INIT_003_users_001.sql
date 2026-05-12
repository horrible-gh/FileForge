-- User Management
CREATE TABLE users (
    group_uuid VARCHAR(36) DEFAULT NULL,
    user_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    user_id VARCHAR(50) UNIQUE NOT NULL,     -- Unique identifier for the user
    user_name VARCHAR(255) NOT NULL,                 -- Name of the user
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100),
    role ENUM('admin', 'user') DEFAULT 'user',  -- Role: admin or user
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP, -- Account creation timestamp
    modified_at  DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

INSERT INTO users (group_uuid, user_id, user_name, password, role) VALUES (
    (SELECT group_uuid FROM groups WHERE group_name = 'Anonymous group'),
    'fileforge',
    'fileforge',
    '$pbkdf2-sha256$29000$ea9VCiEEwPi/9/7fu7eW8g$WAsVC6oK2rzt3WrkIzInnSCOj0ezNB52z0MGLpfUntQ',
    'admin'
);
