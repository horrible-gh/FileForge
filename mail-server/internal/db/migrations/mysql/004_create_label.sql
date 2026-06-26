-- DB0008 §2.4 label — text minutestext text (system/user) [MySQL]
CREATE TABLE label (
    label_id   VARCHAR(64)  NOT NULL,                   -- lbl_* text translated text translated text
    user_id    VARCHAR(64)  NOT NULL,
    name       VARCHAR(255) NOT NULL,
    type       VARCHAR(16)  NOT NULL DEFAULT 'user',
    color      VARCHAR(16),                             -- #RRGGBB
    created_at VARCHAR(40)  NOT NULL,
    PRIMARY KEY (label_id),
    UNIQUE KEY uq_label_user_name (user_id, name),      -- invariant 3 (LABEL_DUPLICATE 409)
    CONSTRAINT fk_label_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT ck_label_type CHECK (type IN ('system','user'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
