SELECT
    s.storage_path,
    s.quota_limit,
    COALESCE(SUM(f.file_size), 0) as used_size
FROM storages s
LEFT JOIN nodes n ON n.storage_uuid = s.storage_uuid AND n.type = 'file'
LEFT JOIN files f ON f.node_uuid = n.node_uuid
WHERE s.storage_uuid = %s
GROUP BY s.storage_uuid, s.storage_path, s.quota_limit
