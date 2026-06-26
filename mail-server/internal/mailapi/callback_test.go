package mailapi_test

import (
	"errors"
	"net/http"
	"strings"
	"testing"

	"mailanchor/serverd/internal/mailapi"
)

// fakeAuthorizerOAuth implements both OAuthExchanger and the optional OAuthAuthorizer with a
// deterministic, network-free exchange so the front-channel callback can be tested e2e.
type fakeAuthorizerOAuth struct{ email string }

func (f fakeAuthorizerOAuth) Exchange(provider, code string) (string, mailapi.Credential, error) {
	if code == "bad" {
		return "", mailapi.Credential{}, errors.New("token endpoint rejected code")
	}
	return f.email, mailapi.Credential{AccessToken: "at-" + code, RefreshToken: "rt"}, nil
}
func (f fakeAuthorizerOAuth) Refresh(string, string) (mailapi.Credential, error) {
	return mailapi.Credential{}, nil
}
func (f fakeAuthorizerOAuth) AuthCodeURL(provider, state string) (string, error) {
	return "https://accounts.google.com/o/oauth2/v2/auth?state=" + state, nil
}

// issueState runs the authenticated authorize half-step and returns the issued state, which
// the (unauthenticated) callback then redeems.
func issueState(t *testing.T, e *env, provider string) string {
	t.Helper()
	var res struct {
		Data struct {
			State string `json:"state"`
		} `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/accounts/oauth/authorize?provider="+provider, e.token, nil, http.StatusOK, &res)
	if res.Data.State == "" {
		t.Fatal("authorize returned empty state")
	}
	return res.Data.State
}

// listAccountEmails fetches the connected-account emails for assertions.
func listAccountEmails(t *testing.T, e *env) []string {
	t.Helper()
	var res struct {
		Data []mailapi.Account `json:"data"`
	}
	e.do(t, http.MethodGet, "/api/v1/accounts", e.token, nil, http.StatusOK, &res)
	out := make([]string, 0, len(res.Data))
	for _, a := range res.Data {
		out = append(out, a.Email)
	}
	return out
}

// TestOAuthCallbackHappyPath is the core NR0009 gap-A fix: the provider redirects the browser
// (no JWT) to /accounts/oauth/callback, the server exchanges the code + connects the account,
// and the user never touches the raw code. The connected account then shows in GET /accounts.
func TestOAuthCallbackHappyPath(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})
	state := issueState(t, e, "gmail")

	// Callback carries NO Authorization header (browser redirect). With no OAuthReturnURL
	// configured the handler serves the self-contained HTML page (200).
	raw := e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?code=good&state="+state, "", nil, http.StatusOK, nil)
	body := string(raw)
	if !strings.Contains(body, "Connection complete") || !strings.Contains(body, "owner@gmail.com") {
		t.Fatalf("callback page missing success markers: %s", body)
	}

	emails := listAccountEmails(t, e)
	found := false
	for _, em := range emails {
		if em == "owner@gmail.com" {
			found = true
		}
	}
	if !found {
		t.Fatalf("account not connected after callback; accounts=%v", emails)
	}
}

// TestOAuthCallbackRejectsUnknownState guards CSRF/replay: a state the server never issued (or
// already consumed) is rejected and no account is created.
func TestOAuthCallbackRejectsUnknownState(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})

	raw := e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?code=good&state=st_forged", "", nil, http.StatusBadRequest, nil)
	if !strings.Contains(string(raw), "Connection failed") {
		t.Fatalf("expected failure page, got: %s", raw)
	}
	if emails := listAccountEmails(t, e); len(emails) != 0 {
		t.Fatalf("no account should be created on bad state; accounts=%v", emails)
	}
}

// TestOAuthCallbackStateIsSingleUse proves Take consumes the state: replaying the same state
// after a successful exchange is rejected (no second/duplicate connect via replay).
func TestOAuthCallbackStateIsSingleUse(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})
	state := issueState(t, e, "gmail")

	e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?code=good&state="+state, "", nil, http.StatusOK, nil)
	// Replay the same state -> rejected as unknown (already consumed).
	e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?code=good&state="+state, "", nil, http.StatusBadRequest, nil)
}

// TestOAuthCallbackProviderError surfaces a consent denial (?error=) as the failure page
// without attempting an exchange.
func TestOAuthCallbackProviderError(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})
	state := issueState(t, e, "gmail")

	raw := e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?error=access_denied&state="+state, "", nil, http.StatusBadRequest, nil)
	if !strings.Contains(string(raw), "access_denied") {
		t.Fatalf("expected provider error echoed, got: %s", raw)
	}
}

// TestOAuthCallbackExchangeFailure: a valid state but the back-channel exchange fails -> the
// failure page renders and no account is created (credential is rolled back).
func TestOAuthCallbackExchangeFailure(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})
	state := issueState(t, e, "gmail")

	e.do(t, http.MethodGet,
		"/api/v1/accounts/oauth/callback?code=bad&state="+state, "", nil, http.StatusBadRequest, nil)
	if emails := listAccountEmails(t, e); len(emails) != 0 {
		t.Fatalf("no account should be created when exchange fails; accounts=%v", emails)
	}
}

// TestOAuthCallbackIsPublic confirms the callback route is NOT behind RequireAuth (a missing
// token must not 401 it) — the whole point is that the provider's redirect is unauthenticated.
func TestOAuthCallbackIsPublic(t *testing.T) {
	e := authEnv(t, fakeAuthorizerOAuth{email: "owner@gmail.com"})
	// No state, no auth: a public route answers 400 (invalid_request), an auth-gated one 401.
	e.do(t, http.MethodGet, "/api/v1/accounts/oauth/callback", "", nil, http.StatusBadRequest, nil)
}
