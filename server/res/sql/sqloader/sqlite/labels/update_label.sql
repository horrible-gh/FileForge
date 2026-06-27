UPDATE mail_labels
SET label_name = COALESCE(:label_name, label_name),
    label_color = COALESCE(:label_color, label_color),
    display_order = COALESCE(:display_order, display_order)
WHERE label_uuid = :label_uuid
