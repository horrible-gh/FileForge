"""Per-login session store backing multi-device sign-in (fileforge.default.0004 T1).

Before this module a whole account shared ONE refresh key (``refresh:{user_id}``), so a
second device's login overwrote the first device's refresh token and a single logout wiped
every device (D0003 목적, NR0005 F1). Sessions replace that account-wide key with a
per-login record identified by a session id (``sid``) that rides in both the access and the
refresh token.

Redis layout (D0003 §7.2 — no DB tables; sessions are as volatile as refresh tokens):

===============================  ======  ==========================================
key                              type    contents
===============================  ======  ==========================================
``sessions:{user_id}``           ZSET    member = sid, score = last-used epoch seconds
``session:{user_id}:{sid}``      HASH    device_label, client_type, ip_display, created_at
``session_refresh:{user_id}:{sid}``  STR the session's current refresh token
===============================  ======  ==========================================

The ZSET is the single source of truth for "is this session alive" and for ordering: it
answers liveness (ZSCORE), the session list (ZREVRANGE), and LRU eviction (ZRANGE) from one
structure, and D0003 §7.2 already names the account session list as the tie-breaker when the
list and the per-session metadata disagree. Liveness is therefore a *positive* membership
check rather than a revocation tombstone — a revoked session vanishes from the ZSET, so its
outstanding access tokens are refused on the very next request without waiting for expiry
(D0003 §3.4).

Last-used lives in the ZSET score, not in the metadata hash, so the 5-minute touch
(D0003 §7.1) costs one ZADD and never rewrites the hash.

**TTL is sliding.** Every create and every refresh rotation re-applies ``SESSION_TTL_SECONDS``
to all three keys, mirroring the pre-existing ``setex`` on the account-wide refresh key. Without
this a daily-used device would still be evicted 7 days after its *first* login (NR0005 F10-b/G5).

Redis errors are NOT swallowed here. Callers decide: the session gate in ``auth.verify_token``
is fail-closed (a revoked session must not come back to life during a Redis outage), while the
older per-token blacklist stays fail-open as it always was (NR0005 F8 / G2).
"""

import time
import uuid

from config import redis_client, settings

# D0003 §7.1: session lifetime == refresh-token lifetime. Two separate lifetimes would
# eventually disagree and produce logouts nobody can explain.
SESSION_TTL_SECONDS = settings.REFRESH_TOKEN_EXPIRE_DAYS * 86400

# D0003 §7.1: enough for PC + laptop + phone + tablet + a couple of browsers, low enough that
# a stolen credential cannot farm sessions without end.
MAX_SESSIONS_PER_USER = 10

# D0003 §7.1: a file-listing burst must not rewrite the session record on every request; the
# list screen does not need minute-accurate "last used".
LAST_USED_THROTTLE_SECONDS = 300


def _list_key(user_id: str) -> str:
    return f"sessions:{user_id}"


def _meta_key(user_id: str, sid: str) -> str:
    return f"session:{user_id}:{sid}"


def _refresh_key(user_id: str, sid: str) -> str:
    return f"session_refresh:{user_id}:{sid}"


def new_session_id() -> str:
    return uuid.uuid4().hex


# -- device / origin labelling ------------------------------------------------------------
# FlowGate derives these server-side from the User-Agent (NR0005 §6). FileForge is a native
# app whose UA carries no useful device name, so a client-supplied label wins and UA parsing
# is only the fallback (D0003 §3.1).

def parse_device_label(user_agent: str | None) -> str:
    ua = (user_agent or "").lower()
    for needle, label in (
        ("android", "Android"),
        ("iphone", "iPhone"),
        ("ipad", "iPad"),
        ("windows", "Windows"),
        ("macintosh", "macOS"),
        ("mac os", "macOS"),
        ("linux", "Linux"),
    ):
        if needle in ua:
            return label
    return "Unknown device"


def resolve_ip_display(request) -> str:
    """Left-most X-Forwarded-For entry, else the socket peer.

    The left-most hop is the original client; the proxy appends itself on the right. Without
    this every session behind a reverse proxy would show the proxy's address.
    """
    if request is None:
        return ""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        first = forwarded.split(",")[0].strip()
        if first:
            return first
    real_ip = request.headers.get("x-real-ip")
    if real_ip:
        return real_ip.strip()
    client = getattr(request, "client", None)
    return getattr(client, "host", "") or ""


def describe_request(request) -> dict:
    """Collect the session's origin fields from an incoming login request."""
    if request is None:
        return {"device_label": "Unknown device", "client_type": "", "ip_display": ""}
    user_agent = request.headers.get("user-agent")
    # T3 will send X-Device-Name; until then the UA fallback keeps the list readable.
    device_label = (request.headers.get("x-device-name") or "").strip()
    return {
        "device_label": device_label or parse_device_label(user_agent),
        "client_type": (user_agent or "")[:200],
        "ip_display": resolve_ip_display(request),
    }


# -- lifecycle ----------------------------------------------------------------------------

