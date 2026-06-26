package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// clockSkewAllowance — L0010 §1 (30s leeway on expiry checks).
const clockSkewAllowance = 30 * time.Second

// accessClaims is the stateless access token payload (L0010: access is not stored).
type accessClaims struct {
	jwt.RegisteredClaims
	Typ string `json:"typ"`
}

// IssueAccess mints a short-lived HS256 access token for the user.
func IssueAccess(secret []byte, userID string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := accessClaims{
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        newTokenID(),
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
		Typ: "access",
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(secret)
}

// newTokenID returns a random jti so two access tokens minted for the same user in the
// same second are still distinct byte strings. Without it their sha256 blacklist keys
// collide and revoking one logout-session would revoke every concurrent session (stage 3
// blacklist correctness; see TestBlacklistIsPerToken).
func newTokenID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("auth: entropy source failed: " + err.Error())
	}
	return hex.EncodeToString(b[:])
}

// accessResult distinguishes "expired" (refreshable) from "invalid" (re-login).
type accessVerifyError struct{ expired bool }

func (e *accessVerifyError) Error() string {
	if e.expired {
		return "access token expired"
	}
	return "access token invalid"
}

// IsExpired reports whether verification failed due to expiry (-> TOKEN_EXPIRED).
func IsExpired(err error) bool {
	var ve *accessVerifyError
	return errors.As(err, &ve) && ve.expired
}

// VerifyAccess validates signature + expiry (with clock-skew leeway) and returns the user id.
func VerifyAccess(secret []byte, token string) (string, error) {
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithLeeway(clockSkewAllowance),
	)
	var claims accessClaims
	_, err := parser.ParseWithClaims(token, &claims, func(t *jwt.Token) (any, error) {
		return secret, nil
	})
	if err != nil {
		return "", &accessVerifyError{expired: errors.Is(err, jwt.ErrTokenExpired)}
	}
	if claims.Typ != "access" {
		return "", &accessVerifyError{expired: false} // refresh used as access, etc.
	}
	return claims.Subject, nil
}

// newRefreshSecret returns an opaque rt_* refresh token and its sha256 hash.
// Only the hash is persisted (DB0008 invariant 9).
func newRefreshSecret() (raw, hash string) {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("auth: entropy source failed: " + err.Error())
	}
	raw = "rt_" + base64.RawURLEncoding.EncodeToString(b[:])
	return raw, hashRefresh(raw)
}

func hashRefresh(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

// tokenKey returns the sha256 hex of an access token, used as the blacklist key so the
// raw JWT is never stored in the shared store (DB0008 invariant 9 spirit; stage 3).
func tokenKey(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// accessExp returns the expiry of a self-issued (HS256) access token if it verifies.
// Used to bound the blacklist TTL to the token's remaining lifetime on logout. ok is
// false for tokens that do not verify locally (e.g. federated RS256) — the caller then
// falls back to a safe upper-bound TTL.
func accessExp(secret []byte, token string) (time.Time, bool) {
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{"HS256"}),
		jwt.WithLeeway(clockSkewAllowance),
	)
	var claims accessClaims
	if _, err := parser.ParseWithClaims(token, &claims, func(t *jwt.Token) (any, error) {
		return secret, nil
	}); err != nil {
		return time.Time{}, false
	}
	if claims.ExpiresAt == nil {
		return time.Time{}, false
	}
	return claims.ExpiresAt.Time, true
}
