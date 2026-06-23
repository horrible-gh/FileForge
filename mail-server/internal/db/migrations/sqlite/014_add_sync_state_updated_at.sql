-- NR0011 B2: stale sync-lock reclaim. sync_state had no heartbeat column, so a process
-- that died/panicked mid-sync left state='syncing' forever and blocked every later sync.
-- updated_at is stamped on every state transition; acquireSyncLock reclaims a 'syncing'
-- row whose updated_at is older than the stale TTL. Backfill existing rows with a zero
-- timestamp so any currently-stuck row is immediately reclaimable.
ALTER TABLE sync_state ADD COLUMN updated_at TEXT;
UPDATE sync_state SET updated_at = '1970-01-01T00:00:00Z' WHERE updated_at IS NULL;
