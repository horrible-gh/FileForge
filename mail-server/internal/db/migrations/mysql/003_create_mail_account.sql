-- DB0008 §2.3 mail_account — translated text text text account (P0007 Account DTO) [MySQL]
CREATE TABLE mail_account (
    account_id   VARCHAR(64)  NOT NULL,                 -- acc_*
    user_id      VARCHAR(64)  NOT NULL,
    email        VARCHAR(320) NOT NULL,
    provider     VARCHAR(16)  NOT NULL,
    status       VARCHAR(16)  NOT NULL DEFAULT 'connected',
    oauth_ref    TEXT,                                  -- raw credentials live in secret storage
    connected_at VARCHAR(40)  NOT NULL,
    PRIMARY KEY (account_id),
    UNIQUE KEY uq_mail_account_user_email (user_id, email),   -- invariant 2
    CONSTRAINT fk_mail_account_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT ck_mail_account_provider CHECK (provider IN ('gmail','outlook','imap')),
    CONSTRAINT ck_mail_account_status   CHECK (status IN ('connected','reauth_required','error'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
