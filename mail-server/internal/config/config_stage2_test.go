package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Stage 2 (R0001): the canonical FileForge/MailAnchor env keys are read first, with the
// legacy MAILANCHOR_* keys kept as fallbacks.

func TestCanonicalKeysPreferredOverLegacy(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")

	// canonical wins when both present
	t.Setenv("SECRET_KEY", "canonical-secret-key-1234567890")
	t.Setenv("MAILANCHOR_JWT_SECRET", "legacy-secret-should-be-ignored")
	t.Setenv("CONTEXT", "/fileforge")
	t.Setenv("MAILANCHOR_CONTEXT", "/legacy")
	t.Setenv("DB_PATH", "/canon/db.sqlite")
	t.Setenv("MAILANCHOR_DB_PATH", "/legacy/db.sqlite")
	t.Setenv("MAIL_STORAGE_BASE_PATH", "/canon/mails")
	t.Setenv("MAILANCHOR_ATTACHMENT_DIR", "/legacy/att")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if string(c.JWTSecret) != "canonical-secret-key-1234567890" {
		t.Fatalf("SECRET_KEY not preferred: %q", c.JWTSecret)
	}
	if c.Context != "/fileforge" {
		t.Fatalf("CONTEXT not preferred: %q", c.Context)
	}
	if c.DBPath != "/canon/db.sqlite" {
		t.Fatalf("DB_PATH not preferred: %q", c.DBPath)
	}
	if c.AttachmentDir != "/canon/mails" {
		t.Fatalf("MAIL_STORAGE_BASE_PATH not preferred: %q", c.AttachmentDir)
	}
}

func TestLegacyKeysStillWork(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("MAILANCHOR_ENV", "development")
	t.Setenv("MAILANCHOR_JWT_SECRET", "legacy-secret-key-1234567890")
	t.Setenv("MAILANCHOR_DB_PATH", "/legacy/db.sqlite")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if string(c.JWTSecret) != "legacy-secret-key-1234567890" {
		t.Fatalf("legacy MAILANCHOR_JWT_SECRET fallback broken: %q", c.JWTSecret)
	}
	if c.DBPath != "/legacy/db.sqlite" {
		t.Fatalf("legacy MAILANCHOR_DB_PATH fallback broken: %q", c.DBPath)
	}
	if c.Env != "development" {
		t.Fatalf("legacy MAILANCHOR_ENV fallback broken: %q", c.Env)
	}
}

// ACCESS_TOKEN_EXPIRE_MINUTES is the canonical (minutes) key; the legacy
// MAILANCHOR_ACCESS_TTL_SEC (seconds) is the fallback.
func TestAccessTTLMinutesAndFallback(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")

	t.Setenv("ACCESS_TOKEN_EXPIRE_MINUTES", "30")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.AccessTTL != 30*time.Minute {
		t.Fatalf("ACCESS_TOKEN_EXPIRE_MINUTES=30 -> %v, want 30m", c.AccessTTL)
	}

	// fallback to legacy seconds when the canonical key is absent
	t.Setenv("ACCESS_TOKEN_EXPIRE_MINUTES", "")
	t.Setenv("MAILANCHOR_ACCESS_TTL_SEC", "120")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.AccessTTL != 120*time.Second {
		t.Fatalf("MAILANCHOR_ACCESS_TTL_SEC=120 -> %v, want 2m", c.AccessTTL)
	}

	// default 15m when neither set
	t.Setenv("MAILANCHOR_ACCESS_TTL_SEC", "")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.AccessTTL != 15*time.Minute {
		t.Fatalf("default AccessTTL -> %v, want 15m", c.AccessTTL)
	}
}

func TestRefreshTTLDaysAndFallback(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")

	t.Setenv("REFRESH_TOKEN_EXPIRE_DAYS", "7")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.RefreshTTL != 7*24*time.Hour {
		t.Fatalf("REFRESH_TOKEN_EXPIRE_DAYS=7 -> %v, want 168h", c.RefreshTTL)
	}

	t.Setenv("REFRESH_TOKEN_EXPIRE_DAYS", "")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.RefreshTTL != 2592000*time.Second {
		t.Fatalf("default RefreshTTL -> %v, want 30d", c.RefreshTTL)
	}
}

func TestDBFieldsLoaded(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")
	t.Setenv("DB_TYPE", "mysql")
	t.Setenv("DB_HOST", "192.168.0.250")
	t.Setenv("DB_PORT", "3306")
	t.Setenv("DB_USER", "fileforge")
	t.Setenv("DB_PASSWORD", "secret")
	t.Setenv("DB_DATABASE", "fileforge")
	t.Setenv("DB_SCHEMA", "")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.DBType != "mysql" || c.DBHost != "192.168.0.250" || c.DBPort != 3306 ||
		c.DBUser != "fileforge" || c.DBPassword != "secret" || c.DBName != "fileforge" {
		t.Fatalf("DB_* not loaded: %+v", c)
	}
}

