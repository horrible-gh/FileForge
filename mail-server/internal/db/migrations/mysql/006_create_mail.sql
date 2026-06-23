-- DB0008 §2.5 mail — 메일 한 통 (MailSummary/MailDetail 공통 본체) [MySQL]
CREATE TABLE mail (
    mail_id        VARCHAR(64)  NOT NULL,               -- m_*
    user_id        VARCHAR(64)  NOT NULL,
    account_id     VARCHAR(64)  NOT NULL,
    thread_id      VARCHAR(255) NOT NULL,               -- 스레드 묶음 키(테이블 미신설)
    from_addr      TEXT         NOT NULL,               -- JSON {name,address}
    to_addrs       TEXT         NOT NULL DEFAULT ('[]'),-- JSON Address[]
    cc_addrs       TEXT         NOT NULL DEFAULT ('[]'),
    subject        TEXT         DEFAULT (''),
    snippet        TEXT         DEFAULT (''),
    body_format    VARCHAR(8)   NOT NULL DEFAULT 'text',
    body_content   TEXT         DEFAULT (''),           -- 상세에서만 적재
    received_at    VARCHAR(40)  NOT NULL,
    is_read        TINYINT(1)   NOT NULL DEFAULT 0,     -- BOOLEAN 0/1
    has_attachment TINYINT(1)   NOT NULL DEFAULT 0,     -- 비정규화 캐시(불변식 8)
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
