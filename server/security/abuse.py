"""Redis-backed abuse limits shared across workers; Redis failure is fail-closed.

Independent of the legacy SlowAPI limiter instances: applying the global limiter
must not accidentally skip login/TOTP-specific checks. Never trust raw forwarded
headers here; Uvicorn must be configured to trust ONLY the local reverse proxy.
"""
import hashlib
import hmac
import unicodedata
from fastapi import HTTPException, Request
from config import redis_client, settings

# Count and attach the expiry atomically, including recovery from an old key
# that has no TTL. Blocked requests do not prolong the original fixed window.
_COUNTER = """
local n = redis.call('INCR', KEYS[1])
local ttl = redis.call('TTL', KEYS[1])
if ttl < 0 then redis.call('EXPIRE', KEYS[1], ARGV[1]); ttl = tonumber(ARGV[1]) end
return {n, ttl}
"""
_CONSUME = """
for i, key in ipairs(KEYS) do
  if redis.call('EXISTS', key) == 1 then return 0 end
end
for i, key in ipairs(KEYS) do redis.call('SET', key, '1', 'EX', ARGV[1]) end
return 1
"""


def _key(scope: str, value: str) -> str:
    digest = hmac.new(settings.SECRET_KEY.encode(), value.encode(), hashlib.sha256).hexdigest()
    return f"fileforge:security:{scope}:{digest}"


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def limit(scope: str, identity: str, attempts: int, seconds: int) -> None:
    try:
        count, ttl = redis_client.eval(_COUNTER, 1, _key(scope, identity), seconds)
    except Exception:
        # No tokens, account names, OTPs, or Redis connection secrets in errors.
        raise HTTPException(503, "security_store_unavailable", headers={"Retry-After": "5"}) from None
    if int(count) > attempts:
        raise HTTPException(429, "too_many_attempts", headers={"Retry-After": str(max(1, int(ttl)))})


def login_attempt(request: Request, username: str) -> None:
    limit("login-ip", client_ip(request), 60, 300)
    limit("login-user", unicodedata.normalize("NFKC", username).casefold(), 10, 300)


def clear_limit(scope: str, identity: str) -> None:
    try:
        redis_client.delete(_key(scope, identity))
    except Exception:
        raise HTTPException(503, "security_store_unavailable") from None


def login_success(username: str) -> None:
    clear_limit("login-user", unicodedata.normalize("NFKC", username).casefold())


def totp_attempt(request: Request, user_id: str) -> None:
    limit("totp-ip", client_ip(request), 30, 300)
    # Shared across login, disable, activate, and recovery-code regeneration.
    limit("totp-user", user_id, 5, 300)


def consume_totp(user_id: str, code: str, temp_token: str | None = None) -> None:
    normalized = unicodedata.normalize("NFKC", code).strip().replace(" ", "").replace("-", "").casefold()
    keys = [_key("otp-used", user_id + "\x00" + normalized)]
    if temp_token:
        keys.append(_key("pending-used", temp_token.rsplit(".", 1)[0]))
    try:
        consumed = redis_client.eval(_CONSUME, len(keys), *keys, 300)
    except Exception:
        raise HTTPException(503, "security_store_unavailable") from None
    if not consumed:
        raise HTTPException(401, "invalid_code")


async def limit_public_share(request: Request) -> None:
    # URL tokens are random capabilities, but link passwords still need limits.
    limit("share-ip", client_ip(request), 120, 60)
    # Password failures are counted by SharedLinkService.verify_password.
    # Successful protected downloads reset that budget, preserving folder use.
