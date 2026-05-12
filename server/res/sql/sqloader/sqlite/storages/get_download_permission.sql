WITH get_storage_uuid AS (
    SELECT
        CASE WHEN ? = 'default' THEN us.storage_uuid
             ELSE ?
         END AS storage_uuid
        , us.user_uuid
      FROM user_storages us
     WHERE is_default = 1
       AND user_uuid = ?
)
SELECT 1 
  FROM user_storages us
  JOIN get_storage_uuid su
    ON 1 = 1
 WHERE us.storage_uuid = su.storage_uuid
   AND (us.user_uuid = su.user_uuid OR us.group_uuid = ?)
   AND us.mode IN ('r', 'rw')
