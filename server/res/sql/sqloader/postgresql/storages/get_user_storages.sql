SELECT
    ss.storage_uuid,
    ss.storage_name,
    ss.storage_type,
    ss.storage_path,
    ss.quota_limit,
    us.is_default,
    COALESCE(SUM(f.file_size), 0) as used_size
FROM storages ss
JOIN user_storages us
    ON us.storage_uuid = ss.storage_uuid
    AND (us.user_uuid = %s OR us.group_uuid = %s)
    AND ss.status = 'active'
LEFT JOIN nodes n ON n.storage_uuid = ss.storage_uuid AND n.type = 'file'
LEFT JOIN files f ON f.node_uuid = n.node_uuid
GROUP BY ss.storage_uuid, ss.storage_name, ss.storage_type, ss.storage_path, ss.quota_limit, us.is_default
