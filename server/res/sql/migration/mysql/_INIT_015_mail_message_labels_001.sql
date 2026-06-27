-- Mail subsystem: message<->label N:M link.
-- Composite PK = assign idempotency. FK -> mail_messages, mail_labels ON DELETE CASCADE.
CREATE TABLE mail_message_labels (
    message_uuid VARCHAR(36) NOT NULL,
    label_uuid VARCHAR(36) NOT NULL,

    created_at DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,

    PRIMARY KEY (message_uuid, label_uuid),
    INDEX idx_msglabels_label (label_uuid, message_uuid),
    CONSTRAINT fk_msglabels_message FOREIGN KEY (message_uuid)
        REFERENCES mail_messages (message_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_msglabels_label FOREIGN KEY (label_uuid)
        REFERENCES mail_labels (label_uuid) ON DELETE CASCADE
);
