ALTER TABLE storages
ADD COLUMN storage_type TEXT DEFAULT 'file' CHECK (storage_type IN ('file', 'note', 'password'));
