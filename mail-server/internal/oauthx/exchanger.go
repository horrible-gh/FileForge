// Package oauthx is the OAuth 2.0 adapter behind mailapi.OAuthExchanger. It runs the
// authorization-code and refresh-token grants against a provider's token endpoint and
// resolves the connected mailbox address, using only the stdlib net/http + encoding/json
// (no new dependency; same ethos as the smtpx SMTP adapter).
//
// Provider endpoints (Google / Microsoft) ship as built-in defaults; per-deployment
// client credentials are injected from config. The access token this yields is what the
// imapx XOAUTH2 adapter presents to the IMAP server, so the two adapters compose.
package oauthx

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"mailanchor/serverd/internal/mailapi"
)

// Provider holds the per-provider OAuth endpoints + injected client credentials.
type Provider struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
	AuthURL      string            // authorization (consent) endpoint for the front-channel
	TokenURL     string            // token endpoint for the back-channel code/refresh grant
	UserInfoURL  string            // GET with Bearer -> {"email": ...}; empty -> fall back to id_token
	Scopes       []string          // consent scopes (must include IMAP scope for XOAUTH2 sync)
	AuthParams   map[string]string // provider-specific consent params (e.g. Google access_type)
}

// Exchanger implements mailapi.OAuthExchanger for the configured providers.
type Exchanger struct {
	providers map[string]Provider
	client    *http.Client
	now       func() time.Time
}

// Defaults returns the built-in Google/Microsoft endpoints with empty credentials.
// New merges these with the injected client id/secret/redirect from config.
func Defaults() map[string]Provider {
	return map[string]Provider{
		"gmail": {
			AuthURL:     "https://accounts.google.com/o/oauth2/v2/auth",
			TokenURL:    "https://oauth2.googleapis.com/token",
			UserInfoURL: "https://openidconnect.googleapis.com/v1/userinfo",
			// https://mail.google.com/ is the full-IMAP scope the imapx XOAUTH2 adapter
			// needs; openid+email resolve the connected mailbox address.
			Scopes: []string{"https://mail.google.com/", "openid", "email"},
			// access_type=offline + prompt=consent make Google return a refresh_token
			// (oauthx.Refresh / sync.go pre-expiry refresh depend on one existing).
			AuthParams: map[string]string{"access_type": "offline", "prompt": "consent"},
		},
		"outlook": {
			AuthURL:     "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
			TokenURL:    "https://login.microsoftonline.com/common/oauth2/v2.0/token",
			UserInfoURL: "https://graph.microsoft.com/oidc/userinfo",
			// IMAP.AccessAsUser.All is the IMAP XOAUTH2 scope; offline_access yields the
			// refresh_token (Microsoft's equivalent of Google's access_type=offline).
			Scopes: []string{"https://outlook.office.com/IMAP.AccessAsUser.All", "offline_access", "openid", "email"},
		},
	}
}

// Creds carries the deployment client credentials for one provider (from config/env).
type Creds struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
}

// New builds an Exchanger for the providers that have a non-empty ClientID in creds.
// Returns nil when no provider is configured (the caller leaves Deps.OAuth nil, so the
// account/sync endpoints answer UPSTREAM_UNAVAILABLE — same as before).
func New(creds map[string]Creds) *Exchanger {
	merged := map[string]Provider{}
	defs := Defaults()
	for name, c := range creds {
		if c.ClientID == "" {
			continue
		}
		p := defs[name] // zero Provider for unknown names -> requires TokenURL set below
		p.ClientID = c.ClientID
		p.ClientSecret = c.ClientSecret
		p.RedirectURI = c.RedirectURI
		if p.TokenURL == "" {
			continue // unknown provider with no endpoint -> skip
		}
		merged[name] = p
	}
	if len(merged) == 0 {
		return nil
	}
	return &Exchanger{
		providers: merged,
		client:    &http.Client{Timeout: 20 * time.Second},
		now:       time.Now,
	}
}

// AuthCodeURL builds the provider consent URL for the front-channel half of the
// authorization-code grant (NR0003 gap A). The client opens it in a browser; the provider
// redirects back to RedirectURI with the auth code the client then posts to /accounts.
// state is an opaque anti-CSRF value the caller must echo-verify on the redirect.
func (e *Exchanger) AuthCodeURL(provider, state string) (string, error) {
	p, ok := e.providers[provider]
	if !ok {
		return "", errUnknownProvider
	}
	if p.AuthURL == "" {
		return "", fmt.Errorf("oauthx: provider %q has no authorization endpoint", provider)
	}
	q := url.Values{
		"response_type": {"code"},
		"client_id":     {p.ClientID},
		"redirect_uri":  {p.RedirectURI},
		"scope":         {strings.Join(p.Scopes, " ")},
		"state":         {state},
	}
	for k, v := range p.AuthParams {
		q.Set(k, v)
	}
	sep := "?"
	if strings.Contains(p.AuthURL, "?") {
		sep = "&"
	}
	return p.AuthURL + sep + q.Encode(), nil
}

