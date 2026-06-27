CREATE TABLE users (
    user_id TEXT PRIMARY KEY,                            -- Unique identifier for the user
    name TEXT NOT NULL,                                  -- Name of the user
    password TEXT NOT NULL,
    email TEXT,
    role TEXT CHECK (role IN ('admin', 'user')) DEFAULT 'user', -- Role: admin or user
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP        -- Account creation timestamp
);
