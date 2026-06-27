-- Mail subsystem: message<->label link (PostgreSQL). Composite PK = assign idempotency.
CREATE TABLE mail_message_labels (
    message_uuid VARCHAR(36) NOT NULL,
    label_uuid VARCHAR(36) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_uuid, label_uuid),
    CONSTRAINT fk_msglabels_message FOREIGN KEY (message_uuid) REFERENCES mail_messages (message_uuid) ON DELETE CASCADE,
    CONSTRAINT fk_msglabels_label FOREIGN KEY (label_uuid) REFERENCES mail_labels (label_uuid) ON DELETE CASCADE
);
CREATE INDEX idx_msglabels_label ON mail_message_labels(label_uuid, message_uuid);
