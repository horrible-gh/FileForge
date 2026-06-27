BEGIN TRANSACTION;

CREATE TABLE users_new (
    group_id INTEGER DEFAULT 0,
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    password TEXT NOT NULL,
    email TEXT,
    role TEXT CHECK (role IN ('admin', 'user')) DEFAULT 'user',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users_new (group_id, user_id, name, password, email, role, created_at)
SELECT 0, user_id, name, password, email, role, created_at FROM users;

DROP TABLE users;
ALTER TABLE users_new RENAME TO users;

COMMIT;
