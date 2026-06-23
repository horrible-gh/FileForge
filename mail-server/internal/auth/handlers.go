package auth

import (
	"net"
	"net/http"
	"strings"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
)

// Handlers adapts the auth Service to HTTP (P0007 §6.1 /auth/*).
type Handlers struct{ svc *Service }

func NewHandlers(svc *Service) *Handlers { return &Handlers{svc: svc} }

type loginReq struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// Login POST /auth/login (P0007 §2.3)
func (h *Handlers) Login(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.Email == "" || req.Password == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "email|password"}))
		return
	}
	res, err := h.svc.Login(req.Email, req.Password, clientIP(r))
	if err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, res)
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

// Refresh POST /auth/refresh (P0007 §2.5)
func (h *Handlers) Refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	if req.RefreshToken == "" {
		httpx.Error(w, apperr.ValidationFailed.WithDetails(map[string]any{"field": "refresh_token"}))
		return
	}
	res, err := h.svc.Refresh(req.RefreshToken)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, res)
}

// Logout POST /auth/logout (P0007 §2.7) — always 204.
func (h *Handlers) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	_ = h.svc.Logout(req.RefreshToken)
	httpx.NoContent(w)
}

// Session GET /auth/session (P0007 §2.8)
func (h *Handlers) Session(w http.ResponseWriter, r *http.Request) {
	tok, ok := bearerToken(r)
	if !ok {
		httpx.Error(w, apperr.TokenInvalid)
		return
	}
	res, err := h.svc.Session(tok)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, res)
}

func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const p = "Bearer "
	if len(h) <= len(p) || !strings.EqualFold(h[:len(p)], p) {
		return "", false
	}
	return strings.TrimSpace(h[len(p):]), true
}

// clientIP returns the request peer address for the login-lockout key. It deliberately
// does NOT read X-Forwarded-For (NR0011 S3): trusting client-supplied XFF lets an
// attacker rotate it to evade the per-IP lockout. When the deployment sits behind a
// trusted proxy, enable cfg.TrustProxy so chi's RealIP middleware sets RemoteAddr from
// XFF before this runs; here we always read the (now-trustworthy) RemoteAddr.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
