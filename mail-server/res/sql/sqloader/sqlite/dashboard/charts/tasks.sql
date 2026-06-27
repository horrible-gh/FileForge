WITH task_status AS (
    SELECT
        sd.schedule_id,
        sd.detail_id,
        sd.status,
        el.result_code,
        el.start_time,
        el.end_time,
        CASE
            WHEN el.result_code = 0 THEN 'completed'  -- 완료
            WHEN el.result_code IS NULL THEN 'pending'  -- 대기
            WHEN el.start_time IS NOT NULL AND el.end_time IS NULL THEN 'in_progress'  -- 진행 중
            ELSE 'error'  -- 에러
        END AS task_state
    FROM schedule_detail sd
    JOIN schedule_group sg ON sg.schedule_id = sd.schedule_id
    JOIN devices d ON sg.target_device = d.device_id
    LEFT JOIN execution_log el
        ON el.detail_id = sd.detail_id
        AND el.start_time >= DATE_SUB(NOW(), INTERVAL 1 DAY)
    WHERE sd.status IN ('active', 'error')
      AND sg.status NOT IN ('inactive')
      AND d.last_login_at >= DATE_SUB(NOW(), INTERVAL 1 DAY)
      AND d.status NOT IN ('inactive')
),
all_states AS (
    -- 모든 상태를 명시적으로 포함 (0 카운트 방지)
    SELECT 'pending' AS task_state
    UNION ALL
    SELECT 'in_progress'
    UNION ALL
    SELECT 'completed'
    UNION ALL
    SELECT 'error'
),
task_counts AS (
    SELECT
        a.task_state,
        COALESCE(COUNT(t.task_state), 0) AS task_count
    FROM all_states a
    LEFT JOIN task_status t ON a.task_state = t.task_state
    GROUP BY a.task_state
)
SELECT
    MAX(CASE WHEN task_state = 'pending' THEN task_count ELSE 0 END) AS pending_count,
    MAX(CASE WHEN task_state = 'in_progress' THEN task_count ELSE 0 END) AS in_progress_count,
    MAX(CASE WHEN task_state = 'completed' THEN task_count ELSE 0 END) AS completed_count,
    MAX(CASE WHEN task_state = 'error' THEN task_count ELSE 0 END) AS error_count
FROM task_counts
