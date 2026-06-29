from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel
import jwt
from datetime import datetime, timedelta, timezone
from config import settings, db, tfa, redis_client
from slowapi import Limiter
from slowapi.util import get_remote_address

from . import jwt_keys

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


def _access_claims(user_id: str, user: dict | None = None) -> dict:
    """Assemble the federated access-token claims. email/display_name let the Go server
    provision a real local user instead of synthesizing a placeholder from `sub`."""
    claims = {"sub": user_id, "type": "access"}
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

    access_token = create_access_token(
        data=_access_claims(user_id, user),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = create_refresh_token(data={"sub": user_id})
    redis_client.setex(f"refresh:{user_id}", REFRESH_TOKEN_EXPIRE_DAYS * 86400, refresh_token)
    logger.debug({"access_token": access_token, "token_type": "bearer", "user": user})
    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer", "user": user}


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
    access_token = create_access_token(
        data=_access_claims(user_id, user),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = create_refresh_token(data={"sub": user_id})
    redis_client.setex(f"refresh:{user_id}", REFRESH_TOKEN_EXPIRE_DAYS * 86400, refresh_token)
    logger.debug(f"[TOTP Verify] ✅ login success - user_id: {user_id}")
    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer", "user": user}


@router.post("/refresh")
async def refresh(body: RefreshRequest):
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

    if not user_id or token_type != "refresh":
        raise credentials_exception

    # Step 2: blacklist text
    if redis_client.exists(f"blacklist:{body.refresh_token}") > 0:
        raise HTTPException(status_code=401, detail="Token has been logged out")

    # Step 3: Redis savetext translated text token text
    stored_token = redis_client.get(f"refresh:{user_id}")
    if stored_token is None or stored_token != body.refresh_token:
        raise credentials_exception

    # Step 4: text Redis text delete
    redis_client.delete(f"refresh:{user_id}")

    # Step 5: text refresh token issue text Redis save
    new_refresh_token = create_refresh_token(data={"sub": user_id})
    redis_client.setex(f"refresh:{user_id}", REFRESH_TOKEN_EXPIRE_DAYS * 86400, new_refresh_token)

    # Step 6: text access token issue
    # NR0003 F3 / L0004 §2.8: re-issue with the SAME federated claim set as the
    # initial login (display_name/email), not a bare {"sub": user_id}. The Go
    # mail server provisions/refreshes a local user from these claims, so a
    # rotated access token that dropped them degraded federation after every
    # refresh. Re-fetch the user; fall back to sub-only if the lookup fails.
    refreshed_user = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), user_id)
    access_token = create_access_token(
        data=_access_claims(user_id, refreshed_user),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    logger.debug(f"[Refresh] ✅ token text complete - user_id: {user_id}")
    return {"access_token": access_token, "refresh_token": new_refresh_token, "token_type": "bearer"}
