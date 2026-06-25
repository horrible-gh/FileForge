package server_test

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/server"
)

// healthz must report the FileForge bridge state so a misconfigured FileForge-absorb
// deployment (no pubkey -> every federated request 401s) is detectable at probe time
// rather than only when a user's GET /accounts fails (server.0004 NR0003 cause A).

func baseCfg() config.Config {
	return config.Config{
		Context:    "/api/v1",
		JWTSecret:  []byte("test-secret-0123456789abcdef"),
		AccessTTL:  900 * time.Second,
		RefreshTTL: 30 * 24 * time.Hour,
	}
}

func healthzBridge(t *testing.T, cfg config.Config) (int, string) {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	ts := httptest.NewServer(server.New(cfg, conn))
	t.Cleanup(ts.Close)

	resp, err := http.Get(ts.URL + cfg.Context + "/healthz")
	if err != nil {
		t.Fatalf("GET healthz: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var env struct {
		OK   bool `json:"ok"`
		Data struct {
			Status          string   `json:"status"`
			FileForgeBridge string   `json:"fileforge_bridge"`
			OAuthConfigured bool     `json:"oauth_configured"`
			OAuthProviders  []string `json:"oauth_providers"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		t.Fatalf("decode healthz body %q: %v", body, err)
	}
	if !env.OK || env.Data.Status != "ok" {
		t.Fatalf("healthz not ok: %q", body)
	}
	return resp.StatusCode, env.Data.FileForgeBridge
}

func healthzOAuth(t *testing.T, cfg config.Config) (bool, []string) {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })

	ts := httptest.NewServer(server.New(cfg, conn))
	t.Cleanup(ts.Close)

	resp, err := http.Get(ts.URL + cfg.Context + "/healthz")
	if err != nil {
		t.Fatalf("GET healthz: %v", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	var env struct {
		OK   bool `json:"ok"`
		Data struct {
			OAuthConfigured bool     `json:"oauth_configured"`
			OAuthProviders  []string `json:"oauth_providers"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &env); err != nil {
		t.Fatalf("decode healthz body %q: %v", body, err)
	}
	if !env.OK {
		t.Fatalf("healthz not ok: %q", body)
	}
	return env.Data.OAuthConfigured, env.Data.OAuthProviders
}

func TestHealthzReportsBridgeDisabledByDefault(t *testing.T) {
	code, bridge := healthzBridge(t, baseCfg())
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	if bridge != "disabled" {
		t.Fatalf("fileforge_bridge = %q, want %q (no pubkey configured)", bridge, "disabled")
	}
}

func TestHealthzReportsBridgeEnabledWithPubKey(t *testing.T) {
	cfg := baseCfg()
	cfg.FileForge = config.FileForgeFederation{PubKeyPEM: testRSAPubPEM(t)}

	code, bridge := healthzBridge(t, cfg)
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	if bridge != "enabled" {
		t.Fatalf("fileforge_bridge = %q, want %q (valid pubkey configured)", bridge, "enabled")
	}
}

// A configured-but-malformed key must NOT report enabled: the bridge stays off (boot does
// not block) and healthz should reflect that so the bad key is visible at probe time.
func TestHealthzReportsBridgeDisabledOnBadPubKey(t *testing.T) {
	cfg := baseCfg()
	cfg.FileForge = config.FileForgeFederation{PubKeyPEM: []byte("-----BEGIN PUBLIC KEY-----\nnot-a-key\n-----END PUBLIC KEY-----\n")}

	code, bridge := healthzBridge(t, cfg)
	if code != http.StatusOK {
		t.Fatalf("status = %d, want 200", code)
	}
	if bridge != "disabled" {
		t.Fatalf("fileforge_bridge = %q, want %q (malformed pubkey)", bridge, "disabled")
	}
}

func TestHealthzReportsOAuthConfiguration(t *testing.T) {
	configured, providers := healthzOAuth(t, baseCfg())
	if configured {
		t.Fatalf("oauth_configured = true, want false")
	}
	if len(providers) != 0 {
		t.Fatalf("oauth_providers = %v, want empty", providers)
	}

	cfg := baseCfg()
	cfg.OAuth = map[string]config.OAuthProvider{
		"gmail": {ClientID: "gid", ClientSecret: "gsec", RedirectURI: "https://app/cb"},
	}
	configured, providers = healthzOAuth(t, cfg)
	if !configured {
		t.Fatalf("oauth_configured = false, want true")
	}
	if len(providers) != 1 || providers[0] != "gmail" {
		t.Fatalf("oauth_providers = %v, want [gmail]", providers)
	}
}

// testRSAPubPEM mints a throwaway RSA key and returns its PKIX public-key PEM, the shape
// NewFederatedVerifier accepts.
func testRSAPubPEM(t *testing.T) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("GenerateKey: %v", err)
	}
	der, err := x509.MarshalPKIXPublicKey(&key.PublicKey)
	if err != nil {
		t.Fatalf("MarshalPKIXPublicKey: %v", err)
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PUBLIC KEY", Bytes: der})
}
