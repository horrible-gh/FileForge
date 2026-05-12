CREATE TABLE groups (
    group_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY
    , group_name VARCHAR(255) NOT NULL
    , status VARCHAR(8) DEFAULT 'active' CHECK (status IN ('active', 'inactive')) -- Status: active or inactive
    , creator_uuid VARCHAR(36) DEFAULT NULL
    , created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL
    , modifier_uuid VARCHAR(36) DEFAULT NULL
    , modified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO groups(group_name) VALUES ('Anonymous group');
