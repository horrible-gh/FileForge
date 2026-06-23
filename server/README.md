# FileForge Server

FileForge Server Application

## RS256 access tokens — MailAnchor token-sharing bridge (mailanchor.ui.0003 T1, issuance side)

Access tokens are signed **RS256** (`routers/login/jwt_keys.py`) so the MailAnchor Go
server can verify them with FileForge's *public* key alone — no shared secret crosses the
polyglot boundary. Claims: `sub`, `email`, `display_name`, `iss`, `aud`, `iat`, `exp`.
Refresh tokens and the TOTP-pending temp token stay HS256 (FileForge-internal only).

Key resolution (see `.env.sample`): `JWT_PRIVATE_KEY` (inline PEM) → `JWT_PRIVATE_KEY_FILE`
→ `JWT_KEYS_DIR`/jwt_private.pem (loaded if present, else a keypair is generated and
persisted there on first boot). Export `jwt_public.pem` to the Go server via
`MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE`; `JWT_ISSUER`/`JWT_AUDIENCE` must match the Go
server's `MAILANCHOR_FILEFORGE_ISSUER`/`_AUDIENCE`.

Tests: `pytest tests/test_jwt_bridge.py` (RS256 round-trip, iss/aud enforcement,
alg-confusion rejection, key persistence, env loaders).
