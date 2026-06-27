SELECT l.label_uuid, l.label_name, l.label_color
FROM mail_labels l
JOIN mail_message_labels ml ON l.label_uuid = ml.label_uuid
WHERE ml.message_uuid = :message_uuid
ORDER BY l.label_name ASC
