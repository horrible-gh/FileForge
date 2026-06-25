// Package config loads runtime configuration from the environment.
// Token TTLs default to L0010 §1 parameters.
//
// Stage 2 (R0001) — env naming is aligned with the FileForge/MailAnchor Python
// originals: the canonical keys (SECRET_KEY, ACCESS_TOKEN_EXPIRE_MINUTES, CONTEXT,
// DB_*, MAIL_STORAGE_BASE_PATH, GOOGLE_*, ENVIRONMENT, ALLOWED_ORIGIN, REDIS_*) are
// read first, with the legacy MAILANCHOR_* keys kept as fallbacks so existing
// deployments/tests keep working. The FileForge token-bridge keys (MAILANCHOR_FILEFORGE_*)
// are intentionally NOT renamed (R0001: "[유지] JWT 브릿지 … 깨지 말 것").
package config

import (
	"bufio"
	"crypto/rand"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Addr       string        // listen address, e.g. ":8090"
	Context    string        // API base path (CONTEXT), P0007: /api/v1
	Env        string        // deployment env (ENVIRONMENT): "production" (default) | "development" | "test"
	JWTSecret  []byte        // HS256 signing key (SECRET_KEY) for the stateless access token
	AccessTTL  time.Duration // ACCESS_TOKEN_EXPIRE_MINUTES (default 15m)
	RefreshTTL time.Duration // refresh_token_ttl (default 30d)

	// --- DB layer (stage 1) ---
	DBType     string // DB_TYPE: mysql | sqlite (aliases normalized in db.NormalizeDriver)
	DBPath     string // DB_PATH: sqlite file path
	DBHost     string // DB_HOST (mysql)
	DBPort     int    // DB_PORT (mysql; 0 -> 3306)
	DBUser     string // DB_USER (mysql)
	DBPassword string // DB_PASSWORD (mysql)
	DBName     string // DB_DATABASE (mysql)
	DBSchema   string // DB_SCHEMA (reserved; MySQL has no separate schema concept)

	// TrustProxy enables X-Forwarded-For client-IP resolution (chi RealIP). Leave OFF
	// unless a trusted reverse proxy strips/sets XFF — otherwise a client can rotate XFF
	// to evade the per-IP login lockout (NR0011 S3). MAILANCHOR_TRUST_PROXY=1.
	TrustProxy bool

	// AllowedOrigins (ALLOWED_ORIGIN) — CORS allow-origins for the SPA/mobile client.
	// Empty -> no CORS middleware mounted (same-origin only).
	AllowedOrigins []string

	// Phase 2 — external services / object store.
	AttachmentDir string // MAIL_STORAGE_BASE_PATH: disk object-store root for attachment bytes
	SMTPHost      string // outbound relay host (empty -> Sender disabled -> SEND_FAILED)
	SMTPPort      int    // outbound relay port
	SMTPUser      string // relay auth username (empty -> unauthenticated relay)
	SMTPPassword  string // relay auth password

	// OAuth client credentials per provider (gmail/outlook). A provider with an empty
	// ClientID is disabled; if none is set, Deps.OAuth/Source stay nil and the
	// account/sync endpoints answer UPSTREAM_UNAVAILABLE (unchanged behaviour). The
	// canonical GOOGLE_* keys populate the "gmail" provider (R0001 stage 5).
	OAuth map[string]OAuthProvider

	// OAuthReturnURL is the app URL the OAuth callback redirects the browser back to after a
	// successful server-side code exchange (server.0005 NR0009 gap A; e.g. a Flutter deep
	// link). Empty -> the callback renders a self-contained "close this window" page instead.
	OAuthReturnURL string

	// SecretEncryptionKey (MAILANCHOR_SECRET_ENCRYPTION_KEY) keys the AES-256-GCM at-rest
	// encryption of stored OAuth credentials (R0001 stage 5). Empty -> the in-memory dev
	// secret store is used (unchanged default). Any length is accepted (SHA-256-folded to a
	// 32-byte key by the store). Kept distinct from SECRET_KEY (signing) for key hygiene.
	SecretEncryptionKey []byte

	// Redis (stage 3 scaffolding) — token blacklist / 2FA state shared store. The config
	// surface is aligned now (REDIS_*); the runtime client is wired in stage 3. Enabled()
	// reports whether a host was supplied.
	Redis RedisConfig

	// FileForge — polyglot token-sharing bridge (mailanchor.ui.0003 T1). When a
	// FileForge RSA *public* key is configured, the Go server accepts RS256 access
	// tokens minted by FileForge (verified against this key) in addition to its own
	// HS256 tokens, and just-in-time provisions a local user keyed by the token
	// subject. The polyglot boundary stays secret-free: only the public key crosses
	// it. Empty -> bridge disabled (only self-issued HS256 tokens are accepted).
	FileForge FileForgeFederation
}

// RedisConfig holds the shared-store connection parameters (FileForge REDIS_* convention).
type RedisConfig struct {
	Host     string
	Port     int
	DB       int
	Password string
	SSL      bool
}

