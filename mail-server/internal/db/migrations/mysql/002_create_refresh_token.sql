-- DB0008 §2.2 refresh_token — 발급/회전/폐기 기록 (access는 무상태라 미저장) [MySQL]
CREATE TABLE refresh_token (
    token_id     VARCHAR(64)  NOT NULL,                 -- rt_*
    user_id      VARCHAR(64)  NOT NULL,
    token_hash   VARCHAR(128) NOT NULL,                 -- 원문 저장 금지 (불변식 9)
    issued_at    VARCHAR(40)  NOT NULL,
    expires_at   VARCHAR(40)  NOT NULL,
    revoked_at   VARCHAR(40),                           -- NULL = 유효
    rotated_from VARCHAR(64),                           -- 회전 체인 추적
    PRIMARY KEY (token_id),
    UNIQUE KEY uq_refresh_token_hash (token_hash),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_refresh_rotated_from FOREIGN KEY (rotated_from)
        REFERENCES refresh_token(token_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
