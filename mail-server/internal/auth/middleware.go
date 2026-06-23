package auth

import (
	"context"
	"net/http"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/httpx"
)

type ctxKey int

const userIDKey ctxKey = 0

// RequireAuth is middleware that enforces a valid Bearer access token and injects
// the resolved user id into the request context. On failure it writes the P0007
// error envelope (TOKEN_EXPIRED -> client refresh, TOKEN_INVALID -> re-login).
func (h *Handlers) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok, ok := bearerToken(r)
		if !ok {
			httpx.Error(w, apperr.TokenInvalid)
			return
		}
		userID, err := h.svc.AuthenticateAccess(tok)
		if err != nil {
			httpx.Error(w, err)
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// UserID extracts the authenticated user id injected by RequireAuth.
func UserID(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(userIDKey).(string)
	return v, ok
}