// GOOGLE_* populates the gmail provider (stage 5 single-provider naming), with the legacy
// MAILANCHOR_OAUTH_GMAIL_* keys as fallback. Outlook is preserved via its own keys.
func TestGoogleOAuthCanonicalAndOutlookPreserved(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")
	t.Setenv("GOOGLE_CLIENT_ID", "gid")
	t.Setenv("GOOGLE_CLIENT_SECRET", "gsec")
	t.Setenv("GOOGLE_REDIRECT_URI", "https://app/callback")
	t.Setenv("MAILANCHOR_OAUTH_OUTLOOK_CLIENT_ID", "oid")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	g, ok := c.OAuth["gmail"]
	if !ok || g.ClientID != "gid" || g.ClientSecret != "gsec" || g.RedirectURI != "https://app/callback" {
		t.Fatalf("GOOGLE_* not mapped to gmail provider: %+v", c.OAuth)
	}
	if o, ok := c.OAuth["outlook"]; !ok || o.ClientID != "oid" {
		t.Fatalf("outlook provider not preserved: %+v", c.OAuth)
	}
}

func TestGmailLegacyFallback(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")
	t.Setenv("MAILANCHOR_OAUTH_GMAIL_CLIENT_ID", "legacy-gid")
	t.Setenv("MAILANCHOR_OAUTH_GMAIL_CLIENT_SECRET", "legacy-gsec")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if g, ok := c.OAuth["gmail"]; !ok || g.ClientID != "legacy-gid" || g.ClientSecret != "legacy-gsec" {
		t.Fatalf("legacy gmail fallback broken: %+v", c.OAuth)
	}
}

func TestRedisConfigLoaded(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")

	// default: disabled (no host)
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.Redis.Enabled() {
		t.Fatal("Redis must default to disabled (no REDIS_HOST)")
	}

	t.Setenv("REDIS_HOST", "192.168.0.250")
	t.Setenv("REDIS_PORT", "6380")
	t.Setenv("REDIS_DB", "2")
	t.Setenv("REDIS_PASSWORD", "rpw")
	t.Setenv("REDIS_SSL", "true")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if !c.Redis.Enabled() || c.Redis.Host != "192.168.0.250" || c.Redis.Port != 6380 ||
		c.Redis.DB != 2 || c.Redis.Password != "rpw" || !c.Redis.SSL {
		t.Fatalf("REDIS_* not loaded: %+v", c.Redis)
	}
}

func TestAllowedOriginLoaded(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")
	t.Setenv("ALLOWED_ORIGIN", "https://mail.example.com, http://localhost:3031, https://mail.example.com")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	want := []string{"https://mail.example.com", "http://localhost:3031"}
	if strings.Join(c.AllowedOrigins, ",") != strings.Join(want, ",") {
		t.Fatalf("ALLOWED_ORIGIN not loaded: %q", strings.Join(c.AllowedOrigins, ","))
	}
}

func TestAllowedOriginDefaultsByEnvironment(t *testing.T) {
	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "development")
	c, err := Load()
	if err != nil {
		t.Fatalf("Load(dev): %v", err)
	}
	if got := strings.Join(c.AllowedOrigins, ","); got != "http://localhost:3031,http://127.0.0.1:3031" {
		t.Fatalf("dev allowed origins = %q", got)
	}

	clearConfigEnv(t)
	t.Setenv("ENVIRONMENT", "production")
	t.Setenv("SECRET_KEY", "production-secret-key-1234567890")
	c, err = Load()
	if err != nil {
		t.Fatalf("Load(prod): %v", err)
	}
	if len(c.AllowedOrigins) != 0 {
		t.Fatalf("prod allowed origins should default empty, got %q", strings.Join(c.AllowedOrigins, ","))
	}
}

// .env loading: values are read from the file, but the process environment always wins.
func TestDotEnvLoadingAndPrecedence(t *testing.T) {
	clearConfigEnv(t)
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".env")
	body := "# stage 2 dotenv\n" +
		"export ENVIRONMENT=development\n" +
		"SECRET_KEY=\"from-dotenv-secret-1234567890\"\n" +
		"CONTEXT='/fromdotenv'\n" +
		"DB_TYPE=mysql\n"
	if err := os.WriteFile(envPath, []byte(body), 0o600); err != nil {
		t.Fatalf("write .env: %v", err)
	}
	t.Setenv("ENV_FILE", envPath)
	// process env wins over .env for CONTEXT
	t.Setenv("CONTEXT", "/from-process-env")

	c, err := Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if c.Env != "development" {
		t.Fatalf(".env ENVIRONMENT not applied: %q", c.Env)
	}
	if string(c.JWTSecret) != "from-dotenv-secret-1234567890" {
		t.Fatalf(".env SECRET_KEY (quoted) not applied: %q", c.JWTSecret)
	}
	if c.DBType != "mysql" {
		t.Fatalf(".env DB_TYPE not applied: %q", c.DBType)
	}
	if c.Context != "/from-process-env" {
		t.Fatalf("process env must win over .env: %q", c.Context)
	}
}
