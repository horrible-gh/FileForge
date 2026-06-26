from fastapi import APIRouter, Depends, HTTPException, Body
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel
from typing import Optional
import jwt
from datetime import datetime, timezone
from config import settings, redis_client

from . import jwt_keys

router = APIRouter()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"


class LogoutRequest(BaseModel):
    refresh_token: Optional[str] = None


@router.post("/")
async def logout(token: str = Depends(oauth2_scheme), body: LogoutRequest = Body(default=LogoutRequest())):
    """ current text text JWT tokentext blacklisttext register (logout) """
    # access_tokentext RS256(jwt_keys). expired text tokentext blacklisttext text text text exptext text.
    exp_time = jwt_keys.verify_access(token, verify_exp=False)["exp"]
    remaining_time = exp_time - datetime.now(timezone.utc).timestamp()

    # access_token blacklist register
    redis_client.setex(f"blacklist:{token}", int(remaining_time), "1")

    # refresh_token blacklist register + Redis text text delete (translated text text)
    if body.refresh_token:
        try:
            refresh_payload = jwt.decode(body.refresh_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": False})
            refresh_exp = refresh_payload.get("exp")
            if refresh_exp:
                refresh_remaining = refresh_exp - datetime.now(timezone.utc).timestamp()
                if refresh_remaining > 0:
                    redis_client.setex(f"blacklist:{body.refresh_token}", int(refresh_remaining), "1")
            user_id = refresh_payload.get("sub")
            if user_id:
                redis_client.delete(f"refresh:{user_id}")
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=400, detail="Invalid refresh_token")

    return {"message": "Logged out successfully"}
