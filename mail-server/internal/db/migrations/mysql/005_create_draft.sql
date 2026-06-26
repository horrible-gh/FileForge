-- DB0008 §2.8 draft — compose text translated text Draft [MySQL]
-- in_reply_to FKtext mail(006) text 007text translated text(005↔006 text text).
-- TEXT text DEFAULTtext MySQL 8.0.13+ text(expression) default value `DEFAULT ('...')` text.
CREATE TABLE draft (
    draft_id     VARCHAR(64) NOT NULL,                  -- d_*
    user_id      VARCHAR(64) NOT NULL,
    account_id   VARCHAR(64),
    in_reply_to  VARCHAR(64),                           -- FK→mail text 007text add
    reply_type   VARCHAR(16),
    to_addrs     TEXT NOT NULL DEFAULT ('[]'),          -- JSON Address[]
    cc_addrs     TEXT NOT NULL DEFAULT ('[]'),
    subject      TEXT DEFAULT (''),
    body_format  VARCHAR(8)  NOT NULL DEFAULT 'text',
    body_content TEXT DEFAULT (''),
    updated_at   VARCHAR(40) NOT NULL,                  -- translated text text text(base_updated_at)
    PRIMARY KEY (draft_id),
    CONSTRAINT fk_draft_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_draft_account FOREIGN KEY (account_id)
        REFERENCES mail_account(account_id) ON DELETE SET NULL,
    CONSTRAINT ck_draft_reply_type  CHECK (reply_type IS NULL OR reply_type IN ('reply','reply_all','forward')),
    CONSTRAINT ck_draft_body_format CHECK (body_format IN ('text','html'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
