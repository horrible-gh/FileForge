SELECT
    m.message_uuid, m.account_uuid, m.folder_uuid, m.from_email, m.from_name,
    m.subject, m.preview, m.sent_date, m.is_read, m.is_starred, m.has_attachments,
    m.is_pinned, a.account_name, a.email as account_email, a.display_color, f.folder_name
FROM mail_messages m
JOIN mail_accounts a ON m.account_uuid = a.account_uuid
LEFT JOIN mail_folders f ON m.folder_uuid = f.folder_uuid
WHERE a.user_uuid = ?
  AND a.status = 'active'
