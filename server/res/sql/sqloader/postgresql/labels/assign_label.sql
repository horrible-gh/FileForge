INSERT INTO mail_message_labels (message_uuid, label_uuid)
VALUES (%(message_uuid)s, %(label_uuid)s)
ON CONFLICT (message_uuid, label_uuid) DO NOTHING
