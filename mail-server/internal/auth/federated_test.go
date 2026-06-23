package auth_test

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"path/filepath"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/db"
)

// fileforgeIssuer simulates the FileForge side of the polyglot bridge: it holds the RSA
// private key and mints RS256 tokens, exposing only its public key (PEM) to the verifier.
type fileforgeIssuer struct {
	key *rsa.PrivateKey
}

func newFileforgeIssuer(t *testing.T) *fileforgeIssuer {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("rsa keygen: %v", err)
	}
	return &fileforgeIssuer{key: key}
}

func (f *fileforgeIssuer) pubPEM(t *testing.T) []byte {
	t.Helper()
	der, err := x509.MarshalPKIXPublicKey(&f.key.PublicKey)
	if err != nil {
		t.Fatalf("marshal pubkey: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
}

// mint signs an RS256 token shaped like a FileForge access token.
func (f *fileforgeIssuer) mint(t *testing.T, claims jwt.MapClaims) string {
	t.Helper()
	tok, err := jwt.NewWithClaims(jwt.SigningMethodRS256, claims).SignedString(f.key)
	if err != nil {
		t.Fatalf("sign RS256: %v", err)
	}
	return tok
}

func newFederatedSvc(t *testing.T, ff *fileforgeIssuer, issuer, audience string) (*auth.Service, *auth.Store) {
	t.Helper()
	dbPath := filepath.Join(t.TempDir(), "test.db")
	conn, err := db.Open(dbPath)
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	store := auth.NewStore(conn)
	svc := auth.NewService(store, []byte("test-secret"), 900*time.Second, 30*24*time.Hour)
	fv, err := auth.NewFederatedVerifier(ff.pubPEM(t), issuer, audience)
	if err != nil {
		t.Fatalf("NewFederatedVerifier: %v", err)
	}
	svc.WithFederation(fv)
	return svc, store
}

// The done-criterion of mailanchor.ui.0003 T1: a FileForge-issued token authenticates
// (Session/AuthenticateAccess succeed) and a local user is just-in-time provisioned.
func TestFederatedTokenProvisionsAndAuthenticates(t *testing.T) {
	ff := newFileforgeIssuer(t)
	svc, store := newFederatedSvc(t, ff, "fileforge", "mailanchor")

	tok := ff.mint(t, jwt.MapClaims{
		"sub":          "ff_user_123",
		"email":        "alice@fileforge.example",
		"display_name": "Alice",
		"iss":          "fileforge",
		"aud":          "mailanchor",
		"exp":          time.Now().Add(15 * time.Minute).Unix(),
	})

	uid, err := svc.AuthenticateAccess(tok)
	if err != nil {
		t.Fatalf("AuthenticateAccess(fileforge token): %v", err)
	}

	user, ferr := store.FindUserByExternalSubject("ff_user_123")
	if ferr != nil {
		t.Fatalf("user not provisioned: %v", ferr)
	}
	if user.ID != uid {
		t.Fatalf("middleware uid %q != provisioned user %q", uid, user.ID)
	}
	if user.Email != "alice@fileforge.example" {
		t.Fatalf("email claim not stored: %q", user.Email)
	}

	// Session returns the same provisioned identity.
	sr, serr := svc.Session(tok)
	if serr != nil || !sr.Authenticated || sr.User.UserID != uid {
		t.Fatalf("session: err=%v res=%+v", serr, sr)
	}

	// A second request for the same subject is idempotent — no duplicate user.
	uid2, err := svc.AuthenticateAccess(tok)
	if err != nil || uid2 != uid {
		t.Fatalf("idempotent re-auth: uid2=%q err=%v", uid2, err)
	}
}

// FileForge today emits only {sub, exp}; a missing email must not block provisioning.
func TestFederatedTokenWithoutEmailSynthesizes(t *testing.T) {
	ff := newFileforgeIssuer(t)
	svc, store := newFederatedSvc(t, ff, "", "")

	tok := ff.mint(t, jwt.MapClaims{
		"sub": "ff_minimal",
		"exp": time.Now().Add(15 * time.Minute).Unix(),
	})
	if _, err := svc.AuthenticateAccess(tok); err != nil {
		t.Fatalf("minimal token auth: %v", err)
	}
	u, err := store.FindUserByExternalSubject("ff_minimal")
	if err != nil {
		t.Fatalf("provision minimal: %v", err)
	}
	if u.Email == "" {
		t.Fatal("synthesized email must be non-empty (app_user.email is NOT NULL)")
	}
}

func TestFederatedTokenRejections(t *testing.T) {
	ff := newFileforgeIssuer(t)
	other := newFileforgeIssuer(t) // a different key — signature must not verify
	svc, _ := newFederatedSvc(t, ff, "fileforge", "mailanchor")

	cases := []struct {
		name   string
		token  string
		expect string
	}{
		{
			name: "expired fileforge token -> TOKEN_EXPIRED",
			token: ff.mint(t, jwt.MapClaims{
				"sub": "ff_exp", "iss": "fileforge", "aud": "mailanchor",
				"exp": time.Now().Add(-1 * time.Hour).Unix(),
			}),
			expect: "TOKEN_EXPIRED",
		},
		{
			name: "wrong issuer -> TOKEN_INVALID",
			token: ff.mint(t, jwt.MapClaims{
				"sub": "ff_iss", "iss": "evil", "aud": "mailanchor",
				"exp": time.Now().Add(time.Hour).Unix(),
			}),
			expect: "TOKEN_INVALID",
		},
		{
			name: "wrong audience -> TOKEN_INVALID",
			token: ff.mint(t, jwt.MapClaims{
				"sub": "ff_aud", "iss": "fileforge", "aud": "someone-else",
				"exp": time.Now().Add(time.Hour).Unix(),
			}),
			expect: "TOKEN_INVALID",
		},
		{
			name: "foreign signing key -> TOKEN_INVALID",
			token: other.mint(t, jwt.MapClaims{
				"sub": "ff_forged", "iss": "fileforge", "aud": "mailanchor",
				"exp": time.Now().Add(time.Hour).Unix(),
			}),
			expect: "TOKEN_INVALID",
		},
		{
			name:   "garbage -> TOKEN_INVALID",
			token:  "not.a.jwt",
			expect: "TOKEN_INVALID",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if _, err := svc.AuthenticateAccess(c.token); codeOf(err) != c.expect {
				t.Fatalf("want %s, got %v", c.expect, err)
			}
		})
	}
}

// An HS256 alg-confusion attack — signing with the RSA public key bytes as an HMAC
// secret — must be rejected: the federated verifier only accepts RS256.
func TestFederatedRejectsAlgConfusion(t *testing.T) {
	ff := newFileforgeIssuer(t)
	svc, _ := newFederatedSvc(t, ff, "", "")

	forged := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "ff_confuse",
		"exp": time.Now().Add(time.Hour).Unix(),
	})
	signed, err := forged.SignedString(ff.pubPEM(t)) // HS256 over the public key
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	if _, err := svc.AuthenticateAccess(signed); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("alg-confusion must be TOKEN_INVALID, got %v", err)
	}
}

// With no federation configured, a FileForge token is just an unknown token.
func TestNoFederationRejectsForeignToken(t *testing.T) {
	ff := newFileforgeIssuer(t)
	svc, _ := newSvc(t) // no WithFederation
	tok := ff.mint(t, jwt.MapClaims{"sub": "ff_x", "exp": time.Now().Add(time.Hour).Unix()})
	if _, err := svc.AuthenticateAccess(tok); codeOf(err) != "TOKEN_INVALID" {
		t.Fatalf("want TOKEN_INVALID, got %v", err)
	}
}
