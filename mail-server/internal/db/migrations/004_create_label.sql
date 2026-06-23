-- DB0008 §2.4 label — 메일 분류 라벨 (system/user)
CREATE TABLE label (
    label_id   TEXT NOT NULL PRIMARY KEY,               -- lbl_* 또는 시스템 고정키
    user_id    TEXT NOT NULL,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL DEFAULT 'user' CHECK (type IN ('system','user')),
    color      TEXT,                                    -- #RRGGBB
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE,
    UNIQUE (user_id, name)                              -- 불변식 3 (LABEL_DUPLICATE 409)
);
