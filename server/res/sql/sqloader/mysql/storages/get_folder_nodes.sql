WITH RECURSIVE tree AS (
    SELECT node_uuid, name, type, parent_uuid
    FROM nodes
    WHERE node_uuid = %s
    
    UNION ALL
    
    SELECT n.node_uuid, n.name, n.type, n.parent_uuid
    FROM nodes n
    INNER JOIN tree t ON n.parent_uuid = t.node_uuid
)
SELECT node_uuid, type FROM tree WHERE type = 'file'
