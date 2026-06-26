-- DB0008 §3 (007) draft.in_reply_to FK→mail add.
-- SQLitetext ALTER ADD CONSTRAINT translated text → translated text textcomposetext FKtext translated text.
-- text translated text draft text translated text translated text FKtext text text(attachmenttext 009) textcomposetext translated text.
CREATE TABLE draft_new (
    draft_id     TEXT NOT NULL PRIMARY KEY,
    user_id      TEXT NOT NULL,
    account_id   TEXT,
    in_reply_to  TEXT,
    reply_type   TEXT CHECK (reply_type IN ('reply','reply_all','forward')),
    to_addrs     TEXT NOT NULL DEFAULT '[]',
    cc_addrs     TEXT NOT NULL DEFAULT '[]',
    subject      TEXT DEFAULT '',
    body_format  TEXT NOT NULL DEFAULT 'text' CHECK (body_format IN ('text','html')),
    body_content TEXT DEFAULT '',
    updated_at   TEXT NOT NULL,
    FOREIGN KEY (user_id)     REFERENCES app_user(user_id)        ON DELETE CASCADE,
    FOREIGN KEY (account_id)  REFERENCES mail_account(account_id) ON DELETE SET NULL,
    FOREIGN KEY (in_reply_to) REFERENCES mail(mail_id)            ON DELETE SET NULL
);
INSERT INTO draft_new SELECT
    draft_id, user_id, account_id, in_reply_to, reply_type,
    to_addrs, cc_addrs, subject, body_format, body_content, updated_at
FROM draft;
DROP TABLE draft;
ALTER TABLE draft_new RENAME TO draft;
