-- DB0008 §2.8 draft — compose text translated text Draft
-- in_reply_to FKtext mail(006) text 007text translated text(005↔006 text text).
CREATE TABLE draft (
    draft_id     TEXT NOT NULL PRIMARY KEY,             -- d_*
    user_id      TEXT NOT NULL,
    account_id   TEXT,
    in_reply_to  TEXT,                                  -- FK→mail text 007text add
    reply_type   TEXT CHECK (reply_type IN ('reply','reply_all','forward')),
    to_addrs     TEXT NOT NULL DEFAULT '[]',            -- JSON Address[]
    cc_addrs     TEXT NOT NULL DEFAULT '[]',
    subject      TEXT DEFAULT '',
    body_format  TEXT NOT NULL DEFAULT 'text' CHECK (body_format IN ('text','html')),
    body_content TEXT DEFAULT '',
    updated_at   TEXT NOT NULL,                         -- translated text text text(base_updated_at)
    FOREIGN KEY (user_id)    REFERENCES app_user(user_id)         ON DELETE CASCADE,
    FOREIGN KEY (account_id) REFERENCES mail_account(account_id)  ON DELETE SET NULL
);
