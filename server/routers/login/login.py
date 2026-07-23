from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel
import jwt
from datetime import datetime, timedelta, timezone
from config import settings, db, tfa, redis_client
from slowapi import Limiter
from slowapi.util import get_remote_address

from . import jwt_keys, session_store

import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

limiter = Limiter(key_func=get_remote_address)

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS
TOTP_PENDING_EXPIRE_MINUTES = 5

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def authenticate_user(username: str, password: str):
    user_pw = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_password"), username)
    if not user_pw or not verify_password(password, user_pw.get("password", "")):
        return False
    result = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), username)
    logger.debug(result)
    return result


def create_access_token(data: dict, expires_delta: timedelta):
    # Access tokens are RS256-signed so the Go server (MailAnchor) can verify them with
    # FileForge's public key alone — the polyglot token-sharing bridge (mailanchor.ui.0003
    # T1). iss/aud/exp are injected by jwt_keys.sign_access.
    return jwt_keys.sign_access(data, expires_delta)


def _access_claims(user_id: str, user: dict | None = None, sid: str | None = None) -> dict:
    """Assemble the federated access-token claims. email/display_name let the Go server
    provision a real local user instead of synthesizing a placeholder from `sub`.

    `sid` rides in the access token as well as the refresh token: carrying it only on refresh
    would leave ordinary requests with no session to check, so a terminated session could keep
    working until its access token expired (D0003 §7.3)."""
    claims = {"sub": user_id, "type": "access"}
    if sid:
        claims["sid"] = sid
    if user:
        if user.get("user_name"):
            claims["display_name"] = user["user_name"]
        if user.get("email"):
            claims["email"] = user["email"]
    return claims


def create_refresh_token(data: dict):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh"})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt


def _issue_session_tokens(request: Request, user_id: str, user: dict | None) -> dict:
    """Mint one login's token pair and register the session that owns it.

    The sid is generated first because both tokens must carry it and the refresh token is
    stored under it — replacing the account-wide `refresh:{user_id}` key that made a second
    device's login evict the first (D0003 §3.1, NR0005 F1).
    """
    sid = session_store.new_session_id()
    access_token = create_access_token(
        data=_access_claims(user_id, user, sid=sid),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
    _, evicted = session_store.create_session(
        user_id,
        refresh_token,
        sid=sid,
        **session_store.describe_request(request),
    )
    if evicted:
        logger.debug(f"[Login] session limit reached - evicted LRU sessions: {evicted}")
    return {"access_token": access_token, "refresh_token": refresh_token, "sid": sid}


class TotpVerifyRequest(BaseModel):
    temp_token: str
    code: str


class RefreshRequest(BaseModel):
    refresh_token: str


@router.post("/")
@router.post("")
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends()):
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")

    user_id = user["user_id"]

    totp_enabled = tfa.is_enabled(user_id)
    logger.debug(f"[Login] user_id: {user_id}, TOTP translated text text: {totp_enabled}")

    if totp_enabled:
        temp_token = create_access_token(
            data={"sub": user_id, "totp_pending": True},
            expires_delta=timedelta(minutes=TOTP_PENDING_EXPIRE_MINUTES),
        )
        logger.debug(f"[Login] temp_token issue - user_id: {user_id}")
        return {"totp_required": True, "temp_token": temp_token}

    tokens = _issue_session_tokens(request, user_id, user)
    logger.debug({"access_token": tokens["access_token"], "token_type": "bearer", "user": user})
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "token_type": "bearer",
        "user": user,
    }


