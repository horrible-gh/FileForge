SELECT n.node_uuid, n.name, n.type, n.parent_uuid, s.storage_path
FROM nodes n
INNER JOIN storages s ON s.storage_uuid = n.storage_uuid
WHERE n.node_uuid = %s