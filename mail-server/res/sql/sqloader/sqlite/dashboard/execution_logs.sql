SELECT
        el.execution_id
        , sg.name sg_name
        , sd.schedule_name
        , el.start_time
        , el.end_time
        , el.result_code
        , el.result_message
		, td.task_type
		, td.command
		, td.source_path
		, td.destination_path
FROM execution_log el
JOIN schedule_group sg
        ON sg.schedule_id = el.schedule_id
JOIN schedule_detail sd
        ON sd.detail_id = el.detail_id
JOIN task_detail td
		ON td.detail_id = sd.detail_id
ORDER BY el.execution_id DESC
