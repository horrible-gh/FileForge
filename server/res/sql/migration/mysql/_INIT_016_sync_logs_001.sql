-- Mail subsystem: sync logs (monitoring). FK -> mail_accounts ON DELETE CASCADE.
CREATE TABLE sync_logs (
    log_uuid VARCHAR(36) DEFAULT (UUID()) PRIMARY KEY,
    account_uuid VARCHAR(36) NOT NULL,

    sync_type ENUM('full', 'incremental', 'manual') DEFAULT 'incremental',
    status ENUM('started', 'completed', 'failed') DEFAULT 'started',

    messages_fetched INT DEFAULT 0,
    messages_updated INT DEFAULT 0,
    error_message TEXT DEFAULT NULL,

    started_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
    completed_at DATETIME DEFAULT NULL,

    INDEX idx_synclog_account (account_uuid),
    INDEX idx_synclog_started (started_at),
    CONSTRAINT fk_sync_logs_account FOREIGN KEY (account_uuid)
        REFERENCES mail_accounts (account_uuid) ON DELETE CASCADE
);
