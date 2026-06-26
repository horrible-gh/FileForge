-- DB0008 §2.11 translated text (translated text §4) [MySQL]
-- dialect note: MySQLtext textminutes(filtered) translated text translated text translated text SQLitetext
-- `WHERE ...` text translated text text translated text translated text(text text, sizetext text text).
-- DESC translated text MySQL 8.0+ text translated text.
CREATE INDEX ix_mail_list        ON mail(user_id, account_id, received_at DESC);
CREATE INDEX ix_mail_thread      ON mail(thread_id);
CREATE INDEX ix_mail_unread      ON mail(user_id, is_read);
CREATE INDEX ix_label_user       ON label(user_id);
CREATE INDEX ix_mail_label_label ON mail_label(label_id);
CREATE INDEX ix_attachment_mail  ON attachment(mail_id);
CREATE INDEX ix_draft_user       ON draft(user_id, updated_at DESC);
CREATE INDEX ix_refresh_user     ON refresh_token(user_id);
