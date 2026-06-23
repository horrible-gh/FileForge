-- DB0008 §2.8 draft — 작성 중 임시보관 초안
-- in_reply_to FK는 mail(006) 이후 007에서 덧붙인다(005↔006 순환 회피).
CREATE TABLE draft (
    draft_id     TEXT NOT NULL PRIMARY KEY,             -- d_*
    user_id      TEXT NOT NULL,
    account_id   TEXT,
    in_reply_to  TEXT,                                  -- FK→mail 은 007에서 추가
    reply_type   TEXT CHECK (reply_type IN ('reply','reply_all','forward')),
    to_addrs     TEXT NOT NULL DEFAULT '[]',            -- JSON Address[]
    cc_addrs     TEXT NOT NULL DEFAULT '[]',
    subject      TEXT DEFAULT '',
    body_format  TEXT NOT NULL DEFAULT 'text' CHECK (body_format IN ('text','html')),
    body_content TEXT DEFAULT '',
    updated_at   TEXT NOT NULL,                         -- 낙관적 경합 기준(base_updated_at)
    FOREIGN KEY (user_id)    REFERENCES app_user(user_id)         ON DELETE CASCADE,
    FOREIGN KEY (account_id) REFERENCES mail_account(account_id)  ON DELETE SET NULL
);
