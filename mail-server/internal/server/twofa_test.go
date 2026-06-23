package server_test

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/server"
	"mailanchor/serverd/internal/totp"
)

// End-to-end R0001 stage-4 wiring through the HTTP router: enroll -> activate -> the login
// gate requires X-TOTP-Code. Exercises route mounting, RequireAuth on the 2FA endpoints, and
// the X-TOTP-Code header path the client uses.
func TestTwoFactorHTTPFlow(t *testing.T) {
	conn, err := db.Open(filepath.Join(t.TempDir(), "t.db"))
	if err != nil {
		t.Fatalf("db.Open: %v", err)
	}
	t.Cleanup(func() { conn.Close() })
	if _, err := auth.NewStore(conn).CreateUser("u@example.com", "pw-12345678", "U"); err != nil {
		t.Fatalf("CreateUser: %v", err)
	}
	ts := httptest.NewServer(server.New(baseCfg(), conn))
	t.Cleanup(ts.Close)

	doJSON := func(t *testing.T, method, path, bearer, totpCode string, body any) (int, map[string]any) {
		t.Helper()
		var buf bytes.Buffer
		if body != nil {
			_ = json.NewEncoder(&buf).Encode(body)
		}
		req, _ := http.NewRequest(method, ts.URL+path, &buf)
		req.Header.Set("Content-Type", "application/json")
		if bearer != "" {
			req.Header.Set("Authorization", "Bearer "+bearer)
		}
		if totpCode != "" {
			req.Header.Set("X-TOTP-Code", totpCode)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatalf("%s %s: %v", method, path, err)
		}
		defer resp.Body.Close()
		raw, _ := io.ReadAll(resp.Body)
		var env map[string]any
		_ = json.Unmarshal(raw, &env)
		// P0007 envelope: successful bodies are under "data".
		if d, ok := env["data"].(map[string]any); ok {
			return resp.StatusCode, d
		}
		return resp.StatusCode, env
	}

	// 1) Plain login -> access token.
	code, data := doJSON(t, http.MethodPost, "/api/v1/auth/login", "", "", map[string]string{"email": "u@example.com", "password": "pw-12345678"})
	if code != http.StatusOK {
		t.Fatalf("login status = %d, body=%v", code, data)
	}
	access, _ := data["access_token"].(string)
	if access == "" {
		t.Fatalf("no access_token in login response: %v", data)
	}

	// 2) Enroll (needs auth).
	code, data = doJSON(t, http.MethodPost, "/api/v1/auth/2fa/setup", access, "", nil)
	if code != http.StatusOK {
		t.Fatalf("setup status = %d, body=%v", code, data)
	}
	secret, _ := data["secret"].(string)
	if secret == "" {
		t.Fatalf("no secret in setup response: %v", data)
	}

	// 3) Activate with a current code.
	otp, _ := totp.Code(secret, time.Now())
	code, data = doJSON(t, http.MethodPost, "/api/v1/auth/2fa/activate", access, "", map[string]string{"code": otp})
	if code != http.StatusOK {
		t.Fatalf("activate status = %d, body=%v", code, data)
	}

	// 4) Login without a code now returns requires_2fa (200, no token).
	code, data = doJSON(t, http.MethodPost, "/api/v1/auth/login", "", "", map[string]string{"email": "u@example.com", "password": "pw-12345678"})
	if code != http.StatusOK || data["requires_2fa"] != true {
		t.Fatalf("gated login: status=%d body=%v (want 200 requires_2fa)", code, data)
	}
	if _, hasToken := data["access_token"]; hasToken {
		t.Fatalf("gated login must not issue a token: %v", data)
	}

	// 5) Login with the X-TOTP-Code header succeeds.
	otp, _ = totp.Code(secret, time.Now())
	code, data = doJSON(t, http.MethodPost, "/api/v1/auth/login", "", otp, map[string]string{"email": "u@example.com", "password": "pw-12345678"})
	if code != http.StatusOK {
		t.Fatalf("2fa login status = %d, body=%v", code, data)
	}
	if access2, _ := data["access_token"].(string); access2 == "" {
		t.Fatalf("2fa login must issue a token: %v", data)
	}

	// 6) The 2FA endpoints reject an unauthenticated caller.
	if code, _ := doJSON(t, http.MethodGet, "/api/v1/auth/2fa/status", "", "", nil); code != http.StatusUnauthorized {
		t.Fatalf("unauth /2fa/status = %d, want 401", code)
	}
}
