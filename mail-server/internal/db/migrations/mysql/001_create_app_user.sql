-- DB0008 §2.1 app_user — authentication text (P0007 user DTO translated text) [MySQL dialect]
-- dialect note: SQLite TEXT PK/UNIQUE → MySQL VARCHAR(translated text/FKtext text text).
CREATE TABLE app_user (
    user_id       VARCHAR(64)  NOT NULL,                -- u_* translated text translated text
    email         VARCHAR(320) NOT NULL,
    password_hash TEXT         NOT NULL,                -- text save prohibited (invariant 9)
    display_name  TEXT,
    created_at    VARCHAR(40)  NOT NULL,                -- ISO-8601 UTC
    updated_at    VARCHAR(40)  NOT NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_app_user_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
