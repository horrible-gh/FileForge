// Package server wires the HTTP router for the MailAnchor Go backend.
package server

import (
	"database/sql"
	"log"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"

	"mailanchor/serverd/internal/auth"
	"mailanchor/serverd/internal/config"
	"mailanchor/serverd/internal/httpx"
	"mailanchor/serverd/internal/imapx"
	"mailanchor/serverd/internal/mailapi"
	"mailanchor/serverd/internal/oauthx"
	"mailanchor/serverd/internal/smtpx"
	"mailanchor/serverd/internal/storage"
)

// New builds the application router with the production external-service ports
// derived from cfg (disk attachment store, SMTP relay if configured, in-memory
// secret store). When OAuth client credentials are configured, the OAuth exchanger
// (oauthx) and the XOAUTH2 IMAP ChangeSource (imapx) are wired so the account/sync
// endpoints work for gmail/outlook; otherwise they stay nil and those endpoints
// answer UPSTREAM_UNAVAILABLE (unchanged behaviour).
func New(cfg config.Config, db *sql.DB) http.Handler {
	blob, err := storage.NewDiskStore(cfg.AttachmentDir)
	if err != nil {
		log.Printf("attachment store init failed (%s): attachments disabled: %v", cfg.AttachmentDir, err)
	}
	deps := mailapi.Deps{
		Secrets:        mailapi.NewMemSecretStore(),
		OAuthReturnURL: cfg.OAuthReturnURL,
	}
	if blob != nil {
		deps.Blob = blob
	}
	if cfg.SMTPHost != "" {
		deps.Sender = smtpx.New(cfg.SMTPHost, cfg.SMTPPort, cfg.SMTPUser, cfg.SMTPPassword, deps.Blob)
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
	return NewWithDeps(cfg, db, deps)
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

// NewWithDeps builds the router with explicit mail dependencies. Tests use this to
// inject fakes (Sender/ChangeSource/OAuth) and a controllable clock.
func NewWithDeps(cfg config.Config, db *sql.DB, deps mailapi.Deps) http.Handler {
	store := auth.NewStore(db)
	svc := auth.NewService(store, cfg.JWTSecret, cfg.AccessTTL, cfg.RefreshTTL)
	// FileForge token-sharing bridge (mailanchor.ui.0003 T1): accept RS256 tokens minted
	// by FileForge when its public key is configured. A malformed key disables the bridge
	// (logged) rather than blocking boot — self-issued HS256 auth keeps working.
	//
	// bridgeStatus is surfaced on /healthz so a misconfigured deployment is detectable at
	// boot/probe time instead of only when a user's GET /accounts 401s (server.0004 NR0003,
	// cause A): in the FileForge-absorb topology the client presents RS256 FileForge tokens,
	// so an unset/invalid key makes EVERY protected request 401 with no operator-facing signal.
	bridgeStatus := "disabled"
	if cfg.FileForge.Enabled() {
		if fv, err := auth.NewFederatedVerifier(cfg.FileForge.PubKeyPEM, cfg.FileForge.Issuer, cfg.FileForge.Audience); err != nil {
			log.Printf("fileforge token bridge disabled (bad public key): %v", err)
		} else {
			svc.WithFederation(fv)
			bridgeStatus = "enabled"
			log.Printf("fileforge token bridge enabled (issuer=%q audience=%q)", cfg.FileForge.Issuer, cfg.FileForge.Audience)
		}
	} else {
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

	r.Route(cfg.Context, func(api chi.Router) {
		api.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
			httpx.OK(w, http.StatusOK, map[string]any{"status": "ok", "fileforge_bridge": bridgeStatus})
		})

		// 인증(A) — P0007 §6.1
		api.Post("/auth/login", authH.Login)
		api.Post("/auth/refresh", authH.Refresh)
		api.Post("/auth/logout", authH.Logout)
		api.Get("/auth/session", authH.Session)

		// 공개(unauthenticated) — OAuth front-channel callback. The provider redirects the
		// browser here after consent (no JWT); it authenticates via the one-time state
		// (server.0005 NR0009 gap A).
		apiH.MountPublic(api)

		// 보호 라우트 그룹 — 메일(C)·작성(D)·관리(M)·동기화(F) 엔드포인트.
		api.Group(func(pr chi.Router) {
			pr.Use(authH.RequireAuth)
			pr.Get("/me", func(w http.ResponseWriter, r *http.Request) {
				uid, _ := auth.UserID(r.Context())
				httpx.OK(w, http.StatusOK, map[string]any{"user_id": uid})
			})
			apiH.Mount(pr)
		})
	})

	return r
}
