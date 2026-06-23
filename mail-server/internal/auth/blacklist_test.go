package auth_test

import (
	"testing"

	"mailanchor/serverd/internal/sharedstore"
)

// R0001 stage 3: logout must revoke a still-valid access token in real time. Before
// BlacklistAccess the token authenticates; after, the same token is rejected even though
// it has not expired.
func TestAccessTokenBlacklistRevokesLiveToken(t *testing.T) {
	svc, store := newSvc(t)
	user, err := store.CreateUser("bl@example.com", "s3cr3t-pass", "BL")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	lr, err := svc.Login("bl@example.com", "s3cr3t-pass", "1.2.3.4")
	if err != nil {
		t.Fatalf("login: %v", err)
	}

	// token works before logout
	if uid, err := svc.AuthenticateAccess(lr.AccessToken); err != nil || uid != user.ID {
		t.Fatalf("pre-logout auth: uid=%q err=%v", uid, err)
	}

	// blacklist (what the logout handler calls) -> token now rejected as TOKEN_INVALID
	svc.BlacklistAccess(lr.AccessToken)
	if _, err := svc.AuthenticateAccess(lr.AccessToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("post-blacklist auth: want TOKEN_INVALID, got %v", err)
	}
	if _, err := svc.Session(lr.AccessToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("post-blacklist session: want TOKEN_INVALID, got %v", err)
	}
}

// A blacklist entry must be scoped to the one token: a second login's token is unaffected.
func TestBlacklistIsPerToken(t *testing.T) {
	svc, store := newSvc(t)
	if _, err := store.CreateUser("bl2@example.com", "s3cr3t-pass", "BL2"); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	a, _ := svc.Login("bl2@example.com", "s3cr3t-pass", "1.2.3.4")
	b, _ := svc.Login("bl2@example.com", "s3cr3t-pass", "1.2.3.4")

	svc.BlacklistAccess(a.AccessToken)
	if _, err := svc.AuthenticateAccess(a.AccessToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("token a should be revoked, got %v", err)
	}
	if _, err := svc.AuthenticateAccess(b.AccessToken); err != nil {
		t.Fatalf("token b must still work, got %v", err)
	}
}

// The Redis-backed store satisfies the same revocation behaviour when injected.
func TestBlacklistWithInjectedStore(t *testing.T) {
	svc, store := newSvc(t)
	svc.WithSharedStore(sharedstore.NewMemStore()) // explicit injection path
	if _, err := store.CreateUser("bl3@example.com", "s3cr3t-pass", "BL3"); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	lr, _ := svc.Login("bl3@example.com", "s3cr3t-pass", "1.2.3.4")
	svc.BlacklistAccess(lr.AccessToken)
	if _, err := svc.AuthenticateAccess(lr.AccessToken); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("want TOKEN_INVALID after blacklist, got %v", err)
	}
}
