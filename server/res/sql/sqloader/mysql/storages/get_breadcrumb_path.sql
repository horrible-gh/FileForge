WITH RECURSIVE path AS (
    SELECT node_uuid, name, parent_uuid, 1 as level
    FROM nodes
    WHERE node_uuid = %s
    
    UNION ALL
    
    SELECT n.node_uuid, n.name, n.parent_uuid, p.level + 1
    FROM nodes n
    INNER JOIN path p ON n.node_uuid = p.parent_uuid
)
SELECT node_uuid, name
FROM path
ORDER BY level DESC;