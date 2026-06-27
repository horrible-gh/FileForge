SELECT COUNT(*) as total
FROM mail_messages m
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
LEFT JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
WHERE a.user_uuid = %s 
  AND a.status = 'active'
