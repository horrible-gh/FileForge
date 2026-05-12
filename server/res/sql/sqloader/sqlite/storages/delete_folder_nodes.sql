WITH RECURSIVE tree AS (
    SELECT node_uuid FROM nodes WHERE node_uuid = ?
    UNION ALL
    SELECT n.node_uuid FROM nodes n
    INNER JOIN tree t ON n.parent_uuid = t.node_uuid
)
DELETE FROM nodes WHERE node_uuid IN (SELECT node_uuid FROM tree)
