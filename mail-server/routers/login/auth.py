import jwt
from datetime import datetime, timezone
from fastapi import Depends, HTTPException
from fastapi.security import OAuth2PasswordBearer
from config import settings, db

import LogAssist.log as Logger

# JWT 설정값
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

db_instance = db.db_instance
sqloader = db.sqloader

# ✅ Redis 또는 메모리 기반 블랙리스트 저장소 (예제)
token_blacklist = set()  # 실제 서비스에서는 Redis 등 사용 권장

def is_token_blacklisted(token: str) -> bool:
    """ 토큰이 블랙리스트에 있는지 확인 """
    return token in token_blacklist

def verify_token(token: str = Depends(oauth2_scheme)):
    #Logger.debug(f"🔍 받은 토큰: {token}")

    credentials_exception = HTTPException(
        status_code=401,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )

    try:
        # ✅ 블랙리스트된 토큰인지 확인
        if is_token_blacklisted(token):
            raise HTTPException(status_code=401, detail="Token has been logged out")

        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": True})
        user_id: str = payload.get("sub")
        exp: int = payload.get("exp")

        if user_id is None or exp is None:
            raise credentials_exception

        if datetime.now(timezone.utc) > datetime.fromtimestamp(exp, timezone.utc):
            raise HTTPException(status_code=401, detail="Token has expired")

        return user_id

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token has expired")
    except jwt.InvalidTokenError:
        raise credentials_exception


def get_current_user(user_id: str = Depends(verify_token)):
    """
    JWT 토큰에서 user_id를 추출하고 DB에서 사용자 정보 조회
    2FA API에서 사용자 정보가 필요할 때 사용
    """
    user = db_instance.fetch_one(sqloader.load_sql("mail_anchor", "get_user"), user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

