package mailapi

import (
	"errors"
	"fmt"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/db"
)

// seedSyncAccount opens a fresh DB and seeds a user + connected account + a sync_state row
// in the given state with the given updated_at. Returns the store and account id.
func seedSyncAccount(t *testing.T, state, updatedAt string) (*Store, string) {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	u, err := auth.NewStore(conn).CreateUser("u@example.com", "pw", "U")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	acct := "acc_sync"
	if _, err := conn.Exec(
		`INSERT INTO mail_account(account_id,user_id,email,provider,status,connected_at)
		 VALUES(?,?,?, 'imap', 'connected', ?)`,
		acct, u.ID, "u@example.com", "2026-06-22T00:00:00Z"); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	if _, err := conn.Exec(
		`INSERT INTO sync_state(account_id,state,updated_at) VALUES(?,?,?)`,
		acct, state, updatedAt); err != nil {
		t.Fatalf("seed sync_state: %v", err)
	}
	return NewStore(conn), acct
}

// NR0011 B2: a 'syncing' row older than the stale window is reclaimable, so a crash that
// left the lock held cannot wedge the account forever.
func TestAcquireSyncLockReclaimsStale(t *testing.T) {
	st, acct := seedSyncAccount(t, "syncing", "2000-01-01T00:00:00Z")
	now := "2026-06-22T10:00:00Z"
	staleBefore := "2026-06-22T09:50:00Z"

	ok, err := st.acquireSyncLock(acct, now, staleBefore)
	if err != nil {
		t.Fatalf("acquire: %v", err)
	}
	if !ok {
		t.Fatal("stale 'syncing' lock must be reclaimable")
	}
	// after reclaim updated_at=now, so an immediate re-acquire (same window) is refused
	ok, err = st.acquireSyncLock(acct, now, staleBefore)
	if err != nil {
		t.Fatalf("re-acquire: %v", err)
	}
	if ok {
		t.Fatal("a fresh 'syncing' lock must NOT be reclaimable")
	}
}

// NR0011 B2: a 'syncing' lock within the window is held (no double-entry).
func TestAcquireSyncLockHeldWhenFresh(t *testing.T) {
	st, acct := seedSyncAccount(t, "syncing", "2026-06-22T09:59:30Z")
	ok, err := st.acquireSyncLock(acct, "2026-06-22T10:00:00Z", "2026-06-22T09:50:00Z")
	if err != nil {
		t.Fatalf("acquire: %v", err)
	}
	if ok {
		t.Fatal("fresh 'syncing' lock should not be acquirable")
	}
}

// NR0011 B2: an idle row is always acquirable.
func TestAcquireSyncLockFromIdle(t *testing.T) {
	st, acct := seedSyncAccount(t, "idle", "2026-06-22T09:59:30Z")
	ok, err := st.acquireSyncLock(acct, "2026-06-22T10:00:00Z", "2026-06-22T09:50:00Z")
	if err != nil {
		t.Fatalf("acquire: %v", err)
	}
	if !ok {
		t.Fatal("idle lock must be acquirable")
	}
}

// --- B3: partial-label merge must not wipe existing labels ---

// labelNamesFor returns the label names attached to a mail by its external_ref.
func labelNamesFor(t *testing.T, st *Store, externalRef string) []string {
	t.Helper()
	rows, err := st.db.Query(
		`SELECT l.name FROM label l
		 JOIN mail_label ml ON l.label_id=ml.label_id
		 JOIN mail m ON ml.mail_id=m.mail_id
		 WHERE m.external_ref=? ORDER BY l.name`, externalRef)
	if err != nil {
		t.Fatalf("query labels: %v", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			t.Fatalf("scan: %v", err)
		}
		out = append(out, n)
	}
	return out
}

func contains(ss []string, want string) bool {
	for _, s := range ss {
		if s == want {
			return true
		}
	}
	return false
}

func newSyncStore(t *testing.T) (*Store, primaryAccountSync) {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	u, err := auth.NewStore(conn).CreateUser("u@example.com", "pw", "U")
	if err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	acct := "acc_m"
	if _, err := conn.Exec(
		`INSERT INTO mail_account(account_id,user_id,email,provider,status,connected_at)
		 VALUES(?,?,?, 'imap', 'connected', ?)`,
		acct, u.ID, "u@example.com", "2026-06-22T00:00:00Z"); err != nil {
		t.Fatalf("seed account: %v", err)
	}
	return NewStore(conn), primaryAccountSync{AccountID: acct, UserID: u.ID, Email: "u@example.com", Provider: "imap"}
}

