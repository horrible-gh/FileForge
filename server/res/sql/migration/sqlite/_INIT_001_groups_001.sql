CREATE TABLE IF NOT EXISTS groups (
    group_uuid TEXT PRIMARY KEY
    , group_name TEXT NOT NULL
    , status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')) -- Status: active or inactive
    , creator_uuid TEXT DEFAULT NULL
    , created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid TEXT DEFAULT NULL
    , modified_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO groups(group_name) VALUES ('Anonymous group');