// tokenResponse is the RFC 6749 §5.1 token endpoint success body.
type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	IDToken      string `json:"id_token"`
	Error        string `json:"error"`
	ErrorDesc    string `json:"error_description"`
}

var errUnknownProvider = errors.New("oauthx: unknown provider")

// Exchange runs the authorization-code grant (P0007 §7.14) and resolves the mailbox
// address (userinfo endpoint, else the id_token email claim).
func (e *Exchanger) Exchange(provider, authCode string) (string, mailapi.Credential, error) {
	p, ok := e.providers[provider]
	if !ok {
		return "", mailapi.Credential{}, errUnknownProvider
	}
	form := url.Values{
		"grant_type":   {"authorization_code"},
		"code":         {authCode},
		"client_id":    {p.ClientID},
		"redirect_uri": {p.RedirectURI},
	}
	if p.ClientSecret != "" {
		form.Set("client_secret", p.ClientSecret)
	}
	tok, err := e.postToken(p, form)
	if err != nil {
		return "", mailapi.Credential{}, err
	}
	email, err := e.resolveEmail(p, tok)
	if err != nil {
		return "", mailapi.Credential{}, err
	}
	return email, e.toCredential(tok), nil
}

// Refresh runs the refresh-token grant (L0013 §2.5 pre-expiry refresh). Providers that
// omit a rotated refresh_token keep the prior one (carried by the caller's SecretStore).
func (e *Exchanger) Refresh(provider, refreshToken string) (mailapi.Credential, error) {
	p, ok := e.providers[provider]
	if !ok {
		return mailapi.Credential{}, errUnknownProvider
	}
	form := url.Values{
		"grant_type":    {"refresh_token"},
		"refresh_token": {refreshToken},
		"client_id":     {p.ClientID},
	}
	if p.ClientSecret != "" {
		form.Set("client_secret", p.ClientSecret)
	}
	tok, err := e.postToken(p, form)
	if err != nil {
		return mailapi.Credential{}, err
	}
	cred := e.toCredential(tok)
	if cred.RefreshToken == "" {
		cred.RefreshToken = refreshToken // provider did not rotate -> keep existing
	}
	return cred, nil
}

func (e *Exchanger) postToken(p Provider, form url.Values) (tokenResponse, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, p.TokenURL,
		strings.NewReader(form.Encode()))
	if err != nil {
		return tokenResponse{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	resp, err := e.client.Do(req)
	if err != nil {
		return tokenResponse{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	var tok tokenResponse
	if err := json.Unmarshal(body, &tok); err != nil {
		return tokenResponse{}, fmt.Errorf("oauthx: decode token response: %w", err)
	}
	if resp.StatusCode/100 != 2 || tok.Error != "" {
		// invalid_grant = the refresh/auth token is permanently bad -> caller forces
		// reauth. Everything else is treated as transient/retriable (NR0011 B7).
		if tok.Error == "invalid_grant" {
			return tokenResponse{}, fmt.Errorf("oauthx: token endpoint %d: %s %s: %w",
				resp.StatusCode, tok.Error, tok.ErrorDesc, mailapi.ErrOAuthInvalidGrant)
		}
		return tokenResponse{}, fmt.Errorf("oauthx: token endpoint %d: %s %s",
			resp.StatusCode, tok.Error, tok.ErrorDesc)
	}
	if tok.AccessToken == "" {
		return tokenResponse{}, errors.New("oauthx: token response missing access_token")
	}
	return tok, nil
}

func (e *Exchanger) toCredential(tok tokenResponse) mailapi.Credential {
	var expiry time.Time
	if tok.ExpiresIn > 0 {
		expiry = e.now().Add(time.Duration(tok.ExpiresIn) * time.Second)
	}
	return mailapi.Credential{
		AccessToken:  tok.AccessToken,
		RefreshToken: tok.RefreshToken,
		Expiry:       expiry,
	}
}

// resolveEmail prefers the OIDC userinfo endpoint; if it is absent or fails it falls back
// to the email claim of the id_token. The id_token arrived over TLS directly from the
// provider's token endpoint, so its claims are trusted without separate signature
// verification (standard for the direct code-exchange response).
func (e *Exchanger) resolveEmail(p Provider, tok tokenResponse) (string, error) {
	if p.UserInfoURL != "" {
		if email := e.userInfoEmail(p.UserInfoURL, tok.AccessToken); email != "" {
			return email, nil
		}
	}
	if email := idTokenEmail(tok.IDToken); email != "" {
		return email, nil
	}
	return "", errors.New("oauthx: could not resolve account email")
}

func (e *Exchanger) userInfoEmail(endpoint, accessToken string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return ""
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	resp, err := e.client.Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return ""
	}
	var info struct {
		Email string `json:"email"`
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	_ = json.Unmarshal(body, &info)
	return info.Email
}

// idTokenEmail extracts the "email" claim from a JWT id_token payload (no signature
// verification — see resolveEmail). Returns "" on any decode failure.
func idTokenEmail(idToken string) string {
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 {
		return ""
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return ""
	}
	var claims struct {
		Email string `json:"email"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		return ""
	}
	return claims.Email
}
