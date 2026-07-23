from fastapi import APIRouter, Depends, HTTPException, Body
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel
from typing import Optional
import jwt
from datetime import datetime, timezone
from config import settings, redis_client

from . import jwt_keys, session_store

router = APIRouter()

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/token")

SECRET_KEY = settings.SECRET_KEY
ALGORITHM = "HS256"


class LogoutRequest(BaseModel):
    refresh_token: Optional[str] = None


@router.post("/")
async def logout(token: str = Depends(oauth2_scheme), body: LogoutRequest = Body(default=LogoutRequest())):
    """Log out the requesting session only.

    Logout used to delete the account-wide `refresh:{user_id}` key, which signed the user out
    of every device at once; it now terminates just the session carried by the presented token
    (D0003 §3.4). The per-token blacklist stays as a belt-and-braces measure for tokens that
    have no sid (pre-session logins) — session-scoped tokens are already refused by the gate in
    auth.verify_token the moment the session is gone (D0003 §7.2).
    """
    # access_tokentext RS256(jwt_keys). expired text tokentext blacklisttext text text text exptext text.
    access_payload = jwt_keys.verify_access(token, verify_exp=False)
    exp_time = access_payload["exp"]
    remaining_time = exp_time - datetime.now(timezone.utc).timestamp()

    user_id = access_payload.get("sub")
    sid = access_payload.get("sid")

    # access_token blacklist register
    redis_client.setex(f"blacklist:{token}", int(remaining_time), "1")

    # refresh_token blacklist register (translated text text)
    if body.refresh_token:
        try:
            refresh_payload = jwt.decode(body.refresh_token, SECRET_KEY, algorithms=[ALGORITHM], options={"verify_exp": False})
            refresh_exp = refresh_payload.get("exp")
            if refresh_exp:
                refresh_remaining = refresh_exp - datetime.now(timezone.utc).timestamp()
                if refresh_remaining > 0:
                    redis_client.setex(f"blacklist:{body.refresh_token}", int(refresh_remaining), "1")
            user_id = user_id or refresh_payload.get("sub")
            sid = sid or refresh_payload.get("sid")
        except jwt.InvalidTokenError:
            raise HTTPException(status_code=400, detail="Invalid refresh_token")

    if user_id and sid:
        session_store.revoke_session(user_id, sid)
    elif user_id:
        # Pre-session token: nothing but the old account-wide key to clear. Sessions created
        # since the deploy belong to other devices and must survive (D0003 §6).
        session_store.drop_legacy_refresh(user_id)

    return {"message": "Logged out successfully"}
