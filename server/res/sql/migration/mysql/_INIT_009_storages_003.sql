-- Add 'mail' as a first-class storage_type (MailAnchor absorption).
-- Extends the existing ENUM('file','note','password') from _INIT_007.
ALTER TABLE storages
MODIFY COLUMN storage_type ENUM('file', 'note', 'password', 'mail') DEFAULT 'file';
