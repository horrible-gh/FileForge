-- DB0008 §2.11 인덱스 (핫패스 §4)
CREATE INDEX ix_mail_list        ON mail(user_id, account_id, received_at DESC);
CREATE INDEX ix_mail_thread      ON mail(thread_id);
CREATE INDEX ix_mail_unread      ON mail(user_id, is_read) WHERE is_read = 0;        -- 부분 인덱스
CREATE INDEX ix_label_user       ON label(user_id);
CREATE INDEX ix_mail_label_label ON mail_label(label_id);
CREATE INDEX ix_attachment_mail  ON attachment(mail_id);
CREATE INDEX ix_draft_user       ON draft(user_id, updated_at DESC);
CREATE INDEX ix_refresh_user     ON refresh_token(user_id) WHERE revoked_at IS NULL; -- 부분 인덱스
