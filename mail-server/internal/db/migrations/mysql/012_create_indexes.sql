-- DB0008 §2.11 인덱스 (핫패스 §4) [MySQL]
-- 방언 메모: MySQL은 부분(filtered) 인덱스를 지원하지 않으므로 SQLite의
-- `WHERE ...` 절을 제거하고 전체 인덱스로 만든다(동작 동등, 크기만 약간 큼).
-- DESC 인덱스는 MySQL 8.0+ 에서 유효하다.
CREATE INDEX ix_mail_list        ON mail(user_id, account_id, received_at DESC);
CREATE INDEX ix_mail_thread      ON mail(thread_id);
CREATE INDEX ix_mail_unread      ON mail(user_id, is_read);
CREATE INDEX ix_label_user       ON label(user_id);
CREATE INDEX ix_mail_label_label ON mail_label(label_id);
CREATE INDEX ix_attachment_mail  ON attachment(mail_id);
CREATE INDEX ix_draft_user       ON draft(user_id, updated_at DESC);
CREATE INDEX ix_refresh_user     ON refresh_token(user_id);
