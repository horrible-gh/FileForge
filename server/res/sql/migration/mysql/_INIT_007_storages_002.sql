ALTER TABLE storages
ADD COLUMN storage_type ENUM('file', 'note', 'password') DEFAULT 'file'
AFTER storage_name;
