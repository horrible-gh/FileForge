SELECT 
    m.*,
    a.account_name,
    a.email as account_email,
    a.display_color,
    f.folder_name,
    f.folder_type
FROM mail_messages m
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
LEFT JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
WHERE m.message_uuid = %s 
  AND a.user_uuid = %s
