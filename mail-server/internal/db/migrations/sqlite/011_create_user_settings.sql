-- DB0008 §2.10 user_settings — translated text 1text display·sync text
CREATE TABLE user_settings (
    user_id           TEXT NOT NULL PRIMARY KEY,        -- invariant 7 (translated text 0/1text)
    sort_order        TEXT NOT NULL DEFAULT 'date_desc' CHECK (sort_order IN ('date_desc','date_asc')),
    language          TEXT NOT NULL DEFAULT 'ko' CHECK (language IN ('ko','ja','en')),
    density           TEXT NOT NULL DEFAULT 'comfortable' CHECK (density IN ('comfortable','compact')),
    sync_interval_min INTEGER CHECK (sync_interval_min IS NULL OR sync_interval_min > 0),
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE
);
