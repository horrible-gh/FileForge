-- DB0008 §2.5 mail — 메일 한 통 (MailSummary/MailDetail 공통 본체)
CREATE TABLE mail (
    mail_id        TEXT NOT NULL PRIMARY KEY,           -- m_*
    user_id        TEXT NOT NULL,
    account_id     TEXT NOT NULL,
    thread_id      TEXT NOT NULL,                       -- 스레드 묶음 키(테이블 미신설)
    from_addr      TEXT NOT NULL,                       -- JSON {name,address}
    to_addrs       TEXT NOT NULL DEFAULT '[]',          -- JSON Address[]
    cc_addrs       TEXT NOT NULL DEFAULT '[]',
    subject        TEXT DEFAULT '',
    snippet        TEXT DEFAULT '',
    body_format    TEXT NOT NULL DEFAULT 'text' CHECK (body_format IN ('text','html')),
    body_content   TEXT DEFAULT '',                     -- 상세에서만 적재
    received_at    TEXT NOT NULL,
    is_read        INTEGER NOT NULL DEFAULT 0,          -- BOOLEAN 0/1
    has_attachment INTEGER NOT NULL DEFAULT 0,          -- 비정규화 캐시(불변식 8)
    direction      TEXT NOT NULL DEFAULT 'inbound' CHECK (direction IN ('inbound','outbound')),
    sent_at        TEXT,
    FOREIGN KEY (user_id)    REFERENCES app_user(user_id)        ON DELETE CASCADE,
    FOREIGN KEY (account_id) REFERENCES mail_account(account_id) ON DELETE CASCADE
);
