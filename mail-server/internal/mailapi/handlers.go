package mailapi

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/httpx"
)

// Handlers exposes the mail API endpoints. All require auth; the user id is taken
// from the request context (auth.RequireAuth). deps carries the external-service
// ports (Phase 2: Sender/ChangeSource/OAuth/SecretStore/Blob).
type Handlers struct {
	store *Store
	deps  Deps
}

// NewHandlers builds the mail handlers. deps may carry nil ports; the corresponding
// endpoints degrade to the appropriate upstream/send error (see send/sync). A nil
// States port is filled with an in-memory store so the OAuth front-channel callback
// works without explicit wiring (server.0005 NR0009 gap A).
func NewHandlers(store *Store, deps Deps) *Handlers {
	if deps.States == nil {
		deps.States = NewMemStateStore()
	}
	return &Handlers{store: store, deps: deps}
}

// now returns the injected clock as an ISO-8601 UTC second-truncated string.
func (h *Handlers) now() string { return h.deps.now().UTC().Truncate(time.Second).Format(tsLayout) }

// sleep is the retry backoff sleeper. Real time in prod; the default policy's small
// attempt count keeps latency bounded. Tests inject a no-op via a custom policy.
func (h *Handlers) sleep(d time.Duration) { time.Sleep(d) }

// MountPublic wires the routes that must NOT require auth. The OAuth callback is a browser
// redirect from the provider after consent and carries no JWT — it authenticates via the
// one-time `state` issued by AuthorizeURL instead (server.0005 NR0009 gap A).
func (h *Handlers) MountPublic(r chi.Router) {
	r.Get("/accounts/oauth/callback", h.OAuthCallback)
}

// Mount wires the mail routes onto an already-authenticated chi router.
func (h *Handlers) Mount(r chi.Router) {
	// management(M) — text·text
	r.Get("/labels", h.ListLabels)
	r.Post("/labels", h.CreateLabel)
	r.Patch("/labels/{id}", h.UpdateLabel)
	r.Delete("/labels/{id}", h.DeleteLabel)

	r.Get("/settings/display", h.GetDisplay)
	r.Patch("/settings/display", h.PatchDisplay)
	r.Get("/settings/sync", h.GetSync)
	r.Patch("/settings/sync", h.PatchSync)

	// text(C) — textpath + text(D)
	r.Get("/mails", h.ListMails)
	r.Get("/mails/{id}", h.GetMail)
	r.Patch("/mails/{id}", h.PatchMail)
	r.Post("/mails", h.SendMail)

	// compose(D) — Draft + text
	r.Get("/drafts/{id}", h.GetDraft)
	r.Post("/drafts", h.CreateDraft)
	r.Put("/drafts/{id}", h.UpdateDraft)
	r.Delete("/drafts/{id}", h.DeleteDraft)
	r.Post("/attachments", h.UploadAttachment)
	r.Get("/attachments/{id}", h.DownloadAttachment)

	// management(M) — account
	r.Get("/accounts/oauth/authorize", h.AuthorizeURL)
	r.Get("/accounts", h.ListAccounts)
	r.Post("/accounts", h.CreateAccount)
	r.Delete("/accounts/{id}", h.DeleteAccount)

	// sync(F)
	r.Get("/sync/status", h.SyncStatus)
	r.Post("/sync", h.TriggerSync)
}

func itoa(i int) string { return strconv.Itoa(i) }

func uid(r *http.Request) string {
	v, _ := auth.UserID(r.Context())
	return v
}

// --- labels ---

func (h *Handlers) ListLabels(w http.ResponseWriter, r *http.Request) {
	ls, err := h.store.ListLabels(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, ls)
}

type labelReq struct {
	Name  string  `json:"name"`
	Color *string `json:"color"`
}

func (h *Handlers) CreateLabel(w http.ResponseWriter, r *http.Request) {
	var req labelReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.Name == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "name"}))
		return
	}
	l, err := h.store.CreateLabel(uid(r), req.Name, req.Color)
	if errors.Is(err, ErrDuplicate) {
		httpx.Error(w, apperr.LabelDuplicate.WithDetails(map[string]any{"name": req.Name}))
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusCreated, l)
}

type labelPatchReq struct {
	Name  *string `json:"name"`
	Color *string `json:"color"`
}

func (h *Handlers) UpdateLabel(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, err := h.store.labelType(uid(r), id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, apperr.LabelNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if t == "system" {
		httpx.Error(w, apperr.Forbidden.WithDetails(map[string]any{"reason": "system label is immutable"}))
		return
	}
	var req labelPatchReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.Name != nil && *req.Name == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "name"}))
		return
	}
	if err := h.store.UpdateLabel(uid(r), id, req.Name, req.Color); errors.Is(err, ErrDuplicate) {
		httpx.Error(w, apperr.LabelDuplicate)
		return
	} else if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	ls, _ := h.store.ListLabels(uid(r))
	for _, l := range ls {
		if l.LabelID == id {
			httpx.OK(w, http.StatusOK, l)
			return
		}
	}
	httpx.OK(w, http.StatusOK, map[string]any{"label_id": id})
}

