package auth_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"mailanchor/serverd/internal/auth"
)

// TestLazyFederatedVerifierSelfHeals reproduces the 0017 NR0003 boot-order race: the Go
// server is armed before FileForge has written server/keys/jwt_public.pem. The lazy
// verifier must reject tokens while the key is absent (request 401s) and then start
// accepting them once the key file appears — without reconstructing the verifier (i.e.
// without a process restart).
func TestLazyFederatedVerifierSelfHeals(t *testing.T) {
	ff := newFileforgeIssuer(t)
	keyPath := filepath.Join(t.TempDir(), "jwt_public.pem")

	// Armed before the key exists (Go booted before FileForge generated the key).
	fv := auth.NewLazyFederatedVerifier(keyPath, "fileforge", "mailanchor")

	if fv.Ready() {
		t.Fatal("verifier must not be ready before the key file exists")
	}
	if got := fv.Status(); got != "pending" {
		t.Fatalf("status before key = %q, want pending", got)
	}

	tok := ff.mint(t, jwt.MapClaims{
		"sub": "ff_user_lazy",
		"iss": "fileforge",
		"aud": "mailanchor",
		"exp": time.Now().Add(time.Hour).Unix(),
	})

	// While the key is missing, verification fails (the protected request 401s) but the
	// failure is non-fatal — the server keeps running and re-tries on the next request.
	if _, err := fv.Verify(tok); err == nil {
		t.Fatal("Verify must fail while the key file is absent")
	}

	// FileForge (re)generates the key — the race resolves on disk, no restart involved.
	if err := os.WriteFile(keyPath, ff.pubPEM(t), 0o600); err != nil {
		t.Fatalf("write key: %v", err)
	}

	// The very next request now succeeds against the same verifier instance.
	claims, err := fv.Verify(tok)
	if err != nil {
		t.Fatalf("Verify after key appeared: %v", err)
	}
	if claims.Subject != "ff_user_lazy" {
		t.Fatalf("subject = %q, want ff_user_lazy", claims.Subject)
	}
	if !fv.Ready() || fv.Status() != "enabled" {
		t.Fatalf("after key load: ready=%v status=%q, want true/enabled", fv.Ready(), fv.Status())
	}
}

// TestLazyFederatedVerifierCachesKey confirms the key is parsed once and cached: after the
// first successful load, removing the file does not break verification (no per-request
// disk read on the hot path once resolved).
func TestLazyFederatedVerifierCachesKey(t *testing.T) {
	ff := newFileforgeIssuer(t)
	keyPath := filepath.Join(t.TempDir(), "jwt_public.pem")
	if err := os.WriteFile(keyPath, ff.pubPEM(t), 0o600); err != nil {
		t.Fatalf("write key: %v", err)
	}
	fv := auth.NewLazyFederatedVerifier(keyPath, "fileforge", "mailanchor")

	tok := ff.mint(t, jwt.MapClaims{
		"sub": "ff_user_cache",
		"iss": "fileforge",
		"aud": "mailanchor",
		"exp": time.Now().Add(time.Hour).Unix(),
	})
	if _, err := fv.Verify(tok); err != nil {
		t.Fatalf("first Verify: %v", err)
	}
	if err := os.Remove(keyPath); err != nil {
		t.Fatalf("remove key: %v", err)
	}
	if _, err := fv.Verify(tok); err != nil {
		t.Fatalf("Verify after key removed (should be cached): %v", err)
	}
}
