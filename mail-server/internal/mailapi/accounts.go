package mailapi

import (
	"database/sql"
	"errors"
	"fmt"
	"html"
	"net/http"
	"net/url"
	"strings"

	"github.com/go-chi/chi/v5"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/idgen"
)

// Account — wire shape (P0007 §3.6).
type Account struct {
	AccountID   string `json:"account_id"`
	Email       string `json:"email"`
	Provider    string `json:"provider"`
	Status      string `json:"status"`
	ConnectedAt string `json:"connected_at"`
}

// primaryAccount carries the fields the send/sync paths need, incl. the From name.
type primaryAccount struct {
	AccountID   string
	Email       string
	Provider    string
	OAuthRef    string
	DisplayName string
}

var validProvider = map[string]bool{"gmail": true, "outlook": true, "imap": true}

func (s *Store) ListAccounts(userID string) ([]Account, error) {
	rows, err := s.db.Query(
		`SELECT account_id,email,provider,status,connected_at FROM mail_account WHERE user_id=? ORDER BY connected_at ASC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Account{}
	for rows.Next() {
		var a Account
		if err := rows.Scan(&a.AccountID, &a.Email, &a.Provider, &a.Status, &a.ConnectedAt); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// InsertAccount creates a connected account + its sync_state row in one transaction.
// The credential is held outside SQL keyed by oauth_ref (DB0008 §2.3).
func (s *Store) InsertAccount(userID, email, provider, oauthRef, now string) (Account, error) {
	a := Account{AccountID: idgen.New(idgen.Account), Email: email, Provider: provider,
		Status: "connected", ConnectedAt: now}
	tx, err := s.db.Begin()
	if err != nil {
		return Account{}, err
	}
	defer tx.Rollback() //nolint:errcheck
	if _, err := tx.Exec(
		`INSERT INTO mail_account(account_id,user_id,email,provider,status,oauth_ref,connected_at)
		 VALUES(?,?,?,?, 'connected', ?, ?)`,
		a.AccountID, userID, email, provider, nullStr(oauthRef), now); err != nil {
		if isUnique(err) {
			return Account{}, ErrDuplicate
		}
		return Account{}, err
	}
	if _, err := tx.Exec(`INSERT INTO sync_state(account_id,state) VALUES(?, 'idle')`, a.AccountID); err != nil {
		return Account{}, err
	}
	if err := tx.Commit(); err != nil {
		return Account{}, err
	}
	return a, nil
}

// DeleteAccount removes the account (CASCADE clears mail/sync_state) and returns the
// freed oauth_ref so the caller can purge the secret. ok=false if not owned.
func (s *Store) DeleteAccount(userID, accountID string) (oauthRef string, ok bool, err error) {
	var ref sql.NullString
	err = s.db.QueryRow(`SELECT oauth_ref FROM mail_account WHERE user_id=? AND account_id=?`,
		userID, accountID).Scan(&ref)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	if _, err := s.db.Exec(`DELETE FROM mail_account WHERE user_id=? AND account_id=?`, userID, accountID); err != nil {
		return "", false, err
	}
	return ref.String, true, nil
}

// PrimaryAccount returns the user's first connected account (for outbound From) joined
// with their display name. sql.ErrNoRows when none is connected.
func (s *Store) PrimaryAccount(userID string) (primaryAccount, error) {
	var (
		p    primaryAccount
		ref  sql.NullString
		name sql.NullString
	)
	err := s.db.QueryRow(
		`SELECT a.account_id,a.email,a.provider,a.oauth_ref,u.display_name
		 FROM mail_account a JOIN app_user u ON a.user_id=u.user_id
		 WHERE a.user_id=? AND a.status='connected'
		 ORDER BY a.connected_at ASC LIMIT 1`, userID).
		Scan(&p.AccountID, &p.Email, &p.Provider, &ref, &name)
	if err != nil {
		return primaryAccount{}, err
	}
	p.OAuthRef = ref.String
	p.DisplayName = name.String
	return p, nil
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// --- handlers ---

// oauthAuthProvider whitelists the providers that support the OAuth consent flow
// (imap is password-based, not OAuth, so it has no authorization URL).
var oauthAuthProvider = map[string]bool{"gmail": true, "outlook": true}

// AuthorizeURL implements GET /accounts/oauth/authorize?provider=gmail (NR0003 gap A):
// it returns the provider consent URL the client opens in a browser to obtain the auth
// code, plus an anti-CSRF state value the client echoes/verifies on the redirect. This is
// the front-channel half of the code grant; the back-channel exchange stays at POST
// /accounts. The URL carries the IMAP scope + offline access so the minted token can drive
// XOAUTH2 sync and yields a refresh_token.
func (h *Handlers) AuthorizeURL(w http.ResponseWriter, r *http.Request) {
	provider := r.URL.Query().Get("provider")
	if !oauthAuthProvider[provider] {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "provider"}))
		return
	}
	authorizer, ok := h.deps.OAuth.(OAuthAuthorizer)
	if h.deps.OAuth == nil || !ok {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "oauth not configured"}))
		return
	}
	state := idgen.New("st_")
	authURL, err := authorizer.AuthCodeURL(provider, state)
	if err != nil {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "oauth not configured"}))
		return
	}
	// Bind the state to the user that started the flow + the provider, so the unauthenticated
	// callback can recover both from the redirect (server.0005 NR0009 gap A).
	h.deps.States.Put(state, uid(r), provider)
	httpx.OK(w, http.StatusOK, map[string]any{"auth_url": authURL, "state": state})
}

// callbackHTML is the self-contained page rendered when no OAuthReturnURL is configured.
// %s placeholders: <title>, <h2>, body message. No external assets so an in-app browser /
// custom tab can detect completion and close without loading anything.
const callbackHTML = `<!doctype html><html lang="ko"><head><meta charset="utf-8">` +
	`<meta name="viewport" content="width=device-width,initial-scale=1"><title>%s</title></head>` +
	`<body style="font-family:sans-serif;text-align:center;padding:3rem"><h2>%s</h2><p>%s</p></body></html>`

// OAuthCallback implements GET /accounts/oauth/callback?code=&state=&error= — the
// front-channel "closer" that was missing (server.0005 NR0009 gap A). The provider redirects
// the user's BROWSER here after consent, so the request is UNAUTHENTICATED: the user +
// provider are recovered from the one-time `state` issued by AuthorizeURL, not a JWT. The
// back-channel code exchange + InsertAccount run server-side so the raw auth code never
// reaches the user (the divergence CH0007 complained about). The legacy POST /accounts paste
// path is left intact for now; this endpoint is what lets the client drop the code field.
func (h *Handlers) OAuthCallback(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	if provErr := q.Get("error"); provErr != "" {
		h.writeCallbackResult(w, "", provErr) // user denied consent / provider error
		return
	}
	code, state := q.Get("code"), q.Get("state")
	if code == "" || state == "" {
		h.writeCallbackResult(w, "", "invalid_request")
		return
	}
	userID, provider, ok := h.deps.States.Take(state)
	if !ok {
		// unknown / expired / replayed state -> reject (CSRF + replay guard).
		h.writeCallbackResult(w, "", "invalid_state")
		return
	}
	if h.deps.OAuth == nil {
		h.writeCallbackResult(w, "", "oauth not configured")
		return
	}
	email, cred, err := h.deps.OAuth.Exchange(provider, code)
	if err != nil {
		h.writeCallbackResult(w, "", "oauth exchange failed")
		return
	}
	oauthRef := idgen.New("sec_")
	if h.deps.Secrets != nil {
		h.deps.Secrets.Put(oauthRef, cred)
	}
	_, err = h.store.InsertAccount(userID, email, provider, oauthRef, h.now())
	if errors.Is(err, ErrDuplicate) {
		// Already connected for this user -> idempotent reconnect, success from the user's POV.
		if h.deps.Secrets != nil {
			h.deps.Secrets.Delete(oauthRef)
		}
		h.writeCallbackResult(w, email, "")
		return
	}
	if err != nil {
		if h.deps.Secrets != nil {
			h.deps.Secrets.Delete(oauthRef)
		}
		h.writeCallbackResult(w, "", "internal")
		return
	}
	h.writeCallbackResult(w, email, "")
}

// writeCallbackResult ends the browser leg of the OAuth flow: redirect to the configured app
// return URL when set (carrying account_connected/email or error), else render the
// self-contained page. This is a browser-facing response, so it does NOT use the JSON API
// envelope (httpx.OK/Error).
func (h *Handlers) writeCallbackResult(w http.ResponseWriter, email, errReason string) {
	if ret := h.deps.OAuthReturnURL; ret != "" {
		sep := "?"
		if strings.Contains(ret, "?") {
			sep = "&"
		}
		loc := ret + sep + "account_connected=true&email=" + url.QueryEscape(email)
		if errReason != "" {
			loc = ret + sep + "error=" + url.QueryEscape(errReason)
		}
		w.Header().Set("Location", loc)
		w.WriteHeader(http.StatusFound)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	title, msg, status := "연결 완료", "이 창을 닫고 앱으로 돌아가세요.", http.StatusOK
	if errReason == "" && email != "" {
		msg = "계정 " + html.EscapeString(email) + " 연결이 완료되었습니다. 이 창을 닫아도 됩니다."
	}
	if errReason != "" {
		title, msg, status = "연결 실패", "오류: "+html.EscapeString(errReason), http.StatusBadRequest
	}
	w.WriteHeader(status)
	fmt.Fprintf(w, callbackHTML, title, title, msg)
}

func (h *Handlers) ListAccounts(w http.ResponseWriter, r *http.Request) {
	as, err := h.store.ListAccounts(uid(r))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusOK, as)
}

type accountReq struct {
	Provider string `json:"provider"`
	AuthCode string `json:"auth_code"`
}

// CreateAccount implements POST /accounts (P0007 §7.14): exchange the OAuth auth code
// with the provider, persist the credential outside SQL, and connect the account.
func (h *Handlers) CreateAccount(w http.ResponseWriter, r *http.Request) {
	var req accountReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if !validProvider[req.Provider] {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "provider"}))
		return
	}
	if req.AuthCode == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "auth_code"}))
		return
	}
	if h.deps.OAuth == nil {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "oauth not configured"}))
		return
	}
	email, cred, err := h.deps.OAuth.Exchange(req.Provider, req.AuthCode)
	if err != nil {
		httpx.Error(w, apperr.UpstreamUnavailable.WithDetails(map[string]any{"reason": "oauth exchange failed"}))
		return
	}
	oauthRef := idgen.New("sec_")
	if h.deps.Secrets != nil {
		h.deps.Secrets.Put(oauthRef, cred)
	}
	a, err := h.store.InsertAccount(uid(r), email, req.Provider, oauthRef, h.now())
	if errors.Is(err, ErrDuplicate) {
		if h.deps.Secrets != nil {
			h.deps.Secrets.Delete(oauthRef)
		}
		httpx.Error(w, apperr.AccountConflict.WithDetails(map[string]any{"email": email}))
		return
	}
	if err != nil {
		if h.deps.Secrets != nil {
			h.deps.Secrets.Delete(oauthRef)
		}
		httpx.Error(w, apperr.Internal)
		return
	}
	httpx.OK(w, http.StatusCreated, a)
}

func (h *Handlers) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	ref, ok, err := h.store.DeleteAccount(uid(r), chi.URLParam(r, "id"))
	if err != nil {
		httpx.Error(w, apperr.Internal)
		return
	}
	if !ok {
		httpx.Error(w, apperr.Forbidden.WithDetails(map[string]any{"reason": "account not found"}))
		return
	}
	if ref != "" && h.deps.Secrets != nil {
		h.deps.Secrets.Delete(ref)
	}
	httpx.NoContent(w)
}
