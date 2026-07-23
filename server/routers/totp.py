from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from routers.login.auth import verify_token, current_session
from routers.login import session_store
from config import tfa, db, adapt_query
import LogAssist.log as logger

db_instance = db.db_instance

router = APIRouter()


class TotpCodeRequest(BaseModel):
    code: str


@router.post("/setup")
async def setup_totp(user_id: str = Depends(verify_token)):
    """TOTP text initialize — secret, QR translated text, text text return."""
    user = db_instance.fetch_one(
        adapt_query("SELECT user_id FROM users WHERE user_id = ?"),
        (user_id,)
    )
    username = user["user_id"] if user else user_id

    result = tfa.setup(user_id, username)
    logger.debug("totp setup", user_id)
    return {
        "secret": result["secret"],
        "qr_image": result["qr_image"],
        "recovery_codes": result["recovery_codes"],
    }


@router.post("/activate")
async def activate_totp(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """TOTP translated text — translated text text text text text text verify."""
    success = tfa.activate(user_id, body.code)
    if not success:
        raise HTTPException(status_code=400, detail="invalid_code")
    logger.debug("totp activated", user_id)
    return {"success": True}


@router.post("/disable")
async def disable_totp(body: TotpCodeRequest, session: tuple = Depends(current_session)):
    """TOTP translated text — current text verify text text.

    Dropping the second factor weakens every existing login, so every *other* session is ended
    here (D0003 §3.5): if the account was taken over, turning 2FA off — like changing the
    password — must not leave the intruder signed in. The caller keeps their own session.
    D0003's password-change half of that rule has no hook yet: FileForge exposes no
    change-password endpoint at all (NR0005 F7/G1), so it is deferred to whenever that lands.
    """
    user_id, sid = session
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    tfa.disable(user_id)
    revoked = session_store.revoke_other_sessions(user_id, sid)
    logger.debug(f"totp disabled - user_id: {user_id}, other sessions revoked: {revoked}")
    return {"success": True, "revoked_sessions": revoked}


@router.post("/regenerate")
async def regenerate_recovery_codes(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """text text textcreate — current text verify text text text text issue."""
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    new_codes = tfa.regenerate_recovery_codes(user_id)
    logger.debug("recovery codes regenerated", user_id)
    return {"recovery_codes": new_codes}


@router.get("/status")
async def get_totp_status(user_id: str = Depends(verify_token)):
    """current translated text TOTP translated text text return."""
    enabled = tfa.is_enabled(user_id)
    return {"enabled": enabled}