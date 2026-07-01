-- R0001/0039 — unified-inbox pagination sort index (SQLite).
-- The list query (`inbox.get_integrated_mail1` + `get_integrated_mail2`) ends with
-- `ORDER BY m.is_pinned DESC, m.sent_date DESC LIMIT ? OFFSET ?`. The only prior
-- index on the sort columns was single-column `idx_msg_sent_date`, which cannot
-- satisfy the leading `is_pinned` key, so every page forced a full materialize +
-- filesort of the user's whole cross-account mailbox — the server side of the
-- "scroll refresh takes forever" complaint. This composite index matches the
-- ORDER BY exactly so the engine can read rows already ordered (scanning it
-- backwards for the DESC/DESC direction) and stop after LIMIT+OFFSET.
CREATE INDEX IF NOT EXISTS idx_msg_pinned_sent ON mail_messages(is_pinned, sent_date);
