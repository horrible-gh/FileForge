// Package config loads runtime configuration from the environment.
// Token TTLs default to L0010 §1 parameters.
package config

import (
	"crypto/rand"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Addr       string        // listen address, e.g. ":8090"
	Context    string        // API base path, P0007: /api/v1
	DBPath     string        // sqlite file path
	Env        string        // deployment env: "production" (default) | "development" | "test"
	JWTSecret  []byte        // HS256 signing key for the stateless access token
	AccessTTL  time.Duration // L0010 access_token_ttl (default 900s)
	RefreshTTL time.Duration // L0010 refresh_token_ttl (default 30d)

	// TrustProxy enables X-Forwarded-For client-IP resolution (chi RealIP). Leave OFF
	// unless a trusted reverse proxy strips/sets XFF — otherwise a client can rotate XFF
	// to evade the per-IP login lockout (NR0011 S3). MAILANCHOR_TRUST_PROXY=1.
	TrustProxy bool

	// Phase 2 — external services / object store.
	AttachmentDir string // disk object-store root for attachment bytes (DB0008 §2.7)
	SMTPHost      string // outbound relay host (empty -> Sender disabled -> SEND_FAILED)
	SMTPPort      int    // outbound relay port
	SMTPUser      string // relay auth username (empty -> unauthenticated relay)
	SMTPPassword  string // relay auth password

	// OAuth client credentials per provider (gmail/outlook). A provider with an empty
	// ClientID is disabled; if none is set, Deps.OAuth/Source stay nil and the
	// account/sync endpoints answer UPSTREAM_UNAVAILABLE (unchanged behaviour).
	OAuth map[string]OAuthProvider

	// OAuthReturnURL is the app URL the OAuth callback redirects the browser back to after a
	// successful server-side code exchange (server.0005 NR0009 gap A; e.g. a Flutter deep
	// link). Empty -> the callback renders a self-contained "close this window" page instead.
	OAuthReturnURL string

	// FileForge — polyglot token-sharing bridge (mailanchor.ui.0003 T1). When a
	// FileForge RSA *public* key is configured, the Go server accepts RS256 access
	// tokens minted by FileForge (verified against this key) in addition to its own
	// HS256 tokens, and just-in-time provisions a local user keyed by the token
	// subject. The polyglot boundary stays secret-free: only the public key crosses
	// it. Empty -> bridge disabled (only self-issued HS256 tokens are accepted).
	FileForge FileForgeFederation
}

// FileForgeFederation holds the verification parameters for FileForge-issued tokens.
// PubKeyPEM is the PEM-encoded RSA public key (PKIX or PKCS1). Issuer/Audience, when
// non-empty, are enforced against the token's iss/aud claims.
type FileForgeFederation struct {
	PubKeyPEM []byte
	Issuer    string
	Audience  string
}

// Enabled reports whether the FileForge token bridge is configured.
func (f FileForgeFederation) Enabled() bool { return len(f.PubKeyPEM) > 0 }

// OAuthProvider is one provider's injected client credentials (endpoints are built-in
// defaults in the oauthx adapter).
type OAuthProvider struct {
	ClientID     string
	ClientSecret string
	RedirectURI  string
}

// Load reads configuration from environment variables, applying design defaults.
func Load() (Config, error) {
	c := Config{
		Addr:       getenv("MAILANCHOR_ADDR", ":8090"),
		Context:    getenv("MAILANCHOR_CONTEXT", "/api/v1"),
		DBPath:     getenv("MAILANCHOR_DB_PATH", "./mailanchor.db"),
		Env:        strings.ToLower(getenv("MAILANCHOR_ENV", "production")),
		TrustProxy: getenvBool("MAILANCHOR_TRUST_PROXY", false),
		JWTSecret:  []byte(getenv("MAILANCHOR_JWT_SECRET", "")),
		AccessTTL:  time.Duration(getenvInt("MAILANCHOR_ACCESS_TTL_SEC", 900)) * time.Second,
		RefreshTTL: time.Duration(getenvInt("MAILANCHOR_REFRESH_TTL_SEC", 2592000)) * time.Second,

		AttachmentDir:  getenv("MAILANCHOR_ATTACHMENT_DIR", "./attachments"),
		SMTPHost:       getenv("MAILANCHOR_SMTP_HOST", ""),
		SMTPPort:       getenvInt("MAILANCHOR_SMTP_PORT", 587),
		SMTPUser:       getenv("MAILANCHOR_SMTP_USER", ""),
		SMTPPassword:   getenv("MAILANCHOR_SMTP_PASSWORD", ""),
		OAuth:          loadOAuth(),
		OAuthReturnURL: getenv("MAILANCHOR_OAUTH_RETURN_URL", ""),
		FileForge:      loadFileForge(),
	}
	if err := resolveJWTSecret(&c); err != nil {
		return Config{}, err
	}
	if c.AccessTTL <= 0 || c.RefreshTTL <= 0 {
		return Config{}, fmt.Errorf("token TTLs must be positive")
	}
	return c, nil
}

