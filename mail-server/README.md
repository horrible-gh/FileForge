# mailanchord — MailAnchor Go backend (Phase 0 base)

R0001 MailAnchor merge initial implementation base. The design contracts
(P0007, L0010, L0011, DB0008) are the source of truth.
This is a cgo-free single-binary Go service. Mail, management, and sync
Phase 1 work builds on this base (NR0003 section 6).

## What is included (Phase 0)
- **config** — env text text. token TTL default value = L0010 §1(access 900s, refresh 30text).
- **DB translated text** — DB0008 001~012 + **013(external_ref, NR0003 §5.E text)**. SQLite dialect, `embed`text text, `schema_migrations`text text. FK text(ON), textminutes translated text text.
- **text text** — P0007 §1 success/error text + error translated text 13text(P0007 §5).
- **authentication(A)** — P0007 §6.1 `/auth/login·refresh·logout·session`.
  - text **argon2id**(L0011 §1), login failed text(in-memory, L0011 §2.5), translated text textverify.
  - access **textstate HS256 JWT**(L0010: DB textsave), refresh **translated text opaque**(translated text save, translated text text text text text — L0010 §2.1).
  - authentication translated text(Bearer) + `/me` text.

## Applied decisions (NR0003 §7)
- D1 authentication translated text = **Go text text**(`/auth/*` text). D2 Body = DB `body_content`. D3 external_ref = **translated text 013 add**. D4 text = DB0008 source of truth(star/pin/folder text).

## Build and run
```sh
go test ./...                 # unit tests + authentication text translated text
go build ./cmd/mailanchord
MAILANCHOR_JWT_SECRET=... ./mailanchord -seed-email a@b.com -seed-password pw   # translated text translated text text(translated text DEFERRED)
MAILANCHOR_JWT_SECRET=... ./mailanchord                                          # server startup(:8090, /api/v1)
```

## Environment variables
| text | default value | text |
|---|---|---|
| `MAILANCHOR_ADDR` | `:8090` | text text |
| `MAILANCHOR_CONTEXT` | `/api/v1` | API base path(P0007) |
| `MAILANCHOR_DB_PATH` | `./mailanchor.db` | SQLite file |
| `MAILANCHOR_SECRET_ENCRYPTION_KEY` | (None) | encrypt DB-backed OAuth credential blobs; blank stores plaintext dev blobs |
| `MAILANCHOR_JWT_SECRET` | (translated text text) | HS256 signaturetext — text required |
| `MAILANCHOR_ACCESS_TTL_SEC` | `900` | access TTL |
| `MAILANCHOR_REFRESH_TTL_SEC` | `2592000` | refresh TTL(30text) |
| `GOOGLE_CLIENT_ID` | (None) | Gmail OAuth translated text ID. translated text `/accounts/oauth/authorize?provider=gmail`text 503 `oauth not configured` |
| `GOOGLE_CLIENT_SECRET` | (None) | Gmail OAuth translated text secret |
| `GOOGLE_REDIRECT_URI` | (None) | Google Cloud Consoletext Authorized redirect URItext translated text text. local example: `http://localhost:8090/api/v1/accounts/oauth/callback` |
| `MAILANCHOR_OAUTH_RETURN_URL` | (None) | OAuth complete text translated text return to URL. translated text servertext text complete HTMLtext translated text |
| `MAILANCHOR_FILEFORGE_JWT_PUBKEY` | (None) | FileForge RS256 public key(PEM translated text). text text token-sharing bridge ON |
| `MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE` | (None) | text text file pathtext text(translated text not configured text) |
| `MAILANCHOR_FILEFORGE_ISSUER` | (None) | text `iss` claims(text text text) |
| `MAILANCHOR_FILEFORGE_AUDIENCE` | (None) | text `aud` claims(text text text) |

`MAILANCHOR_OAUTH_GMAIL_CLIENT_ID`, `MAILANCHOR_OAUTH_GMAIL_CLIENT_SECRET`,
`MAILANCHOR_OAUTH_GMAIL_REDIRECT_URI`text legacy fallbacktext translated text, text translated text
`GOOGLE_*`text translated text. `/api/v1/healthz`text `oauth_configured`text `oauth_providers`text
startup text OAuth text text translated text translated text text text.

