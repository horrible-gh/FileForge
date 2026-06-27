import jwt
import redis
from datetime import datetime, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from config import settings, redis_client, db

from . import jwt_keys

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

def verify_token(token: str = Depends(oauth2_scheme)):
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

        return user_id

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

