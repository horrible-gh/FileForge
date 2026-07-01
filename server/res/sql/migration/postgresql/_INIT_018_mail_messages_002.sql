-- R0001/0039 — unified-inbox pagination sort index (PostgreSQL).
-- See the SQLite copy for rationale: the list ends with
-- `ORDER BY m.is_pinned DESC, m.sent_date DESC LIMIT ? OFFSET ?` and had no index
-- covering the leading `is_pinned` sort key, forcing a full sort per page. This
-- composite index matches the ORDER BY so the planner can avoid the sort.
CREATE INDEX IF NOT EXISTS idx_msg_pinned_sent ON mail_messages(is_pinned, sent_date);
