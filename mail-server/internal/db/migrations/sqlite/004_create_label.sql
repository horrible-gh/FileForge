-- DB0008 §2.4 label — text minutestext text (system/user)
CREATE TABLE label (
    label_id   TEXT NOT NULL PRIMARY KEY,               -- lbl_* text translated text translated text
    user_id    TEXT NOT NULL,
    name       TEXT NOT NULL,
    type       TEXT NOT NULL DEFAULT 'user' CHECK (type IN ('system','user')),
    color      TEXT,                                    -- #RRGGBB
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE,
    UNIQUE (user_id, name)                              -- invariant 3 (LABEL_DUPLICATE 409)
);
