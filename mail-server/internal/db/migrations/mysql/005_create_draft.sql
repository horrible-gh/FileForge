-- DB0008 §2.8 draft — 작성 중 임시보관 초안 [MySQL]
-- in_reply_to FK는 mail(006) 이후 007에서 덧붙인다(005↔006 순환 회피).
-- TEXT 컬럼 DEFAULT는 MySQL 8.0.13+ 식(expression) 기본값 `DEFAULT ('...')` 사용.
CREATE TABLE draft (
    draft_id     VARCHAR(64) NOT NULL,                  -- d_*
    user_id      VARCHAR(64) NOT NULL,
    account_id   VARCHAR(64),
    in_reply_to  VARCHAR(64),                           -- FK→mail 은 007에서 추가
    reply_type   VARCHAR(16),
    to_addrs     TEXT NOT NULL DEFAULT ('[]'),          -- JSON Address[]
    cc_addrs     TEXT NOT NULL DEFAULT ('[]'),
    subject      TEXT DEFAULT (''),
    body_format  VARCHAR(8)  NOT NULL DEFAULT 'text',
    body_content TEXT DEFAULT (''),
    updated_at   VARCHAR(40) NOT NULL,                  -- 낙관적 경합 기준(base_updated_at)
    PRIMARY KEY (draft_id),
    CONSTRAINT fk_draft_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_draft_account FOREIGN KEY (account_id)
        REFERENCES mail_account(account_id) ON DELETE SET NULL,
    CONSTRAINT ck_draft_reply_type  CHECK (reply_type IS NULL OR reply_type IN ('reply','reply_all','forward')),
    CONSTRAINT ck_draft_body_format CHECK (body_format IN ('text','html'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
