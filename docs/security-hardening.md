# FileForge public-service security hardening — 2026-11-08

## Scope and deployment boundary

This change hardens the application code on `main`. It does **not** change the
running server, its environment, Caddy, firewall rules, DNS, or Cloudflare rules.
No production files/accounts were accessed and no live brute-force test was run.
This is not a claim that the entire service has passed a penetration test.

## Object authorization

`security/access.py` is mounted as a dependency on **both** storage routers in
`routers/main.py`. It authenticates the JWT subject, resolves user/group identity
from the database, and checks the actual storage and mode for each target node.
Client identity fields are compatibility inputs, never credentials. A different
user/group, a different node storage, inactive storage, a disallowed operation,
and duplicate identifier parameters are rejected before the legacy handler runs.

Listing, folder trees, single download/delete, rename, content edits, folder
creation, uploads (including destination parent), and bulk operations are covered.
Bulk requests preflight all targets before performing any operation; an invalid
mixed batch does not partially delete files. A batch is limited to 500 targets.
Existing user grants and explicit group grants are retained; a group is looked up
from the signed-in user, not trusted from the request.

Shared-link creation checks access and the real node type in the service layer.
A public link is no longer usable after its creator loses read access to the
storage. These checks do not re-encrypt or relocate any existing file/vault data.

## Authentication and abuse controls

Redis Lua operations provide atomic counters and single-use markers shared across
workers. They are independent of the existing per-module SlowAPI instances.
Redis failure rejects security-sensitive requests with 503; there is no in-memory
or fail-open fallback. 429 replies contain `Retry-After`.

| Budget | Limit |
|---|---|
| Password login, per source IP | 60 / 5 minutes |
| Password login, per normalized account | 10 / 5 minutes; reset after success |
| TOTP envelope verification, per source IP | 60 / 5 minutes |
| TOTP verification/security changes, per source IP | 30 / 5 minutes |
| TOTP verification/security changes, per user | 5 / 5 minutes |
| TOTP setup, per user | 5 / 5 minutes |
| Refresh, per source IP | 120 / 5 minutes |
| Public share access, per source IP | 120 / minute |
| Share password attempts, per link | 20 / 5 minutes; reset after success |
| Share creation, per user | 30 / 5 minutes |

TOTP-pending tokens have a unique nonce, and successful pending tokens and OTPs
cannot be reused. The authenticator's **next** code is required when another
security action follows immediately. Enabled TOTP cannot be replaced through
`/setup`. Activation and disabling revoke other sessions and the legacy refresh
record. Refresh tokens get a unique `jti`, including rotations within one second.
The existing RS256 access-token and multi-session contracts are preserved.

## Share-password compatibility

New hashes use PBKDF2-HMAC-SHA256 (600,000 iterations), a random 128-bit salt and a
192-bit derived key, compared in constant time. The versioned 64-character
representation fits the existing VARCHAR(64) schema; no destructive migration or
password reset is needed. Successful legacy SHA-256 verification upgrades that
link using a conditional update. Invalid passwords never trigger an upgrade.

Legacy query-string passwords remain accepted for client compatibility. New
integrations should use `X-Share-Password`. Query strings can still enter browser
history or upstream access logs; configure upstream log redaction accordingly.
Correct protected downloads reset the failed-password budget, so navigating a
protected folder does not consume a permanent guess allowance.

## HTTP surface and logs

Login access tokens, OTPs, temporary-token fragments and share passwords are no
longer logged by the modified authentication/share routes. Validation errors do
not log bodies or echo Pydantic's `input`/`ctx`. Unauthenticated debug/example
routes and public OpenAPI/Swagger/Redoc routes are removed.

A pure-ASGI middleware adds `Cache-Control: private, no-store`, `nosniff`,
`Referrer-Policy: no-referrer` and `X-Frame-Options: DENY` without buffering file
streams. Raw X-Forwarded-For/X-Real-IP values are not re-trusted by session labels;
the source identity comes from Uvicorn's already-resolved peer. CORS no longer
combines wildcard origins with credentialed requests. This does **not** make a
wildcard an origin allowlist; production still needs explicit allowed origins.

## Required operational checks before considering deployment hardened

- Set `ALLOWED_ORIGIN` to the actual trusted web origin(s), not `*`.
- Verify `SECRET_KEY` is long/random and not the sample placeholder. **Do not
  blindly rotate it:** it also protects existing encrypted mail credentials;
  rotation requires a migration/backup plan.
- Keep Redis and the application listener off the public Internet. Verify the
  Redis ACL permits the Lua/counter operations, with appropriate authentication.
- Configure Uvicorn's trusted proxy peers narrowly, and Caddy's trusted proxy
  chain correctly. Never use arbitrary X-Forwarded-For or `forwarded-allow-ips=*`
  on a directly reachable listener. Otherwise IP budgets may be bypassed or all
  visitors may be counted as one proxy.
- Check the actual Cloudflare proxy/WAF/cache rules and restrict origin access
  where appropriate. DNS records were not changed or independently verified here.
- Apply request-body/concurrency limits in the reverse proxy; this patch does not
  redesign the legacy in-memory upload/ZIP paths or conduct a full mail/OS audit.
- Back up, update the application, restart it, then verify login, MFA, file
  operations, shares, mail and vault using authorized test accounts. Confirm real
  429/503 behavior and origin-IP handling without attacking production accounts.

## Regression verification

`python -m pytest server/tests/security -q` covers object-scope denial, forged
identities, read/write/group grants, mixed batches before side effects, replay,
failed-closed counters, share-hash upgrades and unchanged streaming bytes.
Authentication route tests use real production JWT/password/limiter dependencies
but isolated database/TOTP/session seams. They skip on offline environments
missing those dependencies rather than substituting fake cryptography.

The `Server security regression` workflow installs server requirements, compiles
all server modules, and runs `server/tests` (existing session tests plus the new
security suite). Its disposable Redis 7 service runs the abuse-counter and replay
Lua scripts for real; local authorization tests use isolated SQLite and a Redis
double. Infrastructure settings and browser-level production workflows are not
certified by these unit/integration tests.
