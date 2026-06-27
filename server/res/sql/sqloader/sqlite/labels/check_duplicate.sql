SELECT label_uuid FROM mail_labels
WHERE user_uuid = :user_uuid AND label_name = :label_name
LIMIT 1
