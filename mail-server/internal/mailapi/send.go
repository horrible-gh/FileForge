package mailapi

import (
	"database/sql"
	"errors"
	"net/http"
	"net/mail"
	"strings"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/idgen"
)

// recipientsMax / snippetMaxChars / subjectMaxChars — L0012 §1.
const (
	recipientsMax   = 100
	snippetMaxChars = 140
	subjectMaxChars = 998
)

// ErrAttachmentMissing — a referenced attachment is not a user-owned draft attachment.
var ErrAttachmentMissing = errors.New("attachment missing")

// sendInput is the validated, thread-resolved input to the persist transaction.
type sendInput struct {
	accountID     string
	from          Address
	to, cc        []Address
	subject       string
	body          Body
	inReplyTo     *string
	fromDraftID   *string
	attachmentIDs []string
	sentAt        string
}

type sendResult struct {
	MailID   string `json:"mail_id"`
	ThreadID string `json:"thread_id"`
	Status   string `json:"status"`
	SentAt   string `json:"sent_at"`
}

// persistSent writes the outbound mail in one transaction (L0012 §2.4 step c):
// resolve thread, insert mail, reattach draft attachments / bind listed attachments,
// delete the source draft, and recompute has_attachment (DB0008 invariant 8).
func (s *Store) persistSent(userID string, in sendInput) (sendResult, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return sendResult{}, err
	}
	defer tx.Rollback() //nolint:errcheck

	// resolve_thread (L0012 §2.4.1): join the original thread on reply/forward, else new.
	threadID := idgen.New(idgen.Thread)
	if in.inReplyTo != nil && *in.inReplyTo != "" {
		var t string
		if err := tx.QueryRow(`SELECT thread_id FROM mail WHERE user_id=? AND mail_id=?`,
			userID, *in.inReplyTo).Scan(&t); err == nil {
			threadID = t
		} else if !errors.Is(err, sql.ErrNoRows) {
			return sendResult{}, err
		}
	}

	mailID := idgen.New(idgen.Mail)
	fromJSON, _ := marshalOne(in.from)
	_, err = tx.Exec(
		`INSERT INTO mail(mail_id,user_id,account_id,thread_id,from_addr,to_addrs,cc_addrs,subject,snippet,
		   body_format,body_content,received_at,is_read,has_attachment,direction,sent_at)
		 VALUES(?,?,?,?,?,?,?,?,?,?,?,?, 1, 0, 'outbound', ?)`,
		mailID, userID, in.accountID, threadID, fromJSON, marshalAddrs(in.to), marshalAddrs(in.cc),
		in.subject, makeSnippet(in.body.Content), in.body.Format, in.body.Content, in.sentAt, in.sentAt)
	if err != nil {
		return sendResult{}, err
	}

	// Re-attribute attachments from their draft to this mail (DB0008 invariant 5: exclusive
	// ownership — flip draft_id->mail_id so the row still satisfies the XOR CHECK).
	// Collect the set: all of the source draft's attachments + any explicitly listed ids.
	reattach := map[string]bool{}
	if in.fromDraftID != nil && *in.fromDraftID != "" {
		// verify draft ownership
		var owned int
		if err := tx.QueryRow(`SELECT 1 FROM draft WHERE user_id=? AND draft_id=?`,
			userID, *in.fromDraftID).Scan(&owned); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return sendResult{}, ErrAttachmentMissing
			}
			return sendResult{}, err
		}
		rows, err := tx.Query(`SELECT attachment_id FROM attachment WHERE draft_id=?`, *in.fromDraftID)
		if err != nil {
			return sendResult{}, err
		}
		for rows.Next() {
			var aid string
			if err := rows.Scan(&aid); err != nil {
				rows.Close()
				return sendResult{}, err
			}
			reattach[aid] = true
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return sendResult{}, err
		}
	}
	for _, aid := range in.attachmentIDs {
		// each listed id must be a user-owned draft attachment
		var owned int
		err := tx.QueryRow(
			`SELECT 1 FROM attachment a JOIN draft d ON a.draft_id=d.draft_id
			 WHERE a.attachment_id=? AND d.user_id=?`, aid, userID).Scan(&owned)
		if errors.Is(err, sql.ErrNoRows) {
			return sendResult{}, ErrAttachmentMissing
		}
		if err != nil {
			return sendResult{}, err
		}
		reattach[aid] = true
	}
	for aid := range reattach {
		if _, err := tx.Exec(`UPDATE attachment SET mail_id=?, draft_id=NULL WHERE attachment_id=?`,
			mailID, aid); err != nil {
			return sendResult{}, err
		}
	}

	// delete the source draft (its remaining, un-sent attachments CASCADE away).
	if in.fromDraftID != nil && *in.fromDraftID != "" {
		if _, err := tx.Exec(`DELETE FROM draft WHERE user_id=? AND draft_id=?`, userID, *in.fromDraftID); err != nil {
			return sendResult{}, err
		}
	}

	if err := recomputeHasAttachmentTx(tx, mailID); err != nil {
		return sendResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return sendResult{}, err
	}
	return sendResult{MailID: mailID, ThreadID: threadID, Status: "sent", SentAt: in.sentAt}, nil
}

