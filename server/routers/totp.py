from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from routers.login.auth import verify_token, current_session
from routers.login import session_store
from config import tfa, db, adapt_query
from security import abuse

router = APIRouter()
db_instance = db.db_instance


class TotpCodeRequest(BaseModel):
    code: str = Field(min_length=1, max_length=128)


@router.post("/setup")
async def setup_totp(request: Request, user_id: str = Depends(verify_token)):
    abuse.limit("totp-setup", user_id, 5, 300)
    # Never let an existing bearer session replace an enabled second factor.
    if tfa.is_enabled(user_id):
        raise HTTPException(409, "totp_already_enabled")
    user = db_instance.fetch_one(adapt_query("SELECT user_id FROM users WHERE user_id = ?"), (user_id,))
    result = tfa.setup(user_id, user["user_id"] if user else user_id)
    return {"secret": result["secret"], "qr_image": result["qr_image"],
            "recovery_codes": result["recovery_codes"]}


@router.post("/activate")
async def activate_totp(request: Request, body: TotpCodeRequest, session: tuple = Depends(current_session)):
    user_id, sid = session
    abuse.totp_attempt(request, user_id)
    if tfa.is_enabled(user_id):
        raise HTTPException(409, "totp_already_enabled")
    if not tfa.activate(user_id, body.code):
        raise HTTPException(400, "invalid_code")
    abuse.consume_totp(user_id, body.code)
    session_store.revoke_other_sessions(user_id, sid)
    session_store.drop_legacy_refresh(user_id)
    return {"success": True}


def _verify_once(request: Request, user_id: str, code: str) -> None:
    abuse.totp_attempt(request, user_id)
    if not tfa.is_enabled(user_id) or not tfa.verify(user_id, code):
        raise HTTPException(400, "invalid_code")
    abuse.consume_totp(user_id, code)


@router.post("/disable")
async def disable_totp(request: Request, body: TotpCodeRequest, session: tuple = Depends(current_session)):
    user_id, sid = session
    _verify_once(request, user_id, body.code)
    tfa.disable(user_id)
    revoked = session_store.revoke_other_sessions(user_id, sid)
    session_store.drop_legacy_refresh(user_id)
    return {"success": True, "revoked_sessions": revoked}


@router.post("/regenerate")
async def regenerate_recovery_codes(request: Request, body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    _verify_once(request, user_id, body.code)
    return {"recovery_codes": tfa.regenerate_recovery_codes(user_id)}


@router.get("/status")
async def get_totp_status(user_id: str = Depends(verify_token)):
    return {"enabled": tfa.is_enabled(user_id)}
