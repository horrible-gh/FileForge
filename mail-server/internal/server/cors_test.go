package server_test

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/server"
)

// Stage 2 (R0001): when ALLOWED_ORIGIN is set, CORS headers are emitted for a matching
// Origin and preflight OPTIONS is short-circuited; when unset, no CORS headers appear.

func newTestServer(t *testing.T, allowedOrigins []string) *httptest.Server {
	t.Helper()
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	cfg := baseCfg()
	cfg.AllowedOrigins = allowedOrigins
	ts := httptest.NewServer(server.New(cfg, conn))
	t.Cleanup(ts.Close)
	return ts
}

func TestCORSDisabledByDefault(t *testing.T) {
	ts := newTestServer(t, nil)
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/healthz", nil)
	req.Header.Set("Origin", "https://mail.example.com")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("no CORS header expected when ALLOWED_ORIGIN unset, got %q", got)
	}
}

func TestCORSEchoesMatchingOrigin(t *testing.T) {
	const origin = "https://mail.example.com"
	ts := newTestServer(t, []string{origin})
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/healthz", nil)
	req.Header.Set("Origin", origin)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Fatalf("Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
}

func TestCORSIgnoresNonMatchingOrigin(t *testing.T) {
	ts := newTestServer(t, []string{"https://allowed.example.com"})
	req, _ := http.NewRequest(http.MethodGet, ts.URL+"/api/v1/healthz", nil)
	req.Header.Set("Origin", "https://evil.example.com")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	defer resp.Body.Close()
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("non-matching origin must not be echoed, got %q", got)
	}
}

func TestCORSPreflightShortCircuits(t *testing.T) {
	const origin = "https://mail.example.com"
	ts := newTestServer(t, []string{origin})
	req, _ := http.NewRequest(http.MethodOptions, ts.URL+"/api/v1/auth/login", nil)
	req.Header.Set("Origin", origin)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("OPTIONS: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want 204", resp.StatusCode)
	}
	if got := resp.Header.Get("Access-Control-Allow-Methods"); got == "" {
		t.Fatal("preflight should advertise Access-Control-Allow-Methods")
	}
}

func TestCORSMultipleOrigins(t *testing.T) {
	const origin = "http://127.0.0.1:3031"
	ts := newTestServer(t, []string{"http://localhost:3031", origin, "http://localhost:4152"})
	req, _ := http.NewRequest(http.MethodOptions, ts.URL+"/api/v1/accounts", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	req.Header.Set("Access-Control-Request-Headers", "authorization")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("OPTIONS: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want 204", resp.StatusCode)
	}
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Fatalf("Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
}

func TestCORSAllowsFlutterWebDevPort(t *testing.T) {
	const origin = "http://localhost:4152"
	ts := newTestServer(t, []string{"http://localhost:3031", "http://127.0.0.1:3031", origin})
	req, _ := http.NewRequest(http.MethodOptions, ts.URL+"/api/v1/accounts", nil)
	req.Header.Set("Origin", origin)
	req.Header.Set("Access-Control-Request-Method", http.MethodGet)
	req.Header.Set("Access-Control-Request-Headers", "authorization")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("OPTIONS: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		t.Fatalf("preflight status = %d, want 204", resp.StatusCode)
	}
	if got := resp.Header.Get("Access-Control-Allow-Origin"); got != origin {
		t.Fatalf("Access-Control-Allow-Origin = %q, want %q", got, origin)
	}
}
