SELECT l.label_uuid, l.label_name, l.label_color,
       COUNT(ml.message_uuid) as message_count,
       SUM(CASE WHEN m.is_read = FALSE THEN 1 ELSE 0 END) as unread_count
FROM mail_labels l
LEFT JOIN mail_message_labels ml ON l.label_uuid = ml.label_uuid
LEFT JOIN mail_messages m ON ml.message_uuid = m.message_uuid AND m.is_deleted = FALSE
WHERE l.user_uuid = %(user_uuid)s
GROUP BY l.label_uuid
ORDER BY l.display_order ASC, l.label_name ASC
