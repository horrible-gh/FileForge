WITH  sorting AS (
    SELECT 'folder' AS type, 1 AS sort_seq
    UNION ALL
    SELECT 'file' AS type, 2 AS sort_seq
)
SELECT
    ns.node_uuid
    , ns.name
    , ns.type
    , files.file_size
    , ns.parent_uuid
    , ns.created_at
    , ns.modified_at
    , users.user_name AS modifier_name
FROM
    nodes ns
JOIN users
    ON users.user_uuid = ns.creator_uuid
LEFT JOIN sorting
    ON sorting.type = ns.type
LEFT JOIN files
    ON files.node_uuid = ns.node_uuid
WHERE
    ns.storage_uuid = %s
    AND (
        %s = 'directory'
        OR (
            %s = 'file'
            AND (
                (
                    %s IS NULL
                    AND ns.parent_uuid IS NULL
                )
                OR (
                    %s IS NOT NULL
                    AND ns.parent_uuid = %s
                )
            )
        )
    )
    AND ns.type LIKE %s
    AND (%s IS NULL OR ns.name LIKE %s)
ORDER BY
    sorting.sort_seq, ns.name
