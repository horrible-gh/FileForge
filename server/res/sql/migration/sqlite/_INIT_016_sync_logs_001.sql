-- Mail subsystem: sync logs (SQLite).
CREATE TABLE IF NOT EXISTS sync_logs (
    log_uuid TEXT PRIMARY KEY,
    account_uuid TEXT NOT NULL,
    sync_type TEXT NOT NULL DEFAULT 'incremental' CHECK (sync_type IN ('full','incremental','manual')),
    status TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','failed')),
    messages_fetched INTEGER DEFAULT 0,
    messages_updated INTEGER DEFAULT 0,
    error_message TEXT DEFAULT NULL,
    started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    completed_at DATETIME DEFAULT NULL,
    FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_synclog_account ON sync_logs(account_uuid);
CREATE INDEX IF NOT EXISTS idx_synclog_started ON sync_logs(started_at);
