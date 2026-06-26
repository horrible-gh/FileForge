-- DB0008 §2.2 refresh_token — issue/text/text text (accesstext textstatetext textsave)
CREATE TABLE refresh_token (
    token_id     TEXT NOT NULL PRIMARY KEY,             -- rt_*
    user_id      TEXT NOT NULL,
    token_hash   TEXT NOT NULL UNIQUE,                  -- text save prohibited (invariant 9)
    issued_at    TEXT NOT NULL,
    expires_at   TEXT NOT NULL,
    revoked_at   TEXT,                                  -- NULL = text
    rotated_from TEXT,                                  -- text text text
    FOREIGN KEY (user_id)      REFERENCES app_user(user_id)        ON DELETE CASCADE,
    FOREIGN KEY (rotated_from) REFERENCES refresh_token(token_id)  ON DELETE SET NULL
);
