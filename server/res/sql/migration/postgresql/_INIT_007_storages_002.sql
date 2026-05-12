ALTER TABLE storages
ADD COLUMN storage_type VARCHAR(8) DEFAULT 'file' CHECK (storage_type IN ('file', 'note', 'password'));
