-- DB0008 §2.6 mail_label — text ↔ text N:M
CREATE TABLE mail_label (
    mail_id  TEXT NOT NULL,
    label_id TEXT NOT NULL,
    PRIMARY KEY (mail_id, label_id),                    -- invariant 4 (text text text)
    FOREIGN KEY (mail_id)  REFERENCES mail(mail_id)   ON DELETE CASCADE,
    FOREIGN KEY (label_id) REFERENCES label(label_id) ON DELETE CASCADE
);
