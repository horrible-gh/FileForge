package oauthx

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// tokenServer is a canned OAuth token + userinfo endpoint.
func tokenServer(t *testing.T, tokenBody map[string]any, email string, wantGrant string) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		if err := r.ParseForm(); err != nil {
			t.Errorf("parse form: %v", err)
		}
		if g := r.Form.Get("grant_type"); wantGrant != "" && g != wantGrant {
			t.Errorf("grant_type=%q want %q", g, wantGrant)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(tokenBody)
	})
	mux.HandleFunc("/userinfo", func(w http.ResponseWriter, r *http.Request) {
		if auth := r.Header.Get("Authorization"); auth == "" {
			t.Errorf("userinfo missing bearer")
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"email": email})
	})
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

func newTestExchanger(ts *httptest.Server, userInfo bool) *Exchanger {
	p := Provider{ClientID: "cid", ClientSecret: "csec", RedirectURI: "https://app/cb",
		TokenURL: ts.URL + "/token"}
	if userInfo {
		p.UserInfoURL = ts.URL + "/userinfo"
	}
	return &Exchanger{
		providers: map[string]Provider{"gmail": p},
		client:    ts.Client(),
		now:       func() time.Time { return time.Date(2026, 6, 22, 9, 0, 0, 0, time.UTC) },
	}
}

func TestExchangeUserInfoEmail(t *testing.T) {
	ts := tokenServer(t, map[string]any{
		"access_token": "at-1", "refresh_token": "rt-1", "expires_in": 3600,
	}, "user@gmail.com", "authorization_code")
	ex := newTestExchanger(ts, true)

	email, cred, err := ex.Exchange("gmail", "the-code")
	if err != nil {
		t.Fatalf("Exchange: %v", err)
	}
	if email != "user@gmail.com" {
		t.Fatalf("email=%q", email)
	}
	if cred.AccessToken != "at-1" || cred.RefreshToken != "rt-1" {
		t.Fatalf("cred=%+v", cred)
	}
	want := time.Date(2026, 6, 22, 10, 0, 0, 0, time.UTC)
	if !cred.Expiry.Equal(want) {
		t.Fatalf("expiry=%v want %v", cred.Expiry, want)
	}
}

func TestExchangeIDTokenEmailFallback(t *testing.T) {
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"email":"claim@outlook.com"}`))
	idToken := "h." + payload + ".sig"
	ts := tokenServer(t, map[string]any{
		"access_token": "at-2", "expires_in": 3600, "id_token": idToken,
	}, "", "authorization_code")
	ex := newTestExchanger(ts, false) // no userinfo -> id_token claim used

	email, _, err := ex.Exchange("gmail", "code")
	if err != nil {
		t.Fatalf("Exchange: %v", err)
	}
	if email != "claim@outlook.com" {
		t.Fatalf("email=%q", email)
	}
}

func TestRefreshKeepsExistingRefreshToken(t *testing.T) {
	ts := tokenServer(t, map[string]any{
		"access_token": "at-new", "expires_in": 3600, // no refresh_token rotated
	}, "", "refresh_token")
	ex := newTestExchanger(ts, false)

	cred, err := ex.Refresh("gmail", "rt-original")
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if cred.AccessToken != "at-new" {
		t.Fatalf("access=%q", cred.AccessToken)
	}
	if cred.RefreshToken != "rt-original" {
		t.Fatalf("refresh token should be preserved, got %q", cred.RefreshToken)
	}
}

func TestExchangeTokenEndpointError(t *testing.T) {
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"invalid_grant","error_description":"bad code"}`))
	})
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	ex := &Exchanger{
		providers: map[string]Provider{"gmail": {ClientID: "c", TokenURL: ts.URL + "/token"}},
		client:    ts.Client(), now: time.Now,
	}
	if _, _, err := ex.Exchange("gmail", "bad"); err == nil {
		t.Fatal("expected error on invalid_grant")
	}
}

func TestExchangeUnknownProvider(t *testing.T) {
	ex := &Exchanger{providers: map[string]Provider{}, client: http.DefaultClient, now: time.Now}
	if _, _, err := ex.Exchange("icloud", "c"); err == nil {
		t.Fatal("expected unknown-provider error")
	}
}