func (h *Handlers) DeleteLabel(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	t, err := h.store.labelType(uid(r), id)
	if errors.Is(err, sql.ErrNoRows) {
		httpx.Error(w, apperr.LabelNotFound)
		return
	}
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if t == "system" {
		httpx.Error(w, apperr.Forbidden.WithDetails(map[string]any{"reason": "system label is immutable"}))
		return
	}
	if err := h.store.DeleteLabel(uid(r), id); err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.NoContent(w)
}

// --- settings ---

var (
	validSort     = map[string]bool{"date_desc": true, "date_asc": true}
	validLanguage = map[string]bool{"ko": true, "ja": true, "en": true}
	validDensity  = map[string]bool{"comfortable": true, "compact": true}
)

func (h *Handlers) GetDisplay(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetDisplay(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, d)
}

type displayPatchReq struct {
	SortOrder *string `json:"sort_order"`
	Language  *string `json:"language"`
	Density   *string `json:"density"`
}

func (h *Handlers) PatchDisplay(w http.ResponseWriter, r *http.Request) {
	cur, err := h.store.GetDisplay(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	var req displayPatchReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.SortOrder != nil {
		if !validSort[*req.SortOrder] {
			httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "sort_order"}))
			return
		}
		cur.SortOrder = *req.SortOrder
	}
	if req.Language != nil {
		if !validLanguage[*req.Language] {
			httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "language"}))
			return
		}
		cur.Language = *req.Language
	}
	if req.Density != nil {
		if !validDensity[*req.Density] {
			httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "density"}))
			return
		}
		cur.Density = *req.Density
	}
	if err := h.store.UpdateDisplay(uid(r), cur); err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, cur)
}

func (h *Handlers) GetSync(w http.ResponseWriter, r *http.Request) {
	iv, err := h.store.GetSyncInterval(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"sync_interval_min": iv})
}

type syncPatchReq struct {
	SyncIntervalMin *int `json:"sync_interval_min"`
}

func (h *Handlers) PatchSync(w http.ResponseWriter, r *http.Request) {
	var req syncPatchReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.SyncIntervalMin != nil && *req.SyncIntervalMin <= 0 {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "sync_interval_min"}))
		return
	}
	if err := h.store.UpdateSyncInterval(uid(r), req.SyncIntervalMin); err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"sync_interval_min": req.SyncIntervalMin})
}

// --- mail read-path ---

const (
	listLimitDefault = 25
	listLimitMax     = 100
)

func (h *Handlers) ListMails(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	limit := listLimitDefault
	if v := q.Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			limit = n
		}
	}
	if limit > listLimitMax {
		limit = listLimitMax
	}
	if limit < 1 {
		limit = 1
	}
	cur, err := decodeCursor(q.Get("cursor"))
	if err != nil {
		httpx.Error(w, err)
		return
	}
	f := listFilter{
		Label:  q.Get("label"),
		Q:      q.Get("q"),
		Unread: q.Get("unread") == "true",
		Limit:  limit,
		Cursor: cur,
	}
	items, hasMore, err := h.store.ListMails(uid(r), f)
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	meta := PageMeta{HasMore: hasMore, Count: len(items)}
	if hasMore && len(items) > 0 {
		last := items[len(items)-1]
		nc := encodeCursor(last.ReceivedAt, last.MailID)
		meta.NextCursor = &nc
	}
	httpx.OKMeta(w, http.StatusOK, items, meta)
}

func (h *Handlers) GetMail(w http.ResponseWriter, r *http.Request) {
	d, err := h.store.GetMailDetail(uid(r), chi.URLParam(r, "id"))
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

type mailPatchReq struct {
	IsRead       *bool    `json:"is_read"`
	LabelsAdd    []string `json:"labels_add"`
	LabelsRemove []string `json:"labels_remove"`
}

func (h *Handlers) PatchMail(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	var req mailPatchReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	err := h.store.PatchMail(uid(r), id, req.IsRead, req.LabelsAdd, req.LabelsRemove)
	switch {
	case errors.Is(err, sql.ErrNoRows):
		httpx.Error(w, apperr.MailNotFound)
		return
	case errors.Is(err, ErrLabelMissing):
		httpx.Error(w, apperr.LabelNotFound)
		return
	case err != nil:
		httpx.Error(w, apperr.Internal)
		return
	}
	labels, _ := h.store.CurrentLabels(id)
	resp := map[string]any{"mail_id": id, "labels": labels}
	if req.IsRead != nil {
		resp["is_read"] = *req.IsRead
	}
	httpx.OK(w, http.StatusOK, resp)
}
