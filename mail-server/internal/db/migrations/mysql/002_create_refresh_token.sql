-- DB0008 §2.2 refresh_token — issue/text/text text (accesstext textstatetext textsave) [MySQL]
CREATE TABLE refresh_token (
    token_id     VARCHAR(64)  NOT NULL,                 -- rt_*
    user_id      VARCHAR(64)  NOT NULL,
    token_hash   VARCHAR(128) NOT NULL,                 -- text save prohibited (invariant 9)
    issued_at    VARCHAR(40)  NOT NULL,
    expires_at   VARCHAR(40)  NOT NULL,
    revoked_at   VARCHAR(40),                           -- NULL = text
    rotated_from VARCHAR(64),                           -- text text text
    PRIMARY KEY (token_id),
    UNIQUE KEY uq_refresh_token_hash (token_hash),
    CONSTRAINT fk_refresh_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_refresh_rotated_from FOREIGN KEY (rotated_from)
        REFERENCES refresh_token(token_id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