// NR0011 B3: a re-sync from a partial-label source (LabelsPartial) must preserve labels
// it never advertised (e.g. a user label), instead of wiping them to just "inbox".
func TestPartialLabelMergePreservesUserLabels(t *testing.T) {
	st, acc := newSyncStore(t)
	mk := func(labels []string, partial bool) ExternalChange {
		return ExternalChange{
			Kind: ChangeUpsert, ExternalID: "mid:m1", Subject: "s",
			Body: Body{Format: "text", Content: "b"}, ReceivedAt: "2026-06-22T08:00:00Z",
			Labels: labels, LabelsPartial: partial,
		}
	}
	// initial: inbox + a user label
	if err := st.applyChange(acc, mk([]string{"inbox", "Promotions"}, true)); err != nil {
		t.Fatalf("insert: %v", err)
	}
	if got := labelNamesFor(t, st, "mid:m1"); !contains(got, "Promotions") {
		t.Fatalf("initial labels missing user label: %v", got)
	}
	// re-sync advertises only inbox (partial) -> user label must survive
	if err := st.applyChange(acc, mk([]string{"inbox"}, true)); err != nil {
		t.Fatalf("merge: %v", err)
	}
	got := labelNamesFor(t, st, "mid:m1")
	if !contains(got, "Promotions") || !contains(got, "inbox") {
		t.Fatalf("partial re-sync wiped labels (B3): %v", got)
	}
}

// Contrast: an authoritative source (LabelsPartial=false) still fully replaces labels.
func TestAuthoritativeLabelMergeReplaces(t *testing.T) {
	st, acc := newSyncStore(t)
	mk := func(labels []string) ExternalChange {
		return ExternalChange{
			Kind: ChangeUpsert, ExternalID: "mid:m2", Subject: "s",
			Body: Body{Format: "text", Content: "b"}, ReceivedAt: "2026-06-22T08:00:00Z",
			Labels: labels, LabelsPartial: false,
		}
	}
	if err := st.applyChange(acc, mk([]string{"inbox", "Promotions"})); err != nil {
		t.Fatalf("insert: %v", err)
	}
	if err := st.applyChange(acc, mk([]string{"inbox"})); err != nil {
		t.Fatalf("merge: %v", err)
	}
	if got := labelNamesFor(t, st, "mid:m2"); contains(got, "Promotions") {
		t.Fatalf("authoritative merge should have replaced labels: %v", got)
	}
}

// --- B7: OAuth refresh transient vs permanent classification ---

type stubOAuth struct{ err error }

func (s stubOAuth) Exchange(string, string) (string, Credential, error) {
	return "", Credential{}, nil
}
func (s stubOAuth) Refresh(string, string) (Credential, error) {
	if s.err != nil {
		return Credential{}, s.err
	}
	return Credential{AccessToken: "fresh", RefreshToken: "rt", Expiry: time.Now().Add(time.Hour)}, nil
}

func newOAuthHandlers(t *testing.T, refreshErr error) (*Handlers, primaryAccountSync) {
	t.Helper()
	base := time.Date(2026, 6, 22, 10, 0, 0, 0, time.UTC)
	secrets := NewMemSecretStore()
	secrets.Put("ref1", Credential{
		AccessToken:  "old",
		RefreshToken: "rt",
		Expiry:       base.Add(10 * time.Second), // within oauthRefreshMargin -> triggers refresh
	})
	deps := Deps{
		OAuth:   stubOAuth{err: refreshErr},
		Secrets: secrets,
		Now:     func() time.Time { return base },
	}
	h := NewHandlers(NewStore(nil), deps)
	return h, primaryAccountSync{AccountID: "a", Provider: "gmail", OAuthRef: "ref1"}
}

// NR0011 B7: a transient refresh failure (network/5xx) must surface as a retriable error,
// NOT force the account into reauth_required.
func TestEnsureOAuthFreshTransientIsNotReauth(t *testing.T) {
	h, acc := newOAuthHandlers(t, errors.New("503 temporary"))
	err := h.ensureOAuthFresh(acc)
	if err == nil {
		t.Fatal("transient refresh failure should return an error")
	}
	if errors.Is(err, errReauth) {
		t.Fatal("transient failure must NOT be classified as reauth")
	}
}

// NR0011 B7: a permanent invalid_grant must force reauth.
func TestEnsureOAuthFreshInvalidGrantIsReauth(t *testing.T) {
	h, acc := newOAuthHandlers(t, fmt.Errorf("token endpoint 400: %w", ErrOAuthInvalidGrant))
	if err := h.ensureOAuthFresh(acc); !errors.Is(err, errReauth) {
		t.Fatalf("invalid_grant must force reauth, got %v", err)
	}
}

// happy path: a successful refresh updates the stored credential and returns nil.
func TestEnsureOAuthFreshRefreshesCredential(t *testing.T) {
	h, acc := newOAuthHandlers(t, nil)
	if err := h.ensureOAuthFresh(acc); err != nil {
		t.Fatalf("refresh should succeed: %v", err)
	}
	cred, _ := h.deps.Secrets.Get("ref1")
	if cred.AccessToken != "fresh" {
		t.Fatalf("credential not refreshed: %+v", cred)
	}
}