// Enabled reports whether a Redis host was configured (stage 3 wiring gate).
func (r RedisConfig) Enabled() bool { return r.Host != "" }

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
// A .env file (ENV_FILE or ./.env) is loaded first; values already present in the
// process environment win over .env (standard precedence).
func Load() (Config, error) {
	loadDotEnv()

	c := Config{
		Addr:    getenv("MAILANCHOR_ADDR", ":8090"),
		Context: firstenv("/api/v1", "CONTEXT", "MAILANCHOR_CONTEXT"),
		Env:     strings.ToLower(firstenv("production", "ENVIRONMENT", "MAILANCHOR_ENV")),

		DBType:     firstenv("sqlite", "DB_TYPE"),
		DBPath:     firstenv("./mailanchor.db", "DB_PATH", "MAILANCHOR_DB_PATH"),
		DBHost:     firstenv("", "DB_HOST"),
		DBPort:     firstenvInt(0, "DB_PORT"),
		DBUser:     firstenv("", "DB_USER"),
		DBPassword: firstenv("", "DB_PASSWORD"),
		DBName:     firstenv("", "DB_DATABASE"),
		DBSchema:   firstenv("", "DB_SCHEMA"),

		TrustProxy:     getenvBool("MAILANCHOR_TRUST_PROXY", false),
		AllowedOrigins: loadAllowedOrigins(strings.ToLower(firstenv("production", "ENVIRONMENT", "MAILANCHOR_ENV"))),
		JWTSecret:      []byte(firstenv("", "SECRET_KEY", "MAILANCHOR_JWT_SECRET")),
		AccessTTL:      resolveAccessTTL(),
		RefreshTTL:     resolveRefreshTTL(),

		AttachmentDir:       firstenv("./attachments", "MAIL_STORAGE_BASE_PATH", "MAILANCHOR_ATTACHMENT_DIR"),
		SMTPHost:            getenv("MAILANCHOR_SMTP_HOST", ""),
		SMTPPort:            getenvInt("MAILANCHOR_SMTP_PORT", 587),
		SMTPUser:            getenv("MAILANCHOR_SMTP_USER", ""),
		SMTPPassword:        getenv("MAILANCHOR_SMTP_PASSWORD", ""),
		OAuth:               loadOAuth(),
		OAuthReturnURL:      getenv("MAILANCHOR_OAUTH_RETURN_URL", ""),
		SecretEncryptionKey: []byte(getenv("MAILANCHOR_SECRET_ENCRYPTION_KEY", "")),
		Redis:               loadRedis(),
		FileForge:           loadFileForge(),
	}
	if err := resolveJWTSecret(&c); err != nil {
		return Config{}, err
	}
	if c.AccessTTL <= 0 || c.RefreshTTL <= 0 {
		return Config{}, fmt.Errorf("token TTLs must be positive")
	}
	return c, nil
}

// resolveAccessTTL prefers the canonical ACCESS_TOKEN_EXPIRE_MINUTES (R0001 explicitly
// "(분)"), falling back to the legacy MAILANCHOR_ACCESS_TTL_SEC (seconds), default 15m.
func resolveAccessTTL() time.Duration {
	if m := getenvInt("ACCESS_TOKEN_EXPIRE_MINUTES", 0); m > 0 {
		return time.Duration(m) * time.Minute
	}
	return time.Duration(getenvInt("MAILANCHOR_ACCESS_TTL_SEC", 900)) * time.Second
}

// resolveRefreshTTL prefers REFRESH_TOKEN_EXPIRE_DAYS (FileForge convention), falling
// back to the legacy MAILANCHOR_REFRESH_TTL_SEC (seconds), default 30d (Q2: kept, since
// the consolidated key list has no refresh key — we accept both).
func resolveRefreshTTL() time.Duration {
	if d := getenvInt("REFRESH_TOKEN_EXPIRE_DAYS", 0); d > 0 {
		return time.Duration(d) * 24 * time.Hour
	}
	return time.Duration(getenvInt("MAILANCHOR_REFRESH_TTL_SEC", 2592000)) * time.Second
}

func loadAllowedOrigins(env string) []string {
	raw := firstenv("", "ALLOWED_ORIGIN", "MAILANCHOR_ALLOWED_ORIGINS", "MAILANCHOR_ALLOWED_ORIGIN")
	if raw == "" && isDevEnv(env) {
		raw = "http://localhost:3031,http://127.0.0.1:3031,http://localhost:4152,http://127.0.0.1:4152"
	}
	if raw == "" {
		return nil
	}
	seen := map[string]bool{}
	out := []string{}
	for _, part := range strings.Split(raw, ",") {
		origin := strings.TrimSpace(part)
		if origin == "" || seen[origin] {
			continue
		}
		seen[origin] = true
		out = append(out, origin)
	}
	return out
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
// SECRET_KEY (≥16 bytes). The previous behaviour silently fell back to a
// source-baked constant — anyone knowing it could forge access tokens. We now refuse
// to boot in production with a missing/weak secret; non-production envs get a per-boot
// random ephemeral secret (no constant exists anywhere, so it is never forgeable).
func resolveJWTSecret(c *Config) error {
	const minSecretLen = 16
	if len(c.JWTSecret) == 0 {
		if !isDevEnv(c.Env) {
			return fmt.Errorf("SECRET_KEY is required in %s mode "+
				"(set ENVIRONMENT=development for an ephemeral dev secret)", c.Env)
		}
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			return fmt.Errorf("generate ephemeral dev JWT secret: %w", err)
		}
		c.JWTSecret = buf
		return nil
	}
	if !isDevEnv(c.Env) && len(c.JWTSecret) < minSecretLen {
		return fmt.Errorf("SECRET_KEY must be at least %d bytes in %s mode",
			minSecretLen, c.Env)
	}
	return nil
}