> **`GOOGLE_*`text translated text servertext text text text**: text translated text server startuptext text translated text(not configuredtext
> `/accounts/oauth/authorize`text 503text text translated text). startup failedtext text translated text text text
> `MAILANCHOR_ADDR`(text `:8090`) **port conflict**text - text `mailanchord` instancetext text text
> translated text text translated text text translated text `bind: address already in use`text text translated text. text
> instancetext stop first(`taskkill /F /IM mailanchord.exe`)text text translated text translated text translated text text
> again startuptext. text `run-server.ps1` text `scripts/run-mail-server.ps1`text textstartup text translated text
> translated text translated text translated text translated text text build/startuptext.

## FileForge token-sharing bridge (implemented, mailanchor.ui.0003 T1)
translated text(Python FileForge ↔ Go) translated text **translated text text** text text authentication. FileForge public keytext translated text
translated text(`internal/auth/federated.go`).
- **text** — Bearer tokentext text text HS256text verifytext, *translated text translated text*(expiredtext as-is TOKEN_EXPIRED)
  FileForge public keytext **RS256** verifytext retrytext. translated text token `sub`(FileForge user id)text text
  local `app_user`text **text 1text just-in-time provisioning**(translated text 015 `external_subject`, translated text text·text text)text
  text text subjecttext idempotent textuses. `email`/`display_name` claimstext best-effort(translated text translated text text).
- **security** — RS256text allowed(`alg=HS256` confusion text), iss/aud text(text text), signature·expired verify.
- **verify** — unit tests(`federated_test.go`: provisioning·idempotent·expired/iss/aud/translated text/alg-confusion text) +
  **translated text local translated text 1text**: FileForge signature RS256 token translated text textserver `/me`·`/mails`·`/auth/session` = 200,
  textauthentication/text = 401, app_user 1text idempotent creation verified(completetext text).
- **issue text complete(mailanchor.ui.0003 T0004)** — FileForge(Python) `routers/login/jwt_keys.py`text access tokentext
  **RS256**text issue(private key signature, `email`/`display_name`/`iss`/`aud` claims text). refresh/totp-pendingtext translated text
  HS256 keep. **text live smoke test**: FileForgetext text signaturetext RS256 token 1text Go `/me`·`/mails`·`/auth/session` = 200,
  `app_user`text `email=smoke@fileforge.example`·`display_name`text token claimstext text(text text), idempotent 1text text.

## Phase 1 — DB-only translated text (implemented, `internal/mailapi`)
protected route grouptext translated text(text access text):
- **text(M)** — `GET/POST /labels`, `PATCH/DELETE /labels/{id}`. LABEL_DUPLICATE(409), translated text text text(403).
- **text(M)** — `GET/PATCH /settings/display`, `GET/PATCH /settings/sync`. text verify(VALIDATION_FAILED).
- **text textpath(C)** — `GET /mails`(text text·text/text/unread text, L0012 §2.1), `GET /mails/{id}`(text+text+text), `PATCH /mails/{id}`(is_read·labels_add/remove translated text, L0012 §2.5).
- `Store.SeedMail`text sync(F)text text translated text text text translated text/translated text(HTTP textpathtext not implemented).

## Phase 1 — remaining work (depends on external services, text text)
- **text(D)/SMTP, sync(F)/IMAP, account OAuth, text bytes** — text MailAnchor(Python) translated text go-imap/go-message/go-smtp/x/oauth2/go-redistext text. Ftext translated text 013(external_ref) text(L0013) text.
- Production transition: HS256 to RS256 is complete on both receiving and
  issuing sides through the FileForge token-sharing bridge. End-to-end local
  verification is complete. Accept-Language negotiation and multi-dialect
  MySQL/PostgreSQL migrations remain.
- **T3 SMTP — text translated text addtext**: `smtpx`text **translated text text translated text text translated text**(`sender_send_test.go`: text TCP translated text net/smtp EHLO→MAIL→RCPT→DATA→QUIT text, translated text To+Cc+**Bcc** text·translated text Bcc translated text verify)text addtext. text translated text `build()`text translated text. text text **text text** translated text *text account/translated text* translated text text.
- **T2 IMAP / T3 real account / T4 Gmail OAuth / T5 E2E — real account live smoke test remaining work**: Gmail OAuth accounts send through SMTP XOAUTH2 without `MAILANCHOR_SMTP_HOST`; non-OAuth/password accounts still require `MAILANCHOR_SMTP_*`. OAuth credentials are stored in the DB-backed SecretStore and should be encrypted with `MAILANCHOR_SECRET_ENCRYPTION_KEY`. Real Gmail live smoke still requires a connected test account.
