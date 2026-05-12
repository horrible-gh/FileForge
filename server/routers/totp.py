from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from routers.login.auth import verify_token
from config import tfa, db
import LogAssist.log as logger

db_instance = db.db_instance

router = APIRouter()


class TotpCodeRequest(BaseModel):
    code: str


@router.post("/setup")
async def setup_totp(user_id: str = Depends(verify_token)):
    """TOTP 설정 초기화 — secret, QR 이미지, 복구 코드 반환."""
    user = db_instance.fetch_one(
        "SELECT user_id FROM users WHERE user_id = %s",
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
    """TOTP 활성화 — 앱에서 스캔 후 첫 번째 코드 검증."""
    success = tfa.activate(user_id, body.code)
    if not success:
        raise HTTPException(status_code=400, detail="invalid_code")
    logger.debug("totp activated", user_id)
    return {"success": True}


@router.post("/disable")
async def disable_totp(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """TOTP 비활성화 — 현재 코드 검증 후 해제."""
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    tfa.disable(user_id)
    logger.debug("totp disabled", user_id)
    return {"success": True}


@router.post("/regenerate")
async def regenerate_recovery_codes(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """복구 코드 재생성 — 현재 코드 검증 후 새 복구 코드 발급."""
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    new_codes = tfa.regenerate_recovery_codes(user_id)
    logger.debug("recovery codes regenerated", user_id)
    return {"recovery_codes": new_codes}


@router.get("/status")
async def get_totp_status(user_id: str = Depends(verify_token)):
    """현재 사용자의 TOTP 활성화 여부 반환."""
    enabled = tfa.is_enabled(user_id)
    return {"enabled": enabled}