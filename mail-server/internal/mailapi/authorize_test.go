package mailapi_test

import (
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/db"
	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/oauthx"
	"mailanchor/serverd/internal/server"
)

// authEnv builds a logged-in server with the given OAuth dependency (which may be nil,
// or a back-channel-only fake that does not satisfy OAuthAuthorizer).
func authEnv(t *testing.T, oauth mailapi.OAuthExchanger) *env {
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
	deps := mailapi.Deps{OAuth: oauth, Secrets: mailapi.NewMemSecretStore()}
	cfg := config.Config{
		Context: "/api/v1", JWTSecret: []byte("test-secret"),
		AccessTTL: 900 * time.Second, RefreshTTL: 30 * 24 * time.Hour,
	}
	ts := httptest.NewServer(server.NewWithDeps(cfg, conn, deps))
	t.Cleanup(ts.Close)

	e := &env{ts: ts, user: u.ID}
	var lr struct {
		Data struct {
			AccessToken string `json:"access_token"`
		} `json:"data"`
	}
	e.do(t, http.MethodPost, "/api/v1/auth/login", "",
		map[string]any{"email": "u@example.com", "password": "pw"}, http.StatusOK, &lr)
	e.token = lr.Data.AccessToken
	return e
}

// real oauthx exchanger satisfies both OAuthExchanger and the optional OAuthAuthorizer.
func configuredOAuth() mailapi.OAuthExchanger {
	return oauthx.New(map[string]oauthx.Creds{
		"gmail": {ClientID: "gid", ClientSecret: "gsec", RedirectURI: "https://app/cb"},
	})
}

func TestAuthorizeURLOK(t *testing.T) {
	e := authEnv(t, configuredOAuth())
	var res struct {
		Data struct {
			AuthURL string `json:"auth_url"`
			State   string `json:"state"`
		} `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/accounts/oauth/authorize?provider=gmail", e.token, nil, http.StatusOK, &res)
	if !strings.HasPrefix(res.Data.AuthURL, "https://accounts.google.com/o/oauth2/v2/auth?") {
		t.Fatalf("auth_url=%q", res.Data.AuthURL)
	}
	if res.Data.State == "" {
		t.Fatal("state must be returned for CSRF echo-verify")
	}
	// the returned state must be embedded in the URL the client opens.
	if !strings.Contains(res.Data.AuthURL, "state="+res.Data.State) {
		t.Fatalf("state not bound into url: %q", res.Data.AuthURL)
	}
}

func TestAuthorizeURLBadProvider(t *testing.T) {
	e := authEnv(t, configuredOAuth())
	raw := e.do(t, http.MethodGet, "/api/v1/accounts/oauth/authorize?provider=icloud", e.token, nil, http.StatusBadRequest, nil)
	if errCode(raw) != "VALIDATION_FAILED" {
		t.Fatalf("code=%q", errCode(raw))
	}
}

func TestAuthorizeURLNotConfigured(t *testing.T) {
	e := authEnv(t, nil) // OAuth nil -> not configured
	raw := e.do(t, http.MethodGet, "/api/v1/accounts/oauth/authorize?provider=gmail", e.token, nil, http.StatusServiceUnavailable, nil)
	if errCode(raw) != "UPSTREAM_UNAVAILABLE" {
		t.Fatalf("code=%q", errCode(raw))
	}
}

// backChannelOnlyOAuth implements OAuthExchanger but NOT OAuthAuthorizer, proving the
// handler degrades to "not configured" rather than panicking on the type assertion.
type backChannelOnlyOAuth struct{}

func (backChannelOnlyOAuth) Exchange(string, string) (string, mailapi.Credential, error) {
	return "", mailapi.Credential{}, nil
}
func (backChannelOnlyOAuth) Refresh(string, string) (mailapi.Credential, error) {
	return mailapi.Credential{}, nil
}

func TestAuthorizeURLBackChannelOnly(t *testing.T) {
	e := authEnv(t, backChannelOnlyOAuth{})
	raw := e.do(t, http.MethodGet, "/api/v1/accounts/oauth/authorize?provider=gmail", e.token, nil, http.StatusServiceUnavailable, nil)
	if errCode(raw) != "UPSTREAM_UNAVAILABLE" {
		t.Fatalf("code=%q", errCode(raw))
	}
}
