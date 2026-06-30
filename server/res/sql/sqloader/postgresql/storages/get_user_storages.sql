SELECT
    ss.storage_uuid,
    ss.storage_name,
    ss.storage_type,
    ss.storage_path,
    ss.quota_limit,
    us.is_default,
    -- Storage usage = file-node bytes (file/note storages) PLUS live mail bytes
    -- for mail-type storages. Mail data lives in mail_messages (not in
    -- nodes/files), so without the correlated sum a mail storage always
    -- reported used_size=0 ("infinite space", fileforge.mailanchorpython.0029).
    -- size_bytes is the stored .eml (raw MIME) size and already includes
    -- attachment bytes, so attachments are NOT summed separately to avoid
    -- double counting. Only live (is_deleted = 0) messages count.
    COALESCE(SUM(f.file_size), 0)
      + COALESCE((
            SELECT SUM(mm.size_bytes)
            FROM mail_messages mm
            JOIN mail_accounts ma ON ma.account_uuid = mm.account_uuid
            JOIN user_storages us2 ON us2.user_uuid = ma.user_uuid
            WHERE us2.storage_uuid = ss.storage_uuid
              AND ss.storage_type = 'mail'
              AND mm.is_deleted = 0
        ), 0) AS used_size
FROM storages ss
JOIN user_storages us
    ON us.storage_uuid = ss.storage_uuid
    AND (us.user_uuid = %s OR us.group_uuid = %s)
    AND ss.status = 'active'
LEFT JOIN nodes n ON n.storage_uuid = ss.storage_uuid AND n.type = 'file'
LEFT JOIN files f ON f.node_uuid = n.node_uuid
GROUP BY ss.storage_uuid, ss.storage_name, ss.storage_type, ss.storage_path, ss.quota_limit, us.is_default
