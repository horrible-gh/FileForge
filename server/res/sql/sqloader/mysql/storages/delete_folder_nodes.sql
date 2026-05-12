DELETE FROM nodes 
WHERE node_uuid IN (
    WITH RECURSIVE tree AS (
        SELECT node_uuid FROM nodes WHERE node_uuid = %s
        UNION ALL
        SELECT n.node_uuid FROM nodes n
        INNER JOIN tree t ON n.parent_uuid = t.node_uuid
    )
    SELECT node_uuid FROM tree
)
