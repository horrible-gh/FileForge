-- DB0008 §2.5 mail — text text text (MailSummary/MailDetail text text) [MySQL]
CREATE TABLE mail (
    mail_id        VARCHAR(64)  NOT NULL,               -- m_*
    user_id        VARCHAR(64)  NOT NULL,
    account_id     VARCHAR(64)  NOT NULL,
    thread_id      VARCHAR(255) NOT NULL,               -- translated text text text(translated text translated text)
    from_addr      TEXT         NOT NULL,               -- JSON {name,address}
    to_addrs       TEXT         NOT NULL DEFAULT ('[]'),-- JSON Address[]
    cc_addrs       TEXT         NOT NULL DEFAULT ('[]'),
    subject        TEXT         DEFAULT (''),
    snippet        TEXT         DEFAULT (''),
    body_format    VARCHAR(8)   NOT NULL DEFAULT 'text',
    body_content   TEXT         DEFAULT (''),           -- translated text text
    received_at    VARCHAR(40)  NOT NULL,
    is_read        TINYINT(1)   NOT NULL DEFAULT 0,     -- BOOLEAN 0/1
    has_attachment TINYINT(1)   NOT NULL DEFAULT 0,     -- textnormalization text(invariant 8)
    direction      VARCHAR(8)   NOT NULL DEFAULT 'inbound',
    sent_at        VARCHAR(40),
    PRIMARY KEY (mail_id),
    CONSTRAINT fk_mail_user FOREIGN KEY (user_id)
        REFERENCES app_user(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_mail_account FOREIGN KEY (account_id)
        REFERENCES mail_account(account_id) ON DELETE CASCADE,
    CONSTRAINT ck_mail_body_format CHECK (body_format IN ('text','html')),
    CONSTRAINT ck_mail_direction   CHECK (direction IN ('inbound','outbound'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