@router.post("/totp/verify")
async def verify_totp_login(request: Request, body: TotpVerifyRequest):
    logger.debug(f"[TOTP Verify] request received - temp_token: {body.temp_token[:50]}..., code: {body.code}")

    credentials_exception = HTTPException(
        status_code=401,
        detail="token_expired",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        # temp_token is an RS256 access token carrying totp_pending=True.
        payload = jwt_keys.verify_access(body.temp_token, verify_exp=True)
        logger.debug(f"[TOTP Verify] JWT parsed successfully - payload: {payload}")
    except jwt.ExpiredSignatureError:
        logger.debug("[TOTP Verify] ❌ JWT expiredtext (ExpiredSignatureError)")
        raise HTTPException(status_code=401, detail="token_expired")
    except jwt.InvalidTokenError as e:
        logger.debug(f"[TOTP Verify] ❌ JWT parse failed (InvalidTokenError): {e}")
        raise credentials_exception

    user_id = payload.get("sub")
    totp_pending = payload.get("totp_pending", False)
    logger.debug(f"[TOTP Verify] extracted user_id: {user_id}, totp_pending: {totp_pending}")

    if not user_id or not totp_pending:
        logger.debug(f"[TOTP Verify] ❌ user_id text totp_pending None")
        raise credentials_exception

    logger.debug(f"[TOTP Verify] tfa.verify text - user_id: {user_id}, code: {body.code}")
    verify_result = tfa.verify(user_id, body.code)
    logger.debug(f"[TOTP Verify] tfa.verify result: {verify_result}")

    if not verify_result:
        logger.debug(f"[TOTP Verify] ❌ TOTP verify failed - user_id: {user_id}, code: {body.code}")
        raise HTTPException(status_code=401, detail="invalid_code")

    user = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), user_id)
    # The session is created here, not when the temp token was issued: a totp_pending token
    # cannot reach any API, so a session at that point would be a login that never happened
    # (D0003 §3.1).
    tokens = _issue_session_tokens(request, user_id, user)
    logger.debug(f"[TOTP Verify] ✅ login success - user_id: {user_id}")
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "token_type": "bearer",
        "user": user,
    }


@router.post("/refresh")
async def refresh(request: Request, body: RefreshRequest):
    credentials_exception = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    # Step 1: JWT signature/expired verify
    try:
        payload = jwt.decode(body.refresh_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise credentials_exception

    user_id: str = payload.get("sub")
    token_type: str = payload.get("type")
    sid: str | None = payload.get("sid")

    if not user_id or token_type != "refresh":
        raise credentials_exception

    # Step 2: blacklist text
    if redis_client.exists(f"blacklist:{body.refresh_token}") > 0:
        raise HTTPException(status_code=401, detail="Token has been logged out")

    if sid:
        # Step 3: match against THIS session's stored token. Rotation is now scoped to one
        # session, so two devices refreshing concurrently no longer invalidate each other
        # (D0003 §3.3).
        stored_token = session_store.get_refresh_token(user_id, sid)
        if stored_token is None or stored_token != body.refresh_token:
            raise credentials_exception
        if not session_store.is_session_alive(user_id, sid):
            raise HTTPException(status_code=401, detail="session_revoked")

        # Step 4/5: rotate in place. rotate_refresh_token also re-applies the TTL to every key
        # of this session, keeping session lifetime sliding the way the old account-wide setex
        # was — otherwise a daily-used device would die 7 days after its first login.
        new_refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
        session_store.rotate_refresh_token(user_id, sid, new_refresh_token)
    else:
        # Pre-session refresh token: honour it once and hand back a session-bearing pair, so
        # already-signed-in users migrate without being forced to log in again (D0003 §6).
        stored_token = redis_client.get(f"refresh:{user_id}")
        if stored_token is None or stored_token != body.refresh_token:
            raise credentials_exception
        sid = session_store.new_session_id()
        new_refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
        session_store.create_session(
            user_id,
            new_refresh_token,
            sid=sid,
            **session_store.describe_request(request),
        )
        session_store.drop_legacy_refresh(user_id)
        logger.debug(f"[Refresh] legacy refresh token migrated to session {sid} - user_id: {user_id}")

    # Step 6: text access token issue
    # NR0003 F3 / L0004 §2.8: re-issue with the SAME federated claim set as the
    # initial login (display_name/email), not a bare {"sub": user_id}. The Go
    # mail server provisions/refreshes a local user from these claims, so a
    # rotated access token that dropped them degraded federation after every
    # refresh. Re-fetch the user; fall back to sub-only if the lookup fails.
    refreshed_user = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), user_id)
    access_token = create_access_token(
        data=_access_claims(user_id, refreshed_user, sid=sid),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    logger.debug(f"[Refresh] ✅ token text complete - user_id: {user_id}")
    return {"access_token": access_token, "refresh_token": new_refresh_token, "token_type": "bearer"}
