-- Mail subsystem: sync logs (PostgreSQL).
CREATE TABLE sync_logs (
    log_uuid VARCHAR(36) DEFAULT gen_random_uuid()::varchar PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,
    sync_type VARCHAR(12) NOT NULL DEFAULT 'incremental' CHECK (sync_type IN ('full','incremental','manual')),
    status VARCHAR(10) NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','failed')),
    messages_fetched INTEGER DEFAULT 0,
    messages_updated INTEGER DEFAULT 0,
    error_message TEXT DEFAULT NULL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP DEFAULT NULL,
    CONSTRAINT fk_sync_logs_account FOREIGN KEY (account_uuid) REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_synclog_account ON sync_logs(account_uuid);
CREATE INDEX idx_synclog_started ON sync_logs(started_at);