// loadOAuth reads per-provider client credentials. The canonical GOOGLE_* keys populate
// the "gmail" provider (R0001 stage 5: GOOGLE_* single provider); the legacy
// MAILANCHOR_OAUTH_GMAIL_* keys remain as fallbacks. Outlook is kept (Q5: preserved but
// not the canonical path) via MAILANCHOR_OAUTH_OUTLOOK_*. Providers with no client id
// are omitted.
func loadOAuth() map[string]OAuthProvider {
	out := map[string]OAuthProvider{}

	if id := firstenv("", "GOOGLE_CLIENT_ID", "MAILANCHOR_OAUTH_GMAIL_CLIENT_ID"); id != "" {
		out["gmail"] = OAuthProvider{
			ClientID:     id,
			ClientSecret: firstenv("", "GOOGLE_CLIENT_SECRET", "MAILANCHOR_OAUTH_GMAIL_CLIENT_SECRET"),
			RedirectURI:  firstenv("", "GOOGLE_REDIRECT_URI", "MAILANCHOR_OAUTH_GMAIL_REDIRECT_URI"),
		}
	}

	if id := getenv("MAILANCHOR_OAUTH_OUTLOOK_CLIENT_ID", ""); id != "" {
		out["outlook"] = OAuthProvider{
			ClientID:     id,
			ClientSecret: getenv("MAILANCHOR_OAUTH_OUTLOOK_CLIENT_SECRET", ""),
			RedirectURI:  getenv("MAILANCHOR_OAUTH_OUTLOOK_REDIRECT_URI", ""),
		}
	}
	return out
}

// loadRedis reads the shared-store connection parameters (FileForge REDIS_* convention).
func loadRedis() RedisConfig {
	return RedisConfig{
		Host:     firstenv("", "REDIS_HOST"),
		Port:     firstenvInt(6379, "REDIS_PORT"),
		DB:       firstenvInt(0, "REDIS_DB"),
		Password: firstenv("", "REDIS_PASSWORD"),
		SSL:      getenvBool("REDIS_SSL", false),
	}
}

// loadFileForge reads the FileForge token-bridge parameters. The public key may be
// supplied either inline as PEM (MAILANCHOR_FILEFORGE_JWT_PUBKEY, may contain newlines)
// or as a filesystem path (MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE). A read failure on the
// file path is non-fatal (bridge stays disabled) and surfaces later as an unverifiable
// token rather than blocking boot. These keys are NOT renamed (R0001: keep the bridge).
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

// loadDotEnv loads KEY=VALUE pairs from ENV_FILE (default ./.env) into the process
// environment, but never overwrites a variable that is already set — the real
// environment always wins. A missing file is a silent no-op. This is a minimal,
// dependency-free parser (R0001 stage 2 "+.env 로딩"): it understands comments (#),
// blank lines, optional `export ` prefixes, and single/double-quoted values.
func loadDotEnv() {
	path := os.Getenv("ENV_FILE")
	if path == "" {
		path = ".env"
	}
	file, err := os.Open(path)
	if err != nil {
		return // no .env -> nothing to do
	}
	defer file.Close()

	sc := bufio.NewScanner(file)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		eq := strings.IndexByte(line, '=')
		if eq <= 0 {
			continue
		}
		key := strings.TrimSpace(line[:eq])
		val := strings.TrimSpace(line[eq+1:])
		val = unquote(val)
		if key == "" {
			continue
		}
		// Process env wins, but treat an empty value as absent (consistent with the
		// firstenv/getenv readers, which ignore ""): a var set to "" is overridable.
		if v, ok := os.LookupEnv(key); ok && v != "" {
			continue
		}
		_ = os.Setenv(key, val)
	}
}

// unquote strips a single matching pair of surrounding single or double quotes.
func unquote(s string) string {
	if len(s) >= 2 {
		if (s[0] == '"' && s[len(s)-1] == '"') || (s[0] == '\'' && s[len(s)-1] == '\'') {
			return s[1 : len(s)-1]
		}
	}
	return s
}

// firstenv returns the first non-empty value among keys, else def.
func firstenv(def string, keys ...string) string {
	for _, k := range keys {
		if v, ok := os.LookupEnv(k); ok && v != "" {
			return v
		}
	}
	return def
}

// firstenvInt returns the first parseable integer among keys, else def.
func firstenvInt(def int, keys ...string) int {
	for _, k := range keys {
		if v, ok := os.LookupEnv(k); ok && v != "" {
			if n, err := strconv.Atoi(v); err == nil {
				return n
			}
		}
	}
	return def
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
