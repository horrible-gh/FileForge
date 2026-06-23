-- DB0008 §2.6 mail_label — 메일 ↔ 라벨 N:M [MySQL]
CREATE TABLE mail_label (
    mail_id  VARCHAR(64) NOT NULL,
    label_id VARCHAR(64) NOT NULL,
    PRIMARY KEY (mail_id, label_id),                    -- 불변식 4 (중복 부착 방지)
    CONSTRAINT fk_mail_label_mail  FOREIGN KEY (mail_id)
        REFERENCES mail(mail_id)   ON DELETE CASCADE,
    CONSTRAINT fk_mail_label_label FOREIGN KEY (label_id)
        REFERENCES label(label_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
