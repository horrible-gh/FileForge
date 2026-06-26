-- DB0008 §2.1 app_user — authentication text (P0007 user DTO translated text)
CREATE TABLE app_user (
    user_id       TEXT NOT NULL PRIMARY KEY,           -- u_* translated text translated text
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,                        -- text save prohibited (invariant 9)
    display_name  TEXT,
    created_at    TEXT NOT NULL,                        -- ISO-8601 UTC
    updated_at    TEXT NOT NULL
);
