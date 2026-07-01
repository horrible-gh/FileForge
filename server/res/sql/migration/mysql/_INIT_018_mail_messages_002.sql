-- R0001/0039 — unified-inbox pagination sort index (MySQL).
-- See the SQLite copy for rationale: the list ends with
-- `ORDER BY m.is_pinned DESC, m.sent_date DESC LIMIT ? OFFSET ?` and had no index
-- covering the leading `is_pinned` sort key, forcing a filesort per page. This
-- composite index matches the ORDER BY so InnoDB can read rows in order (scanning
-- the index backwards for the DESC direction) and avoid the sort.
-- MySQL has no `CREATE INDEX ... IF NOT EXISTS`; the sqloader migrator records
-- applied filenames and runs each migration exactly once, so a plain CREATE is safe.
CREATE INDEX idx_msg_pinned_sent ON mail_messages (is_pinned, sent_date);
