SELECT m.*,
       a.email as account_email,
       GROUP_CONCAT(DISTINCT l.label_name ORDER BY l.label_name) as labels,
       GROUP_CONCAT(DISTINCT l.label_color ORDER BY l.label_name) as label_colors
FROM mail_messages m
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
LEFT JOIN mail_message_labels ml ON m.message_uuid = ml.message_uuid
LEFT JOIN mail_labels l ON ml.label_uuid = l.label_uuid
WHERE a.user_uuid = %(user_uuid)s
  AND m.is_deleted = FALSE
  AND (m.subject LIKE %(search_term)s OR m.from_email LIKE %(search_term)s OR m.from_name LIKE %(search_term)s)
GROUP BY m.message_uuid
ORDER BY m.sent_date DESC
LIMIT %(limit)s OFFSET %(offset)s
