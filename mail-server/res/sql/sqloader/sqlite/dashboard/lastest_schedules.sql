WITH instance_group AS (
  SELECT
    schedule_id,
    execution_grp_id,
    MIN(start_time) AS group_start_time,
    MAX(end_time) AS group_end_time,
    MAX(start_time) AS group_latest_time
  FROM execution_log
  GROUP BY schedule_id, execution_grp_id
),
last_instance AS (
  SELECT *
  FROM (
    SELECT
      ig.*,
      ROW_NUMBER() OVER (PARTITION BY schedule_id ORDER BY group_latest_time DESC) AS rn
    FROM instance_group ig
  ) t
  WHERE rn = 1
),
executed_tasks_last AS (
  SELECT
    el.schedule_id,
    COUNT(DISTINCT detail_id) AS executed_tasks
  FROM execution_log el
  JOIN last_instance li
    ON el.schedule_id = li.schedule_id
   AND el.execution_grp_id = li.execution_grp_id
  GROUP BY el.schedule_id
),
first_error_last AS (
  SELECT
    el.schedule_id,
    REPLACE(el.result_message, '\n', ' ') AS raw_error,
    el.start_time
  FROM execution_log el
  JOIN last_instance li
    ON el.schedule_id = li.schedule_id
   AND el.execution_grp_id = li.execution_grp_id
  WHERE el.result_code = -1
  ORDER BY el.start_time ASC
),
first_error_per_group AS (
  SELECT
    schedule_id,
    MIN(raw_error) AS raw_error
  FROM first_error_last
  GROUP BY schedule_id
),
task_counts AS (
  SELECT
    schedule_id,
    COUNT(*) AS total_tasks
  FROM schedule_detail
  WHERE status <> 'inactive'
  GROUP BY schedule_id
)
SELECT
  sg.schedule_id,
  -- 커스텀 상태:
  -- 1) 스케줄 그룹의 상태가 'error'이거나 마지막 인스턴스에서 실행된 태스크 수가 전체 태스크 수보다 작으면 'error'
  -- 2) 스케줄 그룹 상태가 active이면서 모든 태스크 실행됐으나 에러 메시지가 존재하면 'warning'
  -- 3) 그 외에는 'completed'
  CASE
    WHEN sg.status = 'error' OR etl.executed_tasks < tc.total_tasks THEN 'error'
    WHEN sg.status = 'active' AND etl.executed_tasks = tc.total_tasks AND fep.raw_error IS NOT NULL THEN 'warning'
    ELSE 'completed'
  END AS custom_status,
  d.device_name,
  sg.name AS sg_name,
  -- 그룹 상태: devices.last_login_at 기준 하루 이내 로그인 기록이 없으면 'disconnected'
  CASE
    WHEN d.last_login_at < DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 DAY) THEN 'disconnected'
    WHEN sg.status = 'error' OR etl.executed_tasks < tc.total_tasks THEN 'error'
    ELSE sg.status
  END AS group_status,
  tc.total_tasks AS task_count,
  li.group_start_time,
  li.group_end_time,
  -- 에러 메시지 요약: 최초 에러 메시지를 최대 25글자 내로 표시 (25자 초과 시 22글자 + '...')
  CASE
    WHEN fep.raw_error IS NOT NULL THEN
      CASE
        WHEN CHAR_LENGTH(fep.raw_error) > 25 THEN CONCAT(SUBSTRING(fep.raw_error, 1, 22), '...')
        ELSE fep.raw_error
      END
    ELSE NULL
  END AS error_summary
FROM schedule_group sg
JOIN devices d
  ON sg.target_device = d.device_id
JOIN last_instance li
  ON sg.schedule_id = li.schedule_id
JOIN task_counts tc
  ON sg.schedule_id = tc.schedule_id
JOIN executed_tasks_last etl
  ON sg.schedule_id = etl.schedule_id
LEFT JOIN first_error_per_group fep
  ON sg.schedule_id = fep.schedule_id
ORDER BY li.group_latest_time DESC
LIMIT 3
