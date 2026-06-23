-- DB0008 §2.9 sync_state — 계정당 1행 동기화 상태·커서 [MySQL]
CREATE TABLE sync_state (
    account_id     VARCHAR(64) NOT NULL,                -- 불변식 6 (계정당 0/1행)
    state          VARCHAR(16) NOT NULL DEFAULT 'idle',
    last_synced_at VARCHAR(40),
    sync_cursor    TEXT,                                -- 외부 증분 커서(불투명)
    last_error     TEXT,
    PRIMARY KEY (account_id),
    CONSTRAINT fk_sync_state_account FOREIGN KEY (account_id)
        REFERENCES mail_account(account_id) ON DELETE CASCADE,
    CONSTRAINT ck_sync_state_state CHECK (state IN ('idle','syncing','error'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