// isDevEnv reports whether the env permits an auto-generated dev secret.
func isDevEnv(env string) bool {
	switch env {
	case "development", "dev", "test", "local":
		return true
	}
	return false
}

// resolveJWTSecret enforces NR0011 S1: a production deployment MUST supply
// MAILANCHOR_JWT_SECRET (≥16 bytes). The previous behaviour silently fell back to a
// source-baked constant — anyone knowing it could forge access tokens. We now refuse
// to boot in production with a missing/weak secret; non-production envs get a per-boot
// random ephemeral secret (no constant exists anywhere, so it is never forgeable).
func resolveJWTSecret(c *Config) error {
	const minSecretLen = 16
	if len(c.JWTSecret) == 0 {
		if !isDevEnv(c.Env) {
			return fmt.Errorf("MAILANCHOR_JWT_SECRET is required in %s mode "+
				"(set MAILANCHOR_ENV=development for an ephemeral dev secret)", c.Env)
		}
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			return fmt.Errorf("generate ephemeral dev JWT secret: %w", err)
		}
		c.JWTSecret = buf
		return nil
	}
	if !isDevEnv(c.Env) && len(c.JWTSecret) < minSecretLen {
		return fmt.Errorf("MAILANCHOR_JWT_SECRET must be at least %d bytes in %s mode",
			minSecretLen, c.Env)
	}
	return nil
}

// loadOAuth reads per-provider client credentials from the environment, e.g.
// MAILANCHOR_OAUTH_GMAIL_CLIENT_ID / _CLIENT_SECRET / _REDIRECT_URI. Providers with no
// client id are omitted.
func loadOAuth() map[string]OAuthProvider {
	out := map[string]OAuthProvider{}
	for _, name := range []string{"gmail", "outlook"} {
		prefix := "MAILANCHOR_OAUTH_" + strings.ToUpper(name) + "_"
		id := getenv(prefix+"CLIENT_ID", "")
		if id == "" {
			continue
		}
		out[name] = OAuthProvider{
			ClientID:     id,
			ClientSecret: getenv(prefix+"CLIENT_SECRET", ""),
			RedirectURI:  getenv(prefix+"REDIRECT_URI", ""),
		}
	}
	return out
}

// loadFileForge reads the FileForge token-bridge parameters. The public key may be
// supplied either inline as PEM (MAILANCHOR_FILEFORGE_JWT_PUBKEY, may contain newlines)
// or as a filesystem path (MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE). A read failure on the
// file path is non-fatal (bridge stays disabled) and surfaces later as an unverifiable
// token rather than blocking boot.
func loadFileForge() FileForgeFederation {
	f := FileForgeFederation{
		Issuer:   getenv("MAILANCHOR_FILEFORGE_ISSUER", ""),
		Audience: getenv("MAILANCHOR_FILEFORGE_AUDIENCE", ""),
	}
	if pem := getenv("MAILANCHOR_FILEFORGE_JWT_PUBKEY", ""); pem != "" {
		f.PubKeyPEM = []byte(pem)
		return f
	}
	if path := getenv("MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE", ""); path != "" {
		if body, err := os.ReadFile(path); err == nil {
			f.PubKeyPEM = body
		}
	}
	return f
}

func getenv(k, def string) string {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		return v
	}
	return def
}

func getenvInt(k string, def int) int {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func getenvBool(k string, def bool) bool {
	if v, ok := os.LookupEnv(k); ok && v != "" {
		switch strings.ToLower(v) {
		case "1", "true", "yes", "on":
			return true
		case "0", "false", "no", "off":
			return false
		}
	}
	return def
}
