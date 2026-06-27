WITH schedule_group_status AS (
    SELECT
        sg.schedule_id
        , sg.status AS group_status
        , sg.target_device
    FROM schedule_group sg
),
execution_logs AS (
    -- 최근 24시간 내 실행 로그 수집
    SELECT el.schedule_id,
           MAX(CASE WHEN el.result_code != 0 THEN 1 ELSE 0 END) AS has_error,
           MIN(CASE WHEN el.result_code = 0 THEN 1 ELSE 0 END) AS all_success
    FROM execution_log el
    WHERE el.start_time >= DATE_SUB(NOW(), INTERVAL 1 DAY)
    GROUP BY el.schedule_id
),
schedule_final_status AS (
    SELECT
        sg.schedule_id,
        CASE
            WHEN d.last_login_at <= DATE_SUB(NOW(), INTERVAL 1 DAY)
                OR sg.group_status = 'inactive'
                THEN 'inactive'
            WHEN el.has_error = 1 THEN 'error'  -- 실행 로그 중 하나라도 에러가 있으면 error
            WHEN el.schedule_id IS NULL THEN 'active' -- 실행 로그가 없으면 active
            WHEN el.all_success = 1 THEN 'active' -- 모든 실행 로그가 성공이면 active
            ELSE 'error' -- 실행 로그가 있지만 실패한 경우 error
        END AS final_status
    FROM schedule_group_status sg
    JOIN devices d ON sg.target_device = d.device_id
    LEFT JOIN execution_logs el ON sg.schedule_id = el.schedule_id
)
SELECT
    COUNT(CASE WHEN sfs.final_status = 'active' THEN 1 END) AS active_count,
    COUNT(CASE WHEN sfs.final_status = 'error' THEN 1 END) AS error_count,
    COUNT(CASE WHEN sfs.final_status = 'inactive' THEN 1 END) AS inactive_count
FROM schedule_final_status sfs