// recomputeHasAttachmentTx syncs the has_attachment denormalized cache (L0012 §2.7).
func recomputeHasAttachmentTx(tx *sql.Tx, mailID string) error {
	var cnt int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM attachment WHERE mail_id=?`, mailID).Scan(&cnt); err != nil {
		return err
	}
	v := 0
	if cnt > 0 {
		v = 1
	}
	_, err := tx.Exec(`UPDATE mail SET has_attachment=? WHERE mail_id=?`, v, mailID)
	return err
}

func makeSnippet(content string) string {
	c := strings.TrimSpace(content)
	if len(c) > snippetMaxChars {
		// trim on a rune boundary to avoid splitting multibyte (e.g. Korean) text.
		r := []rune(c)
		if len(r) > snippetMaxChars {
			r = r[:snippetMaxChars]
		}
		return string(r)
	}
	return c
}

// resolveAttachments loads the bytes-bearing metadata for a mail's attachments so the
// Sender can build the MIME body. Used by the send handler after persistence checks.
func (s *Store) draftOutgoingAttachments(userID string, draftID *string, ids []string) ([]OutgoingAttachment, error) {
	q := `SELECT a.filename,a.content_type,a.storage_ref FROM attachment a
	      JOIN draft d ON a.draft_id=d.draft_id WHERE d.user_id=?`
	args := []any{userID}
	if draftID != nil && *draftID != "" {
		q += ` AND (d.draft_id=? `
		args = append(args, *draftID)
		if len(ids) > 0 {
			q += ` OR a.attachment_id IN (` + placeholders(len(ids)) + `))`
			for _, id := range ids {
				args = append(args, id)
			}
		} else {
			q += `)`
		}
	} else if len(ids) > 0 {
		q += ` AND a.attachment_id IN (` + placeholders(len(ids)) + `)`
		for _, id := range ids {
			args = append(args, id)
		}
	} else {
		return nil, nil
	}
	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []OutgoingAttachment{}
	for rows.Next() {
		var a OutgoingAttachment
		if err := rows.Scan(&a.Filename, &a.ContentType, &a.StorageRef); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// validateOutgoingAttachments verifies every explicitly listed attachment_id is a
// user-owned draft attachment, BEFORE the external send (NR0011 B1). Previously this
// ownership check lived only in persistSent (after Sender.Send), so a foreign id caused
// the mail to be relayed externally yet the API to answer 404 with a local rollback —
// the recipient got the mail, the caller saw failure. Returns ErrAttachmentMissing.
func (s *Store) validateOutgoingAttachments(userID string, ids []string) error {
	for _, aid := range ids {
		var owned int
		err := s.db.QueryRow(
			`SELECT 1 FROM attachment a JOIN draft d ON a.draft_id=d.draft_id
			 WHERE a.attachment_id=? AND d.user_id=?`, aid, userID).Scan(&owned)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrAttachmentMissing
		}
		if err != nil {
			return err
		}
	}
	return nil
}

func placeholders(n int) string {
	if n <= 0 {
		return ""
	}
	return strings.TrimSuffix(strings.Repeat("?,", n), ",")
}

// --- handler ---

type sendReq struct {
	To            []Address `json:"to"`
	CC            []Address `json:"cc"`
	BCC           []Address `json:"bcc"`
	Subject       string    `json:"subject"`
	Body          Body      `json:"body"`
	InReplyTo     *string   `json:"in_reply_to"`
	ReplyType     *string   `json:"reply_type"`
	FromDraftID   *string   `json:"from_draft_id"`
	AttachmentIDs []string  `json:"attachment_ids"`
}

// SendMail implements POST /mails (L0012 §2.4): validate recipients, send via the
// external Sender wrapped in backoff, then persist in one transaction.
func (h *Handlers) SendMail(w http.ResponseWriter, r *http.Request) {
	userID := uid(r)
	var req sendReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}

	// (a) recipient validation — reject before the transaction / external call.
	recips := 0
	for _, group := range []struct {
		field string
		addrs []Address
	}{{"to", req.To}, {"cc", req.CC}, {"bcc", req.BCC}} {
		for i, a := range group.addrs {
			if _, perr := mail.ParseAddress(a.Address); perr != nil || strings.TrimSpace(a.Address) == "" {
				httpx.Error(w, apperr.RecipientInvalid.WithDetails(map[string]any{
					"field": group.field + "[" + itoa(i) + "].address", "value": a.Address}))
				return
			}
			recips++
		}
	}
	if recips == 0 || recips > recipientsMax {
		// L0012 §2.4: 0-recipient / over-limit is a recipient violation (RECIPIENT_INVALID
		// 422), not a generic VALIDATION_FAILED 400 (NR0011 B5).
		httpx.Error(w, apperr.RecipientInvalid.WithDetails(map[string]any{"field": "recipients", "count": recips}))
		return
	}
	if len([]rune(req.Subject)) > subjectMaxChars {
		req.Subject = string([]rune(req.Subject)[:subjectMaxChars])
	}

	acct, err := h.store.PrimaryAccount(userID)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "no connected account"}))
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}

	// (a.2) attachment ownership — validate listed ids BEFORE the external send so a
	// foreign/missing id fails fast (404) instead of after the mail has gone out (B1).
	if verr := h.store.validateOutgoingAttachments(userID, req.AttachmentIDs); verr != nil {
		if errors.Is(verr, ErrAttachmentMissing) {
			httpx.Error(w, apperr.AttachmentNotFound)
			return
		}
		httpx.Error(w, apperr.Internal)
		return
	}

	// (b) external send (L0010 §2.4 with_backoff). nil Sender -> SEND_FAILED.
	atts, err := h.store.draftOutgoingAttachments(userID, req.FromDraftID, req.AttachmentIDs)
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	from := Address{Name: acct.DisplayName, Address: acct.Email}
	out := OutgoingMail{From: from, To: req.To, CC: req.CC, BCC: req.BCC,
		Subject: req.Subject, Body: req.Body, Attachments: atts}
	if h.deps.Sender == nil {
		httpx.Error(w, apperr.SendFailed.WithDetails(map[string]any{"reason": "sender not configured"}))
		return
	}
	ext := ExternalAccount{AccountID: acct.AccountID, UserID: userID, Email: acct.Email,
		Provider: acct.Provider, OAuthRef: acct.OAuthRef}
	sendErr := h.deps.sendRetry().Do(func() error { return h.deps.Sender.Send(ext, out) }, h.sleep)
	if sendErr != nil {
		httpx.Error(w, apperr.SendFailed.WithDetails(map[string]any{"reason": sendErr.Error()}))
		return
	}

	// (c) persist transaction.
	in := sendInput{
		accountID: acct.AccountID, from: from, to: req.To, cc: req.CC,
		subject: req.Subject, body: req.Body, inReplyTo: req.InReplyTo,
		fromDraftID: req.FromDraftID, attachmentIDs: req.AttachmentIDs, sentAt: h.now(),
	}
	res, err := h.store.persistSent(userID, in)
	if errors.Is(err, ErrAttachmentMissing) {
		httpx.Error(w, apperr.AttachmentNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusCreated, res)
}
