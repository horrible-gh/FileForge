-- mailanchor.ui.0003 T1 — FileForge text authentication text(RS256 token text). [MySQL]
-- FileForge tokentext subject(text user_id)text local app_user text text translated text.
-- local text login translated text NULL(text text text).
-- dialect note: MySQL UNIQUE translated text NULL translated text allowedtranslated text SQLitetext
-- `WHERE external_subject IS NOT NULL` textminutes translated text text translated text.
ALTER TABLE app_user ADD COLUMN external_subject VARCHAR(255);
CREATE UNIQUE INDEX ux_app_user_external_subject ON app_user(external_subject);