func TestNewMergesDefaultsAndSkipsEmpty(t *testing.T) {
	ex := New(map[string]Creds{
		"gmail":   {ClientID: "gid", ClientSecret: "gsec"},
		"outlook": {ClientID: ""}, // disabled
	})
	if ex == nil {
		t.Fatal("expected exchanger")
	}
	if _, ok := ex.providers["gmail"]; !ok {
		t.Fatal("gmail should be configured")
	}
	if ex.providers["gmail"].TokenURL != "https://oauth2.googleapis.com/token" {
		t.Fatalf("default endpoint not merged: %q", ex.providers["gmail"].TokenURL)
	}
	if _, ok := ex.providers["outlook"]; ok {
		t.Fatal("outlook with empty client id must be skipped")
	}
	if New(map[string]Creds{}) != nil {
		t.Fatal("no creds -> nil exchanger")
	}
}

func TestIDTokenEmail(t *testing.T) {
	payload := base64.RawURLEncoding.EncodeToString([]byte(`{"email":"a@b.com","sub":"1"}`))
	if got := idTokenEmail("x." + payload + ".y"); got != "a@b.com" {
		t.Fatalf("idTokenEmail=%q", got)
	}
	if got := idTokenEmail("not-a-jwt"); got != "" {
		t.Fatalf("malformed -> empty, got %q", got)
	}
}

func TestAuthCodeURLGmail(t *testing.T) {
	ex := New(map[string]Creds{"gmail": {ClientID: "gid", ClientSecret: "gsec", RedirectURI: "https://app/cb"}})
	if ex == nil {
		t.Fatal("expected exchanger")
	}
	raw, err := ex.AuthCodeURL("gmail", "state-xyz")
	if err != nil {
		t.Fatalf("AuthCodeURL: %v", err)
	}
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if u.Scheme+"://"+u.Host+u.Path != "https://accounts.google.com/o/oauth2/v2/auth" {
		t.Fatalf("auth endpoint=%q", u.Scheme+"://"+u.Host+u.Path)
	}
	q := u.Query()
	if q.Get("response_type") != "code" || q.Get("client_id") != "gid" || q.Get("redirect_uri") != "https://app/cb" {
		t.Fatalf("core params wrong: %v", q)
	}
	if q.Get("state") != "state-xyz" {
		t.Fatalf("state=%q", q.Get("state"))
	}
	// gap-A invariants: IMAP scope + offline access -> XOAUTH2 sync works and a refresh_token is issued.
	if !strings.Contains(q.Get("scope"), "https://mail.google.com/") {
		t.Fatalf("missing IMAP scope: %q", q.Get("scope"))
	}
	if q.Get("access_type") != "offline" || q.Get("prompt") != "consent" {
		t.Fatalf("offline/consent params missing: access_type=%q prompt=%q", q.Get("access_type"), q.Get("prompt"))
	}
}

func TestAuthCodeURLOutlookScopes(t *testing.T) {
	ex := New(map[string]Creds{"outlook": {ClientID: "oid", RedirectURI: "https://app/cb"}})
	raw, err := ex.AuthCodeURL("outlook", "s")
	if err != nil {
		t.Fatalf("AuthCodeURL: %v", err)
	}
	q, _ := url.ParseQuery(raw[strings.Index(raw, "?")+1:])
	scope := q.Get("scope")
	if !strings.Contains(scope, "IMAP.AccessAsUser.All") || !strings.Contains(scope, "offline_access") {
		t.Fatalf("outlook scopes wrong: %q", scope)
	}
}

func TestAuthCodeURLUnknownProvider(t *testing.T) {
	ex := New(map[string]Creds{"gmail": {ClientID: "gid"}})
	if _, err := ex.AuthCodeURL("icloud", "s"); err == nil {
		t.Fatal("expected unknown-provider error")
	}
}

// sanity: form encoding round-trips the auth code (guards against a stray Set/Add typo).
func TestExchangePostsCode(t *testing.T) {
	var gotCode string
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		gotCode = r.Form.Get("code")
		_ = json.NewEncoder(w).Encode(map[string]any{"access_token": "at", "expires_in": 60,
			"id_token": "h." + base64.RawURLEncoding.EncodeToString([]byte(`{"email":"z@z.com"}`)) + ".s"})
	})
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	ex := &Exchanger{providers: map[string]Provider{"gmail": {ClientID: "c", TokenURL: ts.URL + "/token"}},
		client: ts.Client(), now: time.Now}
	if _, _, err := ex.Exchange("gmail", "abc123"); err != nil {
		t.Fatalf("Exchange: %v", err)
	}
	if gotCode != "abc123" {
		t.Fatalf("code not posted: %q", gotCode)
	}
	_ = url.Values{}
}
