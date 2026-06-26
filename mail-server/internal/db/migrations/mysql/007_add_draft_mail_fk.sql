-- DB0008 §3 (007) draft.in_reply_to FK→mail add. [MySQL]
-- SQLitetext translated text textcomposetext translated text MySQL/InnoDBtext ALTER ADD CONSTRAINT text text translated text.
ALTER TABLE draft
    ADD CONSTRAINT fk_draft_in_reply_to FOREIGN KEY (in_reply_to)
        REFERENCES mail(mail_id) ON DELETE SET NULL;
