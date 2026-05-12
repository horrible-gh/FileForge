-- User Management
CREATE TABLE IF NOT EXISTS users (
    group_uuid TEXT DEFAULT NULL,
    user_uuid TEXT PRIMARY KEY,
    user_id TEXT UNIQUE NOT NULL,     -- Unique identifier for the user
    user_name TEXT NOT NULL,          -- Name of the user
    password TEXT NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'user' CHECK (role IN ('admin', 'user')),  -- Role: admin or user
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP, -- Account creation timestamp
    modified_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (group_uuid, user_id, user_name, password, role) VALUES (
    (SELECT group_uuid FROM groups WHERE group_name = 'Anonymous group'),
    'fileforge',
    'fileforge',
    '$pbkdf2-sha256$29000$ea9VCiEEwPi/9/7fu7eW8g$WAsVC6oK2rzt3WrkIzInnSCOj0ezNB52z0MGLpfUntQ',
    'admin'
);
