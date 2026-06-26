-- NR0003 §5.E text: sync(F)text mail.find_by_external_ref(account_id, external_id)text
-- core translated text text. external_ref text+translated text translated text add. [MySQL]
-- dialect note: MySQL UNIQUE translated text NULL text text text translated text translated text,
-- SQLitetext `WHERE external_ref IS NOT NULL` textminutes translated text translated text translated text
-- (NULL=local outbound text allowed, text-NULLtext accounttext translated text).
ALTER TABLE mail ADD COLUMN external_ref VARCHAR(255);
CREATE UNIQUE INDEX ix_mail_external_ref ON mail(account_id, external_ref);
