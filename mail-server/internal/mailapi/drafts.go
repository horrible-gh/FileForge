package mailapi

import (
	"database/sql"
	"errors"
	"net/http"

	"github.com/go-chi/chi/v5"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/idgen"
)

// ErrConflict — optimistic-concurrency mismatch on draft update (L0012 §2.6).
var ErrConflict = errors.New("draft conflict")

// Draft — wire shape for the compose surface (P0007 §6.2 / DB0008 §2.8).
type Draft struct {
	DraftID   string    `json:"draft_id"`
	AccountID *string   `json:"account_id"`
	InReplyTo *string   `json:"in_reply_to"`
	ReplyType *string   `json:"reply_type"`
	To        []Address `json:"to"`
	CC        []Address `json:"cc"`
	Subject   string    `json:"subject"`
	Body      Body      `json:"body"`
	UpdatedAt string    `json:"updated_at"`
}

func (s *Store) CreateDraft(userID string, d Draft, now string) (Draft, error) {
	d.DraftID = idgen.New(idgen.Draft)
	d.UpdatedAt = now
	_, err := s.db.Exec(
		`INSERT INTO draft(draft_id,user_id,account_id,in_reply_to,reply_type,to_addrs,cc_addrs,
		   subject,body_format,body_content,updated_at)
		 VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
		d.DraftID, userID, nullOf(d.AccountID), nullOf(d.InReplyTo), nullOf(d.ReplyType),
		marshalAddrs(d.To), marshalAddrs(d.CC), d.Subject, bodyFormat(d.Body), d.Body.Content, now)
	if err != nil {
		return Draft{}, err
	}
	return d, nil
}

func (s *Store) GetDraft(userID, draftID string) (Draft, error) {
	var (
		d       Draft
		acct    sql.NullString
		inReply sql.NullString
		reply   sql.NullString
		toJSON  string
		ccJSON  string
		bodyFmt string
		bodyC   sql.NullString
	)
	err := s.db.QueryRow(
		`SELECT draft_id,account_id,in_reply_to,reply_type,to_addrs,cc_addrs,subject,
		   body_format,body_content,updated_at
		 FROM draft WHERE user_id=? AND draft_id=?`, userID, draftID).
		Scan(&d.DraftID, &acct, &inReply, &reply, &toJSON, &ccJSON, &d.Subject, &bodyFmt, &bodyC, &d.UpdatedAt)
	if err != nil {
		return Draft{}, err
	}
	if acct.Valid {
		d.AccountID = &acct.String
	}
	if inReply.Valid {
		d.InReplyTo = &inReply.String
	}
	if reply.Valid {
		d.ReplyType = &reply.String
	}
	d.To = unmarshalAddrs(toJSON)
	d.CC = unmarshalAddrs(ccJSON)
	d.Body = Body{Format: bodyFmt, Content: bodyC.String}
	return d, nil
}

// UpdateDraft applies an optimistic-concurrency update (L0012 §2.6): the row is
// updated only when its updated_at still equals base. ErrConflict on mismatch,
// sql.ErrNoRows when the draft is gone.
func (s *Store) UpdateDraft(userID, draftID string, d Draft, base, now string) (string, error) {
	res, err := s.db.Exec(
		`UPDATE draft SET account_id=?,in_reply_to=?,reply_type=?,to_addrs=?,cc_addrs=?,
		   subject=?,body_format=?,body_content=?,updated_at=?
		 WHERE draft_id=? AND user_id=? AND updated_at=?`,
		nullOf(d.AccountID), nullOf(d.InReplyTo), nullOf(d.ReplyType), marshalAddrs(d.To), marshalAddrs(d.CC),
		d.Subject, bodyFormat(d.Body), d.Body.Content, now, draftID, userID, base)
	if err != nil {
		return "", err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		// distinguish "gone" from "stale base"
		var cur string
		if err := s.db.QueryRow(`SELECT updated_at FROM draft WHERE user_id=? AND draft_id=?`,
			userID, draftID).Scan(&cur); err != nil {
			return "", err // sql.ErrNoRows -> deleted
		}
		return cur, ErrConflict
	}
	return now, nil
}

func (s *Store) DeleteDraft(userID, draftID string) (bool, error) {
	res, err := s.db.Exec(`DELETE FROM draft WHERE user_id=? AND draft_id=?`, userID, draftID)
	if err != nil {
		return false, err
	}
	n, _ := res.RowsAffected()
	return n > 0, nil
}

func bodyFormat(b Body) string {
	if b.Format == "html" {
		return "html"
	}
	return "text"
}

// --- handlers ---

type draftReq struct {
	AccountID     *string   `json:"account_id"`
	InReplyTo     *string   `json:"in_reply_to"`
	ReplyType     *string   `json:"reply_type"`
	To            []Address `json:"to"`
	CC            []Address `json:"cc"`
	Subject       string    `json:"subject"`
	Body          Body      `json:"body"`
	BaseUpdatedAt string    `json:"base_updated_at"`
}

func (r draftReq) toDraft() Draft {
	return Draft{AccountID: r.AccountID, InReplyTo: r.InReplyTo, ReplyType: r.ReplyType,
		To: r.To, CC: r.CC, Subject: r.Subject, Body: r.Body}
}

var (
	validReplyType  = map[string]bool{"reply": true, "reply_all": true, "forward": true}
	validBodyFormat = map[string]bool{"text": true, "html": true}
)

// validateDraftReq rejects enum values the SQLite CHECK constraints would otherwise turn
// into a 500 (reply_type) or silently coerce (body.format) — surfacing them as a proper
// 422 VALIDATION_FAILED instead (NR0011 G1). Returns nil when valid.
func validateDraftReq(req draftReq) *apperr.AppError {
	if req.ReplyType != nil && *req.ReplyType != "" && !validReplyType[*req.ReplyType] {
		return apperr.ValidationFailed.WithDetails(map[string]any{"field": "reply_type", "value": *req.ReplyType})
	}
	if req.Body.Format != "" && !validBodyFormat[req.Body.Format] {
		return apperr.ValidationFailed.WithDetails(map[string]any{"field": "body.format", "value": req.Body.Format})
	}
	return nil
}

func (h *Handlers) CreateDraft(w http.ResponseWriter, r *http.Request) {
	var req draftReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if verr := validateDraftReq(req); verr != nil {
		httpx.Error(w, verr)
		return
	}
	d, err := h.store.CreateDraft(uid(r), req.toDraft(), h.now())
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusCreated, map[string]any{"draft_id": d.DraftID, "updated_at": d.UpdatedAt})
}

func (h *Handlers) GetDraft(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetDraft(uid(r), chi.URLParam(r, "id"))
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, apperr.MailNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, d)
}

func (h *Handlers) UpdateDraft(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req draftReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.BaseUpdatedAt == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "base_updated_at"}))
		return
	}
	if verr := validateDraftReq(req); verr != nil {
		httpx.Error(w, verr)
		return
	}
	updated, err := h.store.UpdateDraft(uid(r), id, req.toDraft(), req.BaseUpdatedAt, h.now())
	switch {
	case errors.Is(err, sql.ErrNoRows):
		httpx.Error(w, apperr.MailNotFound)
		return
	case errors.Is(err, ErrConflict):
		httpx.Error(w, apperr.DraftConflict.WithDetails(map[string]any{
			"draft_id": id, "server_updated_at": updated}))
		return
	case err != nil:
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"draft_id": id, "updated_at": updated})
}

func (h *Handlers) DeleteDraft(w http.ResponseWriter, r *http.Request) {
	ok, err := h.store.DeleteDraft(uid(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if !ok {
		httpx.Error(w, apperr.MailNotFound)
		return
	}
	httpx.NoContent(w)
}
