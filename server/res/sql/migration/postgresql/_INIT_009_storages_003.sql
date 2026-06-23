-- Add 'mail' as a first-class storage_type (MailAnchor absorption).
-- Replaces the inline CHECK created by _INIT_007 (PostgreSQL auto-names it
-- "storages_storage_type_check") with one that also permits 'mail'.
ALTER TABLE storages DROP CONSTRAINT IF EXISTS storages_storage_type_check;
ALTER TABLE storages ADD CONSTRAINT storages_storage_type_check
    CHECK (storage_type IN ('file', 'note', 'password', 'mail'));
