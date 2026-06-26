-- DB0008 §2.9 sync_state — accounttext 1text sync state·text
CREATE TABLE sync_state (
    account_id     TEXT NOT NULL PRIMARY KEY,           -- invariant 6 (accounttext 0/1text)
    state          TEXT NOT NULL DEFAULT 'idle' CHECK (state IN ('idle','syncing','error')),
    last_synced_at TEXT,
    sync_cursor    TEXT,                                -- text textminutes text(translated text)
    last_error     TEXT,
    FOREIGN KEY (account_id) REFERENCES mail_account(account_id) ON DELETE CASCADE
);
