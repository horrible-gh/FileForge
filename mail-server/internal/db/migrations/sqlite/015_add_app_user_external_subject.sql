-- mailanchor.ui.0003 T1 — FileForge text authentication text(RS256 token text).
-- FileForgetext issuetext tokentext subject(text user_id)text local app_usertext translated text translated text.
-- local text login translated text NULL(text text text). text provisioning translated text translated text.
ALTER TABLE app_user ADD COLUMN external_subject TEXT;
-- text text subjecttext text local accounttext translated text text text(NULLtext text translated text).
CREATE UNIQUE INDEX ux_app_user_external_subject
    ON app_user(external_subject) WHERE external_subject IS NOT NULL;
