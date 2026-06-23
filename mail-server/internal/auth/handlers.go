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

// Login POST /auth/login (P0007 §2.3). 2FA-aware (R0001 stage 4): the optional second factor
// rides in the X-TOTP-Code header (mirrors MailAnchor's login). When the account has 2FA but
// no code was supplied, the response is 200 {"requires_2fa": true} and the client resubmits.
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
	totpCode := strings.TrimSpace(r.Header.Get("X-TOTP-Code"))
	res, requires2FA, err := h.svc.LoginWithTOTP(req.Email, req.Password, totpCode, clientIP(r))
	if err != nil {
		httpx.Error(w, err)
		return
	}
	if requires2FA {
		httpx.OK(w, http.StatusOK, map[string]any{"requires_2fa": true, "message": "2FA code required"})
		return
	}
	httpx.OK(w, http.StatusOK, res)
}

// totpCodeReq is the body for the 2FA endpoints that take a 6-digit TOTP or recovery code.
type totpCodeReq struct {
	Code string `json:"code"`
}

func (h *Handlers) totpCode(r *http.Request) (string, error) {
	var req totpCodeReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		return "", err
	}
	code := strings.TrimSpace(req.Code)
	if code == "" {
		return "", apperr.ValidationFailed.WithDetails(map[string]any{"field": "code"})
	}
	return code, nil
}

// TOTPStatus GET /auth/2fa/status — whether the caller has activated 2FA.
func (h *Handlers) TOTPStatus(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserID(r.Context())
	httpx.OK(w, http.StatusOK, map[string]any{"enabled": h.svc.TOTPStatus(uid)})
}

// TOTPSetup POST /auth/2fa/setup — enroll a new secret; returns secret/otpauth_url/recovery.
func (h *Handlers) TOTPSetup(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserID(r.Context())
	res, err := h.svc.TOTPSetup(uid)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, res)
}

// TOTPActivate POST /auth/2fa/activate — verify the first code and activate 2FA.
func (h *Handlers) TOTPActivate(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserID(r.Context())
	code, err := h.totpCode(r)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	if err := h.svc.TOTPActivate(uid, code); err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"success": true})
}

// TOTPDisable POST /auth/2fa/disable — verify a current code and remove 2FA.
func (h *Handlers) TOTPDisable(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserID(r.Context())
	code, err := h.totpCode(r)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	if err := h.svc.TOTPDisable(uid, code); err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"success": true})
}

// TOTPRegenerateRecovery POST /auth/2fa/regenerate-recovery — verify a current code and issue
// a fresh recovery-code set (invalidating the previous one).
func (h *Handlers) TOTPRegenerateRecovery(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserID(r.Context())
	code, err := h.totpCode(r)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	codes, err := h.svc.TOTPRegenerateRecovery(uid, code)
	if err != nil {
		httpx.Error(w, err)
		return
	}
	httpx.OK(w, http.StatusOK, map[string]any{"recovery_codes": codes})
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

// Logout POST /auth/logout (P0007 §2.7) — always 204. Revokes the refresh token and, when
// the request carries a Bearer access token, blacklists it so it is rejected immediately
// rather than living until its natural expiry (R0001 stage 3 token blacklist).
func (h *Handlers) Logout(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.Error(w, err)
		return
	}
	_ = h.svc.Logout(req.RefreshToken)
	if tok, ok := bearerToken(r); ok {
		h.svc.BlacklistAccess(tok)
	}
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
