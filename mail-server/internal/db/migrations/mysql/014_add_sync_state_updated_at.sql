-- NR0011 B2: stale sync-lock reclaim — sync_state.updated_at heartbeat. [MySQL]
-- 모든 상태 전이에서 갱신되며, acquireSyncLock 이 stale TTL 초과 'syncing' 행을 회수한다.
-- 기존 행은 0 타임스탬프로 백필하여 즉시 회수 가능하게 한다.
ALTER TABLE sync_state ADD COLUMN updated_at VARCHAR(40);
UPDATE sync_state SET updated_at = '1970-01-01T00:00:00Z' WHERE updated_at IS NULL;
