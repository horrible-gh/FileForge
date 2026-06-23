-- DB0008 §2.1 app_user — 인증 주체 (P0007 user DTO 영속체) [MySQL dialect]
-- 방언 메모: SQLite TEXT PK/UNIQUE → MySQL VARCHAR(인덱스/FK는 길이 필요).
CREATE TABLE app_user (
    user_id       VARCHAR(64)  NOT NULL,                -- u_* 불투명 식별자
    email         VARCHAR(320) NOT NULL,
    password_hash TEXT         NOT NULL,                -- 평문 저장 금지 (불변식 9)
    display_name  TEXT,
    created_at    VARCHAR(40)  NOT NULL,                -- ISO-8601 UTC
    updated_at    VARCHAR(40)  NOT NULL,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_app_user_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
