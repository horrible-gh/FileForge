package auth_test

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/apperr"
	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/db"
)

func newSvc(t *testing.T) (*auth.Service, *auth.Store) {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "test.db")
	conn, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	store := auth.NewStore(conn)
	return auth.NewService(store, []byte("test-secret"), 900*time.Second, 30*24*time.Hour), store
}

func codeOf(err error) string {
	var ae *apperr.AppError
	if errors.As(err, &ae) {
		return ae.Code
	}
	return "<nil>"
}

func TestAuthFlow(t *testing.T) {
	svc, store := newSvc(t)

	user, err := store.CreateUser("user@example.com", "s3cr3t-pass", "홍길동")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}

	// wrong password -> AUTH_INVALID_CREDENTIALS
	if _, err := svc.Login("user@example.com", "wrong", "1.2.3.4"); codeOf(err) != "AUTH_INVALID_CREDENTIALS" {
		t.Fatalf("wrong pw: want AUTH_INVALID_CREDENTIALS, got %v", err)
	}
	// unknown account -> same code (timing equalized via dummy verify)
	if _, err := svc.Login("nobody@example.com", "x", "1.2.3.4"); codeOf(err) != "AUTH_INVALID_CREDENTIALS" {
		t.Fatalf("unknown acct: want AUTH_INVALID_CREDENTIALS, got %v", err)
	}

	// correct login
	lr, err := svc.Login("user@example.com", "s3cr3t-pass", "1.2.3.4")
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if lr.TokenType != "Bearer" || lr.ExpiresIn != 900 || lr.User.UserID != user.ID {
		t.Fatalf("unexpected login result: %+v", lr)
	}

	// session with the access token
	sr, err := svc.Session(lr.AccessToken)
	if err != nil || !sr.Authenticated || sr.User.Email != "user@example.com" {
		t.Fatalf("session: err=%v res=%+v", err, sr)
	}

	// refresh rotates -> new tokens, old refresh now revoked
	rr, err := svc.Refresh(lr.RefreshToken)
	if err != nil {
		t.Fatalf("refresh: %v", err)
	}
	if rr.AccessToken == "" || rr.RefreshToken == "" || rr.RefreshToken == lr.RefreshToken {
		t.Fatalf("refresh did not rotate: %+v", rr)
	}

	// reuse of the old (revoked) refresh -> TOKEN_INVALID + chain revoke
	if _, err := svc.Refresh(lr.RefreshToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("reuse old refresh: want TOKEN_INVALID, got %v", err)
	}
	// chain revoke means even the freshly issued refresh is now dead
	if _, err := svc.Refresh(rr.RefreshToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("post-chain-revoke refresh: want TOKEN_INVALID, got %v", err)
	}

	// logout is idempotent and never errors
	if err := svc.Logout(rr.RefreshToken); err != nil {
		t.Fatalf("logout: %v", err)
	}
	if err := svc.Logout("rt_does_not_exist"); err != nil {
		t.Fatalf("logout unknown: %v", err)
	}
}

// NR0011 B6: refresh rotation is atomic + conditional. RotateRefresh on a token that was
// already rotated (revoked) must affect 0 rows and report ok=false, so two concurrent
// refreshes can never both fork a chain from one token.
func TestRotateRefreshIsConditional(t *testing.T) {
	_, store := newSvc(t)
	user, err := store.CreateUser("rot@example.com", "pw", "")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	now := time.Now().UTC().Truncate(time.Second)
	old := auth.RefreshRow{
		TokenID: "rt_old", UserID: user.ID, TokenHash: "h_old",
		IssuedAt: now, ExpiresAt: now.Add(time.Hour),
	}
	if err := store.InsertRefresh(old); err != nil {
		t.Fatalf("InsertRefresh: %v", err)
	}

	next1 := auth.RefreshRow{TokenID: "rt_new1", UserID: user.ID, TokenHash: "h_new1",
		IssuedAt: now, ExpiresAt: now.Add(time.Hour), RotatedFrom: &old.TokenID}
	ok, err := store.RotateRefresh(old.TokenID, next1, now)
	if err != nil || !ok {
		t.Fatalf("first rotation must succeed: ok=%v err=%v", ok, err)
	}

	// a second rotation from the same (now revoked) token must be rejected
	next2 := auth.RefreshRow{TokenID: "rt_new2", UserID: user.ID, TokenHash: "h_new2",
		IssuedAt: now, ExpiresAt: now.Add(time.Hour), RotatedFrom: &old.TokenID}
	ok, err = store.RotateRefresh(old.TokenID, next2, now)
	if err != nil {
		t.Fatalf("second rotation err: %v", err)
	}
	if ok {
		t.Fatal("second rotation from an already-rotated token must report ok=false")
	}
	// and the rejected successor must NOT have been inserted
	if _, err := store.FindRefreshByHash("h_new2"); !auth.IsNotFound(err) {
		t.Fatalf("rejected successor must not be persisted: %v", err)
	}
}

func TestSessionInvalidToken(t *testing.T) {
	svc, _ := newSvc(t)
	if _, err := svc.Session("garbage.token.value"); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("want TOKEN_INVALID, got %v", err)
	}
}

func TestLoginLockout(t *testing.T) {
	svc, store := newSvc(t)
	if _, err := store.CreateUser("lock@example.com", "pw", ""); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	for i := 0; i < 5; i++ {
		_, _ = svc.Login("lock@example.com", "bad", "9.9.9.9")
	}
	// even the correct password is now rejected (locked), concealed behind same code
	if _, err := svc.Login("lock@example.com", "pw", "9.9.9.9"); codeOf(err) != "AUTH_INVALID_CREDENTIALS" {
		t.Fatalf("locked: want AUTH_INVALID_CREDENTIALS, got %v", err)
	}
	// a different IP is not locked
	if _, err := svc.Login("lock@example.com", "pw", "8.8.8.8"); err != nil {
		t.Fatalf("other ip should succeed: %v", err)
	}
}
