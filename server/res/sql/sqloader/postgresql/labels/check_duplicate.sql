SELECT label_uuid FROM mail_labels
WHERE user_uuid = %(user_uuid)s AND label_name = %(label_name)s
LIMIT 1
