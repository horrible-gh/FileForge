-- DB0008 §2.2 refresh_token — 발급/회전/폐기 기록 (access는 무상태라 미저장)
CREATE TABLE refresh_token (
    token_id     TEXT NOT NULL PRIMARY KEY,             -- rt_*
    user_id      TEXT NOT NULL,
    token_hash   TEXT NOT NULL UNIQUE,                  -- 원문 저장 금지 (불변식 9)
    issued_at    TEXT NOT NULL,
    expires_at   TEXT NOT NULL,
    revoked_at   TEXT,                                  -- NULL = 유효
    rotated_from TEXT,                                  -- 회전 체인 추적
    FOREIGN KEY (user_id)      REFERENCES app_user(user_id)        ON DELETE CASCADE,
    FOREIGN KEY (rotated_from) REFERENCES refresh_token(token_id)  ON DELETE SET NULL
);
