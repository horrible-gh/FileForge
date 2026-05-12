WITH RECURSIVE tree AS (
    SELECT s.storage_path, n.node_uuid, n.name, n.type, n.parent_uuid, n.storage_uuid,
           CAST(n.name AS TEXT) as full_path
    FROM nodes n
    INNER JOIN storages s ON s.storage_uuid = n.storage_uuid
    WHERE n.node_uuid = %s

    UNION ALL

    SELECT s.storage_path, n.node_uuid, n.name, n.type, n.parent_uuid, n.storage_uuid,
           CONCAT(t.full_path, '/', n.name) as full_path
    FROM nodes n
    INNER JOIN tree t ON n.parent_uuid = t.node_uuid
    INNER JOIN storages s ON s.storage_uuid = n.storage_uuid
)
SELECT storage_path, node_uuid, name, type, parent_uuid, full_path
FROM tree
