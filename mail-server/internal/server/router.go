// Package server wires the HTTP router for the MailAnchor Go backend.
package server

import (
	"database/sql"
	"log"
	"net/http"
	"sort"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/imapx"
	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/oauthx"
	"mailanchor/serverd/internal/sharedstore"
	"mailanchor/serverd/internal/smtpx"
	"mailanchor/serverd/internal/storage"
)

// New builds the application router with the production external-service ports
// derived from cfg (disk attachment store, SMTP relay if configured, in-memory
// secret store). When OAuth client credentials are configured, the OAuth exchanger
// (oauthx), XOAUTH2 IMAP ChangeSource (imapx), and Gmail XOAUTH2 SMTP Sender are wired
// so account/sync/send work for Gmail without a separate SMTP relay. Otherwise they
// stay nil and those endpoints answer UPSTREAM_UNAVAILABLE/SEND_FAILED as applicable.
func New(cfg config.Config, db *sql.DB) http.Handler {
	blob, err := storage.NewDiskStore(cfg.AttachmentDir)
	if err != nil {
		log.Printf("attachment store init failed (%s): attachments disabled: %v", cfg.AttachmentDir, err)
	}
	deps := mailapi.Deps{
		Secrets:        newSecretStore(cfg, db),
		OAuthReturnURL: cfg.OAuthReturnURL,
	}
	if blob != nil {
		deps.Blob = blob
	}
	if creds := oauthCreds(cfg); len(creds) > 0 {
		if ex := oauthx.New(creds); ex != nil {
			deps.OAuth = ex
			// XOAUTH2 IMAP fetch reuses the access tokens the exchanger mints, so the
			// sync source is only meaningful once OAuth is configured.
			deps.Source = imapx.New(deps.Secrets, nil)
			log.Printf("oauth/imap adapters enabled for %d provider(s)", len(creds))
		}
	}
	if cfg.SMTPHost != "" || deps.OAuth != nil {
		deps.Sender = smtpx.NewWithOAuth(cfg.SMTPHost, cfg.SMTPPort, cfg.SMTPUser, cfg.SMTPPassword, deps.Secrets, deps.OAuth, deps.Blob)
	}
	return NewWithDeps(cfg, db, deps)
}

// newSecretStore selects the OAuth credential store. When MAILANCHOR_SECRET_ENCRYPTION_KEY
// is configured, credentials are encrypted at rest with AES-256-GCM (R0001 stage 5);
// otherwise the in-memory dev store is kept (unchanged default). A configured-but-unusable
// key logs and falls back rather than blocking boot (Redis/FileForge degradation style).
func newSecretStore(cfg config.Config, db *sql.DB) mailapi.SecretStore {
	if db != nil {
		key := cfg.SecretEncryptionKey
		if len(key) == 0 {
			log.Printf("oauth secret store: SQL-backed plaintext dev mode; set MAILANCHOR_SECRET_ENCRYPTION_KEY to encrypt stored OAuth credentials")
		} else {
			log.Printf("oauth secret store: SQL-backed AES-256-GCM encryption enabled")
		}
		return mailapi.NewSQLSecretStore(db, key)
	}
	log.Printf("oauth secret store: in-memory fallback (no DB handle)")
	return mailapi.NewMemSecretStore()
}

// corsMiddleware applies a minimal CORS policy for the configured allow-origins
// (ALLOWED_ORIGIN, stage 2). It echoes the origin when it matches (supporting "*"),
// advertises the methods/headers the API uses, and short-circuits preflight OPTIONS.
func corsMiddleware(allowed []string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" && originAllowed(allowed, origin) {
				w.Header().Set("Access-Control-Allow-Origin", origin)
				w.Header().Set("Vary", "Origin")
				w.Header().Set("Access-Control-Allow-Credentials", "true")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-TOTP-Code")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func originAllowed(allowed []string, origin string) bool {
	for _, candidate := range allowed {
		if candidate == "*" || candidate == origin {
			return true
		}
	}
	return false
}

