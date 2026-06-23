package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// clearConfigEnv blanks the env vars Load reads so each case starts from a clean slate.
func clearConfigEnv(t *testing.T) {
	t.Helper()
	for _, k := range []string{
		"MAILANCHOR_ENV", "MAILANCHOR_JWT_SECRET", "MAILANCHOR_TRUST_PROXY",
		"MAILANCHOR_ACCESS_TTL_SEC", "MAILANCHOR_REFRESH_TTL_SEC",
		"MAILANCHOR_FILEFORGE_JWT_PUBKEY", "MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE",
		"MAILANCHOR_FILEFORGE_ISSUER", "MAILANCHOR_FILEFORGE_AUDIENCE",
	} {
		t.Setenv(k, "")
	}
}

// NR0011 S1: production must refuse to boot without a JWT secret; the old behaviour
// silently baked in a known constant that let anyone forge access tokens.
func TestLoadRequiresJWTSecretInProduction(t *testing.T) {
	clearConfigEnv(t)
	// default env is production, secret empty -> error
	if _, err := Load(); err == nil {
		t.Fatal("production Load with empty JWT secret must error")
	}

	// explicit production + weak (<16 byte) secret -> error
	t.Setenv("MAILANCHOR_ENV", "production")
	t.Setenv("MAILANCHOR_JWT_SECRET", "tooshort")
	if _, err := Load(); err == nil {
		t.Fatal("production Load with a weak JWT secret must error")
	}

	// production + strong secret -> ok, kept verbatim
	t.Setenv("MAILANCHOR_JWT_SECRET", "a-sufficiently-long-production-secret")
	c, err := Load()
	if err != nil {
		t.Fatalf("production Load with strong secret: %v", err)
	}
	if string(c.JWTSecret) != "a-sufficiently-long-production-secret" {
		t.Fatalf("secret not preserved: %q", c.JWTSecret)
	}
}

// NR0011 S1: dev/test envs get a per-boot random ephemeral secret — never the old
// source-baked constant, so a leaked binary cannot forge tokens.
func TestLoadEphemeralDevSecret(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("MAILANCHOR_ENV", "development")
	c, err := Load()
	if err != nil {
		t.Fatalf("dev Load: %v", err)
	}
	if len(c.JWTSecret) < 16 {
		t.Fatalf("dev secret too short: %d bytes", len(c.JWTSecret))
	}
	if string(c.JWTSecret) == "dev-insecure-secret-change-me" {
		t.Fatal("dev secret must not be the removed hardcoded constant")
	}
	// two boots must not share the same ephemeral secret
	c2, err := Load()
	if err != nil {
		t.Fatalf("dev Load 2: %v", err)
	}
	if string(c.JWTSecret) == string(c2.JWTSecret) {
		t.Fatal("ephemeral dev secret should differ per boot")
	}
}

// NR0011 S3: TrustProxy defaults OFF and parses common boolean spellings.
func TestLoadTrustProxy(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("MAILANCHOR_ENV", "development")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.TrustProxy {
		t.Fatal("TrustProxy must default to false")
	}
	for _, v := range []string{"1", "true", "YES", "on"} {
		t.Setenv("MAILANCHOR_TRUST_PROXY", v)
		c, err := Load()
		if err != nil {
			t.Fatalf("Load(%s): %v", v, err)
		}
		if !c.TrustProxy {
			t.Fatalf("TrustProxy=%s should parse true", v)
		}
	}
}

// mailanchor.ui.0003 T1: the FileForge bridge is OFF until a public key is supplied,
// and accepts the key inline (env) or via a file path, with optional iss/aud.
func TestLoadFileForgeBridge(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("MAILANCHOR_ENV", "development")

	// no key -> disabled
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.FileForge.Enabled() {
		t.Fatal("FileForge bridge must default to disabled")
	}

	const pemInline = "-----BEGIN PUBLIC KEY-----\nMIIBdummy\n-----END PUBLIC KEY-----\n"

	// inline PEM + issuer/audience
	t.Setenv("MAILANCHOR_FILEFORGE_JWT_PUBKEY", pemInline)
	t.Setenv("MAILANCHOR_FILEFORGE_ISSUER", "fileforge")
	t.Setenv("MAILANCHOR_FILEFORGE_AUDIENCE", "mailanchor")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load(inline): %v", err)
	}
	if !c.FileForge.Enabled() || string(c.FileForge.PubKeyPEM) != pemInline {
		t.Fatalf("inline PEM not loaded: %q", c.FileForge.PubKeyPEM)
	}
	if c.FileForge.Issuer != "fileforge" || c.FileForge.Audience != "mailanchor" {
		t.Fatalf("iss/aud not loaded: %+v", c.FileForge)
	}

	// file path takes effect when the inline var is empty
	t.Setenv("MAILANCHOR_FILEFORGE_JWT_PUBKEY", "")
	keyPath := filepath.Join(t.TempDir(), "ff.pub")
	if werr := os.WriteFile(keyPath, []byte(pemInline), 0o600); werr != nil {
		t.Fatalf("write key file: %v", werr)
	}
	t.Setenv("MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE", keyPath)
	c, err = Load()
	if err != nil {
		t.Fatalf("Load(file): %v", err)
	}
	if !c.FileForge.Enabled() || string(c.FileForge.PubKeyPEM) != pemInline {
		t.Fatalf("file PEM not loaded: %q", c.FileForge.PubKeyPEM)
	}
}

func TestLoadEnvLowercased(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("MAILANCHOR_ENV", "DEVELOPMENT")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.Env != "development" || !strings.EqualFold(c.Env, "development") {
		t.Fatalf("env not lowercased: %q", c.Env)
	}
}
