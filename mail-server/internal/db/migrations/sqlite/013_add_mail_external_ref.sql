-- NR0003 §5.E text: L0013 synctext mail.find_by_external_ref(account_id, external_id)text
-- core translated text translated text DB0008text external_ref translated text translated text(DB0008 DEFERRED).
-- sync(F) text translated text text text translated text text+translated text translated text addtext.
ALTER TABLE mail ADD COLUMN external_ref TEXT;          -- text translated text translated text(provider issue)
-- account text text external_ref text text text(text echo merge). NULL(local outbound)text translated text text translated text.
CREATE UNIQUE INDEX ix_mail_external_ref ON mail(account_id, external_ref) WHERE external_ref IS NOT NULL;
