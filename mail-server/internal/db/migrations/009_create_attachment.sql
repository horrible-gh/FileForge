-- DB0008 §2.7 attachment — 첨부 메타(바이트는 오브젝트 스토어). 메일 또는 초안에 배타 귀속.
CREATE TABLE attachment (
    attachment_id TEXT NOT NULL PRIMARY KEY,            -- a_*
    mail_id       TEXT,
    draft_id      TEXT,
    filename      TEXT NOT NULL,
    size_bytes    INTEGER NOT NULL CHECK (size_bytes >= 0),
    content_type  TEXT NOT NULL,
    storage_ref   TEXT NOT NULL,                        -- 오브젝트 스토어 키
    created_at    TEXT NOT NULL,
    FOREIGN KEY (mail_id)  REFERENCES mail(mail_id)   ON DELETE CASCADE,
    FOREIGN KEY (draft_id) REFERENCES draft(draft_id) ON DELETE CASCADE,
    -- 불변식 5: 정확히 한쪽에만 귀속(배타적)
    CHECK ((mail_id IS NOT NULL) <> (draft_id IS NOT NULL))
);
