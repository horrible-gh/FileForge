SELECT label_uuid, label_name, label_color, display_order, created_at, modified_at
FROM mail_labels
WHERE user_uuid = %(user_uuid)s
ORDER BY display_order ASC, label_name ASC
