import jwt
import redis
from datetime import datetime, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from config import settings

import LogAssist.log as Logger

# JWT 설정값
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

# routers/main.py 하위 호환 import용 (실제 블랙리스트 확인은 Redis 기준)
token_blacklist = set()

redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)

def is_token_blacklisted(token: str) -> bool:
    try:
        return redis_client.exists(f"blacklist:{token}") > 0
    except redis.RedisError:
        return False  # Redis 장애 시 fail-open

def verify_token(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        if is_token_blacklisted(token):
            raise HTTPException(status_code=401, detail="Token has been logged out")

        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
        user_id: str = payload.get("sub")
        exp: int = payload.get("exp")
        totp_pending: bool = payload.get("totp_pending", False)
        token_type: str = payload.get("type", "access")

        if user_id is None or exp is None:
            raise credentials_exception

        # totp_pending 토큰으로 일반 API 접근 불가
        if totp_pending:
            raise HTTPException(status_code=401, detail="2FA verification required")

        # refresh_token으로 일반 API 접근 불가
        if token_type == "refresh":
            raise HTTPException(status_code=401, detail="Invalid token type")

        if datetime.now(timezone.utc) > datetime.fromtimestamp(exp, timezone.utc):
            raise HTTPException(status_code=401, detail="Token has expired")

        return user_id

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise credentials_exception

