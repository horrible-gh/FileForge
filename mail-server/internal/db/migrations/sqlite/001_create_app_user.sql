-- DB0008 §2.1 app_user — 인증 주체 (P0007 user DTO 영속체)
CREATE TABLE app_user (
    user_id       TEXT NOT NULL PRIMARY KEY,           -- u_* 불투명 식별자
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,                        -- 평문 저장 금지 (불변식 9)
    display_name  TEXT,
    created_at    TEXT NOT NULL,                        -- ISO-8601 UTC
    updated_at    TEXT NOT NULL
);
