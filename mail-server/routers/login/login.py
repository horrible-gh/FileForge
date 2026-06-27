from fastapi import APIRouter, Depends, HTTPException, Header
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from passlib.context import CryptContext
import jwt
from datetime import datetime, timedelta, timezone
from typing import Optional
from config import settings, db, tfa

import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

# JWT Secret Key (실제 서비스에서는 환경변수 사용 권장)
SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES

# 비밀번호 해싱 설정
pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")

router = APIRouter()

# OAuth2 방식으로 토큰 받기
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def authenticate_user(username: str, password: str):
    user_pw = db_instance.fetch_one(sqloader.load_sql("mail_anchor", "get_password"), username)
    if not user_pw or not verify_password(password, user_pw.get("password", "")):
        return False
    result =  db_instance.fetch_one(sqloader.load_sql("mail_anchor", "get_user"), username)
    logger.debug(result)
    return result


def create_access_token(data: dict, expires_delta: timedelta):
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + expires_delta
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

    return encoded_jwt


@router.post("/")
@router.post("")
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    x_totp_code: Optional[str] = Header(None, alias="X-TOTP-Code")
):
    """
    로그인 엔드포인트 (2FA 지원)

    1단계: ID/PW 인증
    2단계: 2FA가 활성화된 경우, TOTP 코드 검증 (X-TOTP-Code 헤더로 전달)
    """
    # 1단계: ID/PW 인증
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=400, detail="Invalid credentials")

    user_id = str(user["user_id"])

    # 2단계: 2FA 체크
    if tfa.is_enabled(user_id):
        if not x_totp_code:
            # 2FA가 활성화되어 있지만 코드가 제공되지 않음
            logger.debug(f"2FA required for user: {user_id}")
            return {
                "requires_2fa": True,
                "message": "2FA code required"
            }

        # TOTP 코드 검증 (리커버리 코드도 자동 체크됨)
        if not tfa.verify(user_id, x_totp_code):
            logger.warning(f"Invalid 2FA code for user: {user_id}")
            raise HTTPException(status_code=401, detail="Invalid 2FA code")

        logger.info(f"2FA verification successful for user: {user_id}")

    # 인증 완료 → JWT 발급
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user["user_id"]}, expires_delta=access_token_expires
    )
    logger.debug({"access_token": access_token, "token_type": "bearer", "user": user})
    return {"access_token": access_token, "token_type": "bearer", "user": user}
