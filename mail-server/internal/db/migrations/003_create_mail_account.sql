-- DB0008 §2.3 mail_account — 연결된 외부 메일 계정 (P0007 Account DTO)
CREATE TABLE mail_account (
    account_id   TEXT NOT NULL PRIMARY KEY,             -- acc_*
    user_id      TEXT NOT NULL,
    email        TEXT NOT NULL,
    provider     TEXT NOT NULL CHECK (provider IN ('gmail','outlook','imap')),
    status       TEXT NOT NULL DEFAULT 'connected'
                 CHECK (status IN ('connected','reauth_required','error')),
    oauth_ref    TEXT,                                  -- 자격 원문은 비밀저장소
    connected_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES app_user(user_id) ON DELETE CASCADE,
    UNIQUE (user_id, email)                             -- 불변식 2
);
