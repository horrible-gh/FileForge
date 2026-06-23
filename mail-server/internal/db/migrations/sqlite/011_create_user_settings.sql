-- DB0008 §2.10 user_settings — 사용자당 1행 표시·동기화 설정
CREATE TABLE user_settings (
    user_id           TEXT NOT NULL PRIMARY KEY,        -- 불변식 7 (사용자당 0/1행)
    sort_order        TEXT NOT NULL DEFAULT 'date_desc' CHECK (sort_order IN ('date_desc','date_asc')),
    language          TEXT NOT NULL DEFAULT 'ko' CHECK (language IN ('ko','ja','en')),
    density           TEXT NOT NULL DEFAULT 'comfortable' CHECK (density IN ('comfortable','compact')),
    sync_interval_min INTEGER CHECK (sync_interval_min IS NULL OR sync_interval_min > 0),
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE
);
