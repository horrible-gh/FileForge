-- DB0008 §2.7 attachment — text text(bytestext translated text translated text). text text Drafttext text text.
CREATE TABLE attachment (
    attachment_id TEXT NOT NULL PRIMARY KEY,            -- a_*
    mail_id       TEXT,
    draft_id      TEXT,
    filename      TEXT NOT NULL,
    size_bytes    INTEGER NOT NULL CHECK (size_bytes >= 0),
    content_type  TEXT NOT NULL,
    storage_ref   TEXT NOT NULL,                        -- translated text translated text text
    created_at    TEXT NOT NULL,
    FOREIGN KEY (mail_id)  REFERENCES mail(mail_id)   ON DELETE CASCADE,
    FOREIGN KEY (draft_id) REFERENCES draft(draft_id) ON DELETE CASCADE,
    -- invariant 5: translated text translated text text(translated text)
    CHECK ((mail_id IS NOT NULL) <> (draft_id IS NOT NULL))
);
