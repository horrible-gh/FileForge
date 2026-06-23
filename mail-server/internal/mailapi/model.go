// Package mailapi implements the self-contained (DB-only) Phase 1 surface:
// labels (M), settings (M), and the mail read-path (C: list/detail/patch).
// External-service domains (send/SMTP, sync/IMAP, OAuth, attachment bytes) are
// Phase 1 remainder and are not implemented here (see TR0007).
package mailapi

import (
	"encoding/base64"
	"encoding/json"

	"mailanchor/serverd/internal/apperr"
)

// Address — P0007 §3.3
type Address struct {
	Name    string `json:"name,omitempty"`
	Address string `json:"address"`
}

// Label — P0007 §3.5
type Label struct {
	LabelID string  `json:"label_id"`
	Name    string  `json:"name"`
	Type    string  `json:"type"`
	Color   *string `json:"color"`
}

// MailSummary — P0007 §3.1
type MailSummary struct {
	MailID        string   `json:"mail_id"`
	ThreadID      string   `json:"thread_id"`
	From          Address  `json:"from"`
	Subject       string   `json:"subject"`
	Snippet       string   `json:"snippet"`
	ReceivedAt    string   `json:"received_at"`
	IsRead        bool     `json:"is_read"`
	HasAttachment bool     `json:"has_attachment"`
	Labels        []string `json:"labels"`
}

// MailDetail — P0007 §3.2
type MailDetail struct {
	MailID      string       `json:"mail_id"`
	ThreadID    string       `json:"thread_id"`
	From        Address      `json:"from"`
	To          []Address    `json:"to"`
	CC          []Address    `json:"cc"`
	Subject     string       `json:"subject"`
	ReceivedAt  string       `json:"received_at"`
	IsRead      bool         `json:"is_read"`
	Body        Body         `json:"body"`
	Attachments []Attachment `json:"attachments"`
	Labels      []string     `json:"labels"`
}

type Body struct {
	Format  string `json:"format"`
	Content string `json:"content"`
}

// Attachment — P0007 §3.4
type Attachment struct {
	AttachmentID string `json:"attachment_id"`
	Filename     string `json:"filename"`
	SizeBytes    int64  `json:"size_bytes"`
	ContentType  string `json:"content_type"`
}

// PageMeta — P0007 §3.8
type PageMeta struct {
	NextCursor *string `json:"next_cursor"`
	HasMore    bool    `json:"has_more"`
	Count      int     `json:"count"`
}

// cursor is the opaque keyset cursor (L0012 §2.1.1): base64url(json{r,m}).
type cursor struct {
	ReceivedAt string `json:"r"`
	MailID     string `json:"m"`
}

func encodeCursor(receivedAt, mailID string) string {
	b, _ := json.Marshal(cursor{ReceivedAt: receivedAt, MailID: mailID})
	return base64.RawURLEncoding.EncodeToString(b)
}

// decodeCursor returns the keyset bound; empty cursor means "first page".
func decodeCursor(s string) (cursor, error) {
	if s == "" {
		return cursor{}, nil
	}
	raw, err := base64.RawURLEncoding.DecodeString(s)
	if err != nil {
		return cursor{}, apperr.ValidationFailed.WithDetails(map[string]any{"field": "cursor"})
	}
	var c cursor
	if err := json.Unmarshal(raw, &c); err != nil {
		return cursor{}, apperr.ValidationFailed.WithDetails(map[string]any{"field": "cursor"})
	}
	return c, nil
}

func marshalAddrs(a []Address) string {
	if a == nil {
		a = []Address{}
	}
	b, _ := json.Marshal(a)
	return string(b)
}

func unmarshalAddrs(s string) []Address {
	var a []Address
	if s == "" {
		return []Address{}
	}
	_ = json.Unmarshal([]byte(s), &a)
	if a == nil {
		return []Address{}
	}
	return a
}

func unmarshalAddr(s string) Address {
	var a Address
	_ = json.Unmarshal([]byte(s), &a)
	return a
}

func marshalOne(a Address) (string, error) {
	b, err := json.Marshal(a)
	return string(b), err
}
