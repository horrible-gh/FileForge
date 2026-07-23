import jwt
import redis
from datetime import datetime, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from config import settings, redis_client, db

from . import jwt_keys, session_store

import LogAssist.log as Logger

# JWT translated text (refresh/legacy HS256 text; accesstext RS256text jwt_keystext verify)
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# routers/main.py child text importtext (text blacklist translated text Redis text)
token_blacklist = set()

def is_token_blacklisted(token: str) -> bool:
    try:
        return redis_client.exists(f"blacklist:{token}") > 0
    except redis.RedisError:
        return False  # Redis text text fail-open

def _assert_session_alive(user_id: str, sid: str | None) -> None:
    """Refuse requests whose session has been terminated (D0003 §3.2/§3.4).

    Placed inside ``verify_token`` on purpose: every authenticated route already depends on it
    (116 call sites across 16 files), so session-scoped revocation reaches all of them without
    a single caller change (NR0005 F3/F4).

    A token with no ``sid`` predates this feature and is honoured for its remaining lifetime —
    access tokens live 30 minutes, so the transition window closes on its own and nobody is
    logged out by the deploy (D0003 §6).

    Unlike the per-token blacklist above this is **fail-closed**: if Redis is unreachable we
    cannot tell a live session from a revoked one, and guessing "live" would resurrect sessions
    the user explicitly killed (NR0005 G2). 503 rather than 401 so the client retries instead of
    tearing down credentials that are probably still valid.
    """
    if not sid:
        return
    try:
        alive = session_store.check_and_touch(user_id, sid)
    except redis.RedisError:
        Logger.error("[Auth] session store unreachable; refusing request (fail-closed)")
        raise HTTPException(status_code=503, detail="session_store_unavailable")
    if not alive:
        raise HTTPException(status_code=401, detail="session_revoked")


def verify_token(token: str = Depends(oauth2_scheme)):
    return verify_token_payload(token)["sub"]


def verify_token_payload(token: str = Depends(oauth2_scheme)) -> dict:
    """``verify_token`` that keeps the JWT payload instead of collapsing it to ``sub``.

    ``verify_token`` returns a bare user id and 116 call sites depend on that shape, so the
    session routes get this parallel dependency rather than a changed return type (NR0005 F3).
    """
    credentials_exception = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        if is_token_blacklisted(token):
            raise HTTPException(status_code=401, detail="Token has been logged out")

        payload = jwt_keys.verify_access(token, verify_exp=True)
        user_id: str = payload.get("sub")
        exp: int = payload.get("exp")
        totp_pending: bool = payload.get("totp_pending", False)
        token_type: str = payload.get("type", "access")

        if user_id is None or exp is None:
            raise credentials_exception

        # totp_pending tokentext text API text text
        if totp_pending:
            raise HTTPException(status_code=401, detail="2FA verification required")

        # refresh_tokentext text API text text
        if token_type == "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")

        if datetime.now(timezone.utc) > datetime.fromtimestamp(exp, timezone.utc):
            raise HTTPException(status_code=401, detail="Token has expired")

        _assert_session_alive(user_id, payload.get("sid"))

        return payload

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise credentials_exception


def current_user_uuid(user_id: str = Depends(verify_token)) -> str:
    """Resolve the authenticated JWT subject to the users.user_uuid primary key.

    `verify_token` returns the JWT ``sub`` claim, which carries the string
    ``users.user_id`` (login mints ``sub = user["user_id"]``), NOT the UUID PK.
    The absorbed mail subsystem keys every row on ``user_uuid`` and
    ``mail_accounts.user_uuid`` is an FK to ``users(user_uuid)``; feeding the string
    user_id straight in makes the OAuth account INSERT fail with MySQL 1452
    (fileforge.mailanchorpython.0004.0003-NR). Resolving here is the single
    token→uuid boundary the mail routers must depend on.
    """
    row = db.db_instance.fetch_one(
        db.sqloader.load_sql("file_forge", "get_user_uuid_by_user_id"),
        user_id,
    )
    if not row or not row.get("user_uuid"):
        raise HTTPException(
            status_code=401,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return row["user_uuid"]


def current_session(payload: dict = Depends(verify_token_payload)) -> tuple[str, str | None]:
    """``(user_id, sid)`` for the calling request; ``sid`` is None for pre-session tokens."""
    return payload.get("sub"), payload.get("sid")

