UPDATE mail_labels
SET label_name = COALESCE(%(label_name)s, label_name),
    label_color = COALESCE(%(label_color)s, label_color),
    display_order = COALESCE(%(display_order)s, display_order)
WHERE label_uuid = %(label_uuid)s
