SELECT COUNT(DISTINCT m.message_uuid) as total
FROM mail_messages m
JOIN mail_message_labels ml ON m.message_uuid = ml.message_uuid
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
WHERE ml.label_uuid = %(label_uuid)s
  AND a.user_uuid = %(user_uuid)s
  AND m.is_deleted = FALSE