// oauthCreds maps the config provider credentials into the oauthx port type.
func oauthCreds(cfg config.Config) map[string]oauthx.Creds {
	out := map[string]oauthx.Creds{}
	for name, p := range cfg.OAuth {
		out[name] = oauthx.Creds{
			ClientID:     p.ClientID,
			ClientSecret: p.ClientSecret,
			RedirectURI:  p.RedirectURI,
		}
	}
	return out
}

func oauthProviderNames(cfg config.Config) []string {
	names := make([]string, 0, len(cfg.OAuth))
	for name := range cfg.OAuth {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// NewWithDeps builds the router with explicit mail dependencies. Tests use this to
// inject fakes (Sender/ChangeSource/OAuth) and a controllable clock.
func NewWithDeps(cfg config.Config, db *sql.DB, deps mailapi.Deps) http.Handler {
	store := auth.NewStore(db)
	svc := auth.NewService(store, cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	// Shared store (R0001 stage 3+5): token blacklist + OAuth state. A configured Redis is
	// shared across instances; if it is unreachable we log and keep the in-process defaults
	// rather than blocking boot (FileForge-bridge degradation style). One Redis instance
	// backs both the auth blacklist (stage 3) and the OAuth front-channel state (stage 5),
	// so authorize/callback can span instances.
	if cfg.Redis.Enabled() {
		if rs, err := sharedstore.NewRedisStore(sharedstore.Options{
			Host:     cfg.Redis.Host,
			Port:     cfg.Redis.Port,
			DB:       cfg.Redis.DB,
			Password: cfg.Redis.Password,
			SSL:      cfg.Redis.SSL,
		}); err != nil {
			log.Printf("redis shared-store disabled (falling back to in-process store): %v", err)
		} else {
			svc.WithSharedStore(rs)
			// Move OAuth state to the shared store too (stage 5), unless the caller injected
			// its own States port (tests). NewHandlers fills a MemStateStore when still nil.
			if deps.States == nil {
				deps.States = mailapi.NewSharedStateStore(rs)
				log.Printf("oauth state store: backed by redis shared-store (stage 5)")
			}
			log.Printf("redis shared-store enabled (%s:%d db=%d)", cfg.Redis.Host, cfg.Redis.Port, cfg.Redis.DB)
		}
	}
	// FileForge token-sharing bridge (mailanchor.ui.0003 T1): accept RS256 tokens minted
	// by FileForge when its public key is configured. A malformed key disables the bridge
	// (logged) rather than blocking boot — self-issued HS256 auth keeps working.
	//
	// bridgeStatus is surfaced on /healthz so a misconfigured deployment is detectable at
	// boot/probe time instead of only when a user's GET /accounts 401s (server.0004 NR0003,
	// cause A): in the FileForge-absorb topology the client presents RS256 FileForge tokens,
	// so an unset/invalid key makes EVERY protected request 401 with no operator-facing signal.
	// bridgeStatus is a closure so /healthz reflects the *current* state: a lazily-armed
	// bridge reports "pending" until its key file appears, then "enabled" (0017 NR0003).
	bridgeStatus := func() string { return "disabled" }
	switch {
	case cfg.FileForge.Enabled():
		// Key material already loaded at boot (inline PEM, or file readable at boot).
		if fv, err := auth.NewFederatedVerifier(cfg.FileForge.PubKeyPEM, cfg.FileForge.Issuer, cfg.FileForge.Audience); err != nil {
			log.Printf("fileforge token bridge disabled (bad public key): %v", err)
		} else {
			svc.WithFederation(fv)
			bridgeStatus = fv.Status
			log.Printf("fileforge token bridge enabled (issuer=%q audience=%q)", cfg.FileForge.Issuer, cfg.FileForge.Audience)
		}
	case cfg.FileForge.KeyFile != "":
		// A key file is configured but was not readable at boot — arm the bridge lazily so
		// it self-heals once the key appears, instead of staying disabled until a manual
		// restart (0017 NR0003 boot-order race: Go started before FileForge wrote the key).
		fv := auth.NewLazyFederatedVerifier(cfg.FileForge.KeyFile, cfg.FileForge.Issuer, cfg.FileForge.Audience)
		svc.WithFederation(fv)
		bridgeStatus = fv.Status
		log.Printf("fileforge token bridge armed (lazy): pubkey not readable at boot, "+
			"will load on first federated request from %s", cfg.FileForge.KeyFile)
	default:
		// No pubkey configured -> the bridge is OFF and only self-issued HS256 tokens are
		// accepted. Log it loudly: a FileForge-absorb deployment that forgets the key will
		// 401 every federated request, and the previous silence hid that until a user hit it.
		log.Printf("fileforge token bridge OFF: no MAILANCHOR_FILEFORGE_JWT_PUBKEY[_FILE] set; " +
			"only self-issued HS256 tokens are accepted (federated RS256 tokens will 401)")
	}
	authH := auth.NewHandlers(svc)
	apiH := mailapi.NewHandlers(mailapi.NewStore(db), deps)

	r := chi.NewRouter()
	// RealIP rewrites RemoteAddr from X-Forwarded-For. Only enable it behind a trusted
	// reverse proxy (NR0011 S3): otherwise a client rotates XFF to evade the per-IP
	// login lockout. When OFF, clientIP() uses the direct peer address.
	if cfg.TrustProxy {
		r.Use(middleware.RealIP)
	}
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))
	// CORS (stage 2, ALLOWED_ORIGIN). Mounted only when origins are configured so the
	// default (same-origin) behaviour is unchanged. FileForge's main.py applies CORS from
	// ALLOWED_ORIGIN; we mirror that with a dependency-free middleware.
	if len(cfg.AllowedOrigins) > 0 {
		r.Use(corsMiddleware(cfg.AllowedOrigins))
	}

	r.Route(cfg.Context, func(api chi.Router) {
		oauthProviders := oauthProviderNames(cfg)
		api.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
			httpx.OK(w, http.StatusOK, map[string]any{
				"status":           "ok",
				"fileforge_bridge": bridgeStatus(),
				"oauth_configured": len(oauthProviders) > 0,
				"oauth_providers":  oauthProviders,
			})
		})

		// authentication(A) — P0007 §6.1
		api.Post("/auth/login", authH.Login)
		api.Post("/auth/refresh", authH.Refresh)
		api.Post("/auth/logout", authH.Logout)
		api.Get("/auth/session", authH.Session)

		// public(unauthenticated) — OAuth front-channel callback. The provider redirects the
		// browser here after consent (no JWT); it authenticates via the one-time state
		// (server.0005 NR0009 gap A).
		apiH.MountPublic(api)

		// protected route group — text(C)·compose(D)·management(M)·sync(F) endpoints.
		api.Group(func(pr chi.Router) {
			pr.Use(authH.RequireAuth)
			pr.Get("/me", func(w http.ResponseWriter, r *http.Request) {
				uid, _ := auth.UserID(r.Context())
				httpx.OK(w, http.StatusOK, map[string]any{"user_id": uid})
			})
			// 2FA(TOTP) management — R0001 stage 4 (MailAnchor /2fa/* text). all require authentication.
			pr.Get("/auth/2fa/status", authH.TOTPStatus)
			pr.Post("/auth/2fa/setup", authH.TOTPSetup)
			pr.Post("/auth/2fa/activate", authH.TOTPActivate)
			pr.Post("/auth/2fa/disable", authH.TOTPDisable)
			pr.Post("/auth/2fa/regenerate-recovery", authH.TOTPRegenerateRecovery)
			apiH.Mount(pr)
		})
	})

	return r
}
