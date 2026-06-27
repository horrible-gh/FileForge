-- 동기화 로그 (디버깅/모니터링용)
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
    
    INDEX idx_account_uuid (account_uuid),
    INDEX idx_started_at (started_at)
);