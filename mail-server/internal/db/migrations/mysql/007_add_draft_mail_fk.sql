-- DB0008 §3 (007) draft.in_reply_to FK→mail 추가. [MySQL]
-- SQLite는 테이블 재작성이 필요했지만 MySQL/InnoDB는 ALTER ADD CONSTRAINT 를 직접 지원한다.
ALTER TABLE draft
    ADD CONSTRAINT fk_draft_in_reply_to FOREIGN KEY (in_reply_to)
        REFERENCES mail(mail_id) ON DELETE SET NULL;
