-- NR0011 B2: stale sync-lock reclaim — sync_state.updated_at heartbeat. [MySQL]
-- all state translated text refreshtext, acquireSyncLock text stale TTL exceeded 'syncing' text translated text.
-- text text 0 translated text translated text text text translated text text.
ALTER TABLE sync_state ADD COLUMN updated_at VARCHAR(40);
UPDATE sync_state SET updated_at = '1970-01-01T00:00:00Z' WHERE updated_at IS NULL;
