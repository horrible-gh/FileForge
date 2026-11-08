from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
from pydantic import BaseModel, Field
import jwt
import secrets
from datetime import datetime, timedelta, timezone
from config import settings, db, tfa, redis_client
from slowapi import Limiter
from slowapi.util import get_remote_address
from . import jwt_keys, session_store
from security import abuse

# Keep the old limiter for compatibility; abuse.py independently enforces
# shared Redis budgets even when another SlowAPI instance checked the request.
limiter = Limiter(key_func=get_remote_address)
db_instance = db.db_instance
sqloader = db.sqloader
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
REFRESH_TOKEN_EXPIRE_DAYS = settings.REFRESH_TOKEN_EXPIRE_DAYS
TOTP_PENDING_EXPIRE_MINUTES = 5
pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
_DUMMY_HASH = pwd_context.hash(secrets.token_urlsafe(32))
router = APIRouter()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")


def verify_password(plain_password, hashed_password):
    try:
        return pwd_context.verify(plain_password, hashed_password)
    except (ValueError, TypeError):
        return False


def authenticate_user(username: str, password: str):
    if len(username) > 256 or len(password) > 4096:
        return False
    user_pw = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_password"), username)
    valid = verify_password(password, user_pw.get("password", "") if user_pw else _DUMMY_HASH)
    if not user_pw or not valid:
        return False
    return db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), username)


def create_access_token(data: dict, expires_delta: timedelta):
    return jwt_keys.sign_access(data, expires_delta)


def _access_claims(user_id: str, user: dict | None = None, sid: str | None = None) -> dict:
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
    # Even two refreshes in the same second must produce different tokens.
    to_encode.update({"exp": expire, "type": "refresh", "jti": secrets.token_urlsafe(24)})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def _issue_session_tokens(request: Request, user_id: str, user: dict | None) -> dict:
    sid = session_store.new_session_id()
    access_token = create_access_token(
        data=_access_claims(user_id, user, sid=sid),
        expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    )
    refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
    session_store.create_session(user_id, refresh_token, sid=sid, **session_store.describe_request(request))
    return {"access_token": access_token, "refresh_token": refresh_token, "sid": sid}


class TotpVerifyRequest(BaseModel):
    temp_token: str = Field(min_length=1, max_length=8192)
    code: str = Field(min_length=1, max_length=128)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1, max_length=8192)


@router.post("/")
@router.post("")
@limiter.limit(settings.RATE_LIMIT_LOGIN)
async def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends()):
    abuse.login_attempt(request, form_data.username)
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(400, "Invalid credentials")
    user_id = user["user_id"]
    if tfa.is_enabled(user_id):
        temp_token = create_access_token(
            data={"sub": user_id, "totp_pending": True, "jti": secrets.token_urlsafe(24)},
            expires_delta=timedelta(minutes=TOTP_PENDING_EXPIRE_MINUTES),
        )
        return {"totp_required": True, "temp_token": temp_token}
    tokens = _issue_session_tokens(request, user_id, user)
    abuse.login_success(form_data.username)
    return {"access_token": tokens["access_token"], "refresh_token": tokens["refresh_token"],
            "token_type": "bearer", "user": user}


@router.post("/totp/verify")
async def verify_totp_login(request: Request, body: TotpVerifyRequest):
    # Limit invalid/forged token requests too, before costly signature checking.
    abuse.limit("totp-envelope-ip", abuse.client_ip(request), 60, 300)
    try:
        payload = jwt_keys.verify_access(body.temp_token, verify_exp=True)
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "token_expired") from None
    except jwt.InvalidTokenError:
        raise HTTPException(401, "token_expired") from None
    user_id = payload.get("sub")
    if not user_id or payload.get("totp_pending") is not True:
        raise HTTPException(401, "token_expired")
    abuse.totp_attempt(request, user_id)
    if not tfa.is_enabled(user_id) or not tfa.verify(user_id, body.code):
        raise HTTPException(401, "invalid_code")
    abuse.consume_totp(user_id, body.code, body.temp_token)
    user = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), user_id)
    if not user:
        raise HTTPException(401, "Invalid authentication credentials")
    tokens = _issue_session_tokens(request, user_id, user)
    abuse.login_success(user_id)
    return {"access_token": tokens["access_token"], "refresh_token": tokens["refresh_token"],
            "token_type": "bearer", "user": user}


@router.post("/refresh")
async def refresh(request: Request, body: RefreshRequest):
    abuse.limit("refresh-ip", abuse.client_ip(request), 120, 300)
    credentials_exception = HTTPException(401, "Invalid authentication credentials",
                                         headers={"WWW-Authenticate": "Bearer"})
    try:
        payload = jwt.decode(body.refresh_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Token has expired") from None
    except jwt.InvalidTokenError:
        raise credentials_exception from None
    user_id = payload.get("sub")
    sid = payload.get("sid")
    if not user_id or payload.get("type") != "refresh":
        raise credentials_exception
    if redis_client.exists(f"blacklist:{body.refresh_token}") > 0:
        raise HTTPException(401, "Token has been logged out")
    if sid:
        stored_token = session_store.get_refresh_token(user_id, sid)
        if stored_token is None or stored_token != body.refresh_token:
            raise credentials_exception
        if not session_store.is_session_alive(user_id, sid):
            raise HTTPException(401, "session_revoked")
        new_refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
        session_store.rotate_refresh_token(user_id, sid, new_refresh_token)
    else:
        # One-time migration of a pre-session login; preserve existing users.
        stored_token = redis_client.get(f"refresh:{user_id}")
        if stored_token is None or stored_token != body.refresh_token:
            raise credentials_exception
        sid = session_store.new_session_id()
        new_refresh_token = create_refresh_token(data={"sub": user_id, "sid": sid})
        session_store.create_session(user_id, new_refresh_token, sid=sid, **session_store.describe_request(request))
        session_store.drop_legacy_refresh(user_id)
    refreshed_user = db_instance.fetch_one(sqloader.load_sql("file_forge", "get_user"), user_id)
    access_token = create_access_token(data=_access_claims(user_id, refreshed_user, sid=sid),
                                       expires_delta=timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    return {"access_token": access_token, "refresh_token": new_refresh_token, "token_type": "bearer"}
