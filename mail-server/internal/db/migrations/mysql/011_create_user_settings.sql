-- DB0008 §2.10 user_settings — translated text 1text display·sync text [MySQL]
CREATE TABLE user_settings (
    user_id           VARCHAR(64) NOT NULL,             -- invariant 7 (translated text 0/1text)
    sort_order        VARCHAR(16) NOT NULL DEFAULT 'date_desc',
    language          VARCHAR(8)  NOT NULL DEFAULT 'ko',
    density           VARCHAR(16) NOT NULL DEFAULT 'comfortable',
    sync_interval_min INT,
    PRIMARY KEY (user_id),
    CONSTRAINT fk_user_settings_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT ck_user_settings_sort     CHECK (sort_order IN ('date_desc','date_asc')),
    CONSTRAINT ck_user_settings_language CHECK (language IN ('ko','ja','en')),
    CONSTRAINT ck_user_settings_density  CHECK (density IN ('comfortable','compact')),
    CONSTRAINT ck_user_settings_interval CHECK (sync_interval_min IS NULL OR sync_interval_min > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
