SELECT m.*, a.email as account_email,
       GROUP_CONCAT(DISTINCT l.label_name) as labels,
       GROUP_CONCAT(DISTINCT l.label_color) as label_colors
FROM mail_messages m
JOIN mail_message_labels ml ON m.message_uuid = ml.message_uuid
JOIN mail_labels l ON ml.label_uuid = l.label_uuid
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
WHERE ml.label_uuid = :label_uuid
  AND a.user_uuid = :user_uuid
  AND m.is_deleted = 0
GROUP BY m.message_uuid
ORDER BY m.sent_date DESC
LIMIT :limit OFFSET :offset