def create_session(
    user_id: str,
    refresh_token: str,
    *,
    device_label: str = "",
    client_type: str = "",
    ip_display: str = "",
    sid: str | None = None,
    now: float | None = None,
) -> tuple[str, list[str]]:
    """Register a new session and return ``(sid, evicted_sids)``.

    Over-limit logins evict the least-recently-used session instead of being refused: the user
    plainly means to sign in on the new device and has no way to free a slot from there
    (D0003 §3.1).
    """
    sid = sid or new_session_id()
    now = time.time() if now is None else now

    evicted = _evict_over_limit(user_id, incoming=1)

    pipe = redis_client.pipeline()
    pipe.zadd(_list_key(user_id), {sid: now})
    pipe.expire(_list_key(user_id), SESSION_TTL_SECONDS)
    pipe.hset(
        _meta_key(user_id, sid),
        mapping={
            "device_label": device_label or "Unknown device",
            "client_type": client_type or "",
            "ip_display": ip_display or "",
            "created_at": str(int(now)),
        },
    )
    pipe.expire(_meta_key(user_id, sid), SESSION_TTL_SECONDS)
    pipe.setex(_refresh_key(user_id, sid), SESSION_TTL_SECONDS, refresh_token)
    pipe.execute()
    return sid, evicted


def _evict_over_limit(user_id: str, incoming: int = 1) -> list[str]:
    """Drop the oldest sessions so that ``count + incoming <= MAX_SESSIONS_PER_USER``."""
    key = _list_key(user_id)
    overflow = redis_client.zcard(key) + incoming - MAX_SESSIONS_PER_USER
    if overflow <= 0:
        return []
    # Ascending by score == least recently used first.
    victims = redis_client.zrange(key, 0, overflow - 1)
    for victim in victims:
        revoke_session(user_id, victim)
    return list(victims)


def is_session_alive(user_id: str, sid: str) -> bool:
    return redis_client.zscore(_list_key(user_id), sid) is not None


def check_and_touch(user_id: str, sid: str, now: float | None = None) -> bool:
    """Liveness check for the request path, with a throttled last-used update folded in.

    One ZSCORE answers both questions, so the gate costs a single extra round trip per request
    and the touch only writes once per ``LAST_USED_THROTTLE_SECONDS`` (NR0005 F11).
    """
    now = time.time() if now is None else now
    score = redis_client.zscore(_list_key(user_id), sid)
    if score is None:
        return False
    if now - float(score) >= LAST_USED_THROTTLE_SECONDS:
        redis_client.zadd(_list_key(user_id), {sid: now})
    return True


def get_refresh_token(user_id: str, sid: str) -> str | None:
    return redis_client.get(_refresh_key(user_id, sid))


def rotate_refresh_token(user_id: str, sid: str, refresh_token: str, now: float | None = None) -> None:
    """Swap in the rotated refresh token and slide every session key's TTL forward."""
    now = time.time() if now is None else now
    pipe = redis_client.pipeline()
    pipe.setex(_refresh_key(user_id, sid), SESSION_TTL_SECONDS, refresh_token)
    pipe.zadd(_list_key(user_id), {sid: now})
    pipe.expire(_list_key(user_id), SESSION_TTL_SECONDS)
    pipe.expire(_meta_key(user_id, sid), SESSION_TTL_SECONDS)
    pipe.execute()


def revoke_session(user_id: str, sid: str) -> bool:
    """Terminate one session. Returns False if it was already gone."""
    pipe = redis_client.pipeline()
    pipe.zrem(_list_key(user_id), sid)
    pipe.delete(_meta_key(user_id, sid))
    pipe.delete(_refresh_key(user_id, sid))
    removed = pipe.execute()[0]
    return bool(removed)


def revoke_other_sessions(user_id: str, keep_sid: str | None) -> int:
    """Terminate every session except ``keep_sid``. Returns how many were terminated."""
    victims = [s for s in redis_client.zrange(_list_key(user_id), 0, -1) if s != keep_sid]
    for victim in victims:
        revoke_session(user_id, victim)
    return len(victims)


def list_sessions(user_id: str, current_sid: str | None = None) -> list[dict]:
    """Sessions newest-used first, with the current one flagged.

    The ZSET is authoritative: metadata for a sid that is no longer listed is stale and gets
    cleaned up here, and a listed sid whose metadata expired still shows up with blanks rather
    than disappearing (D0003 §7.2).
    """
    entries = redis_client.zrevrange(_list_key(user_id), 0, -1, withscores=True)
    sessions = []
    for sid, score in entries:
        meta = redis_client.hgetall(_meta_key(user_id, sid)) or {}
        sessions.append(
            {
                "sid": sid,
                "device_label": meta.get("device_label", "Unknown device"),
                "client_type": meta.get("client_type", ""),
                "ip_display": meta.get("ip_display", ""),
                "created_at": int(meta.get("created_at") or int(score)),
                "last_used_at": int(score),
                "is_current": sid == current_sid,
            }
        )
    return sessions


def drop_legacy_refresh(user_id: str) -> None:
    """Remove the pre-session account-wide refresh key once its holder has migrated (D0003 §6)."""
    redis_client.delete(f"refresh:{user_id}")
