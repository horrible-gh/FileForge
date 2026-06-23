-- DB0008 §2.6 mail_label — 메일 ↔ 라벨 N:M
CREATE TABLE mail_label (
    mail_id  TEXT NOT NULL,
    label_id TEXT NOT NULL,
    PRIMARY KEY (mail_id, label_id),                    -- 불변식 4 (중복 부착 방지)
    FOREIGN KEY (mail_id)  REFERENCES mail(mail_id)   ON DELETE CASCADE,
    FOREIGN KEY (label_id) REFERENCES label(label_id) ON DELETE CASCADE
);
