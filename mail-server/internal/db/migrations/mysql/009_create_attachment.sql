-- DB0008 §2.7 attachment — 첨부 메타(바이트는 오브젝트 스토어). 메일/초안 배타 귀속. [MySQL]
CREATE TABLE attachment (
    attachment_id VARCHAR(64)  NOT NULL,                -- a_*
    mail_id       VARCHAR(64),
    draft_id      VARCHAR(64),
    filename      TEXT         NOT NULL,
    size_bytes    BIGINT       NOT NULL,
    content_type  VARCHAR(255) NOT NULL,
    storage_ref   VARCHAR(512) NOT NULL,                -- 오브젝트 스토어 키
    created_at    VARCHAR(40)  NOT NULL,
    PRIMARY KEY (attachment_id),
    CONSTRAINT fk_attachment_mail  FOREIGN KEY (mail_id)
        REFERENCES mail(mail_id)   ON DELETE CASCADE,
    CONSTRAINT fk_attachment_draft FOREIGN KEY (draft_id)
        REFERENCES draft(draft_id) ON DELETE CASCADE,
    CONSTRAINT ck_attachment_size CHECK (size_bytes >= 0),
    -- 불변식 5: 정확히 한쪽에만 귀속(배타적)
    CONSTRAINT ck_attachment_owner CHECK ((mail_id IS NOT NULL) <> (draft_id IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
