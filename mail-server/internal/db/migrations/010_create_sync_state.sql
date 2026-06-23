-- DB0008 §2.9 sync_state — 계정당 1행 동기화 상태·커서
CREATE TABLE sync_state (
    account_id     TEXT NOT NULL PRIMARY KEY,           -- 불변식 6 (계정당 0/1행)
    state          TEXT NOT NULL DEFAULT 'idle' CHECK (state IN ('idle','syncing','error')),
    last_synced_at TEXT,
    sync_cursor    TEXT,                                -- 외부 증분 커서(불투명)
    last_error     TEXT,
    FOREIGN KEY (account_id) REFERENCES mail_account(account_id) ON DELETE CASCADE
);
