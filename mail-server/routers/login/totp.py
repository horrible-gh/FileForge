"""
2FA TOTP 엔드포인트
TOTP 기반 2단계 인증 설정, 활성화, 비활성화 API
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from .auth import verify_token
from config import tfa, db
import LogAssist.log as logger

db_instance = db.get_db_instance()

router = APIRouter(prefix="/2fa", tags=["2FA"])


# === Request 모델 ===

class TotpCodeRequest(BaseModel):
    code: str  # 6자리 TOTP 코드 또는 리커버리 코드


# === 엔드포인트 ===

@router.get("/status")
async def get_totp_status(user_id: str = Depends(verify_token)):
    """현재 사용자의 TOTP 활성화 여부 반환."""
    enabled = tfa.is_enabled(user_id)
    return {"enabled": enabled}


@router.post("/setup")
async def setup_totp(user_id: str = Depends(verify_token)):
    """TOTP 설정 초기화 — secret, QR 이미지, 복구 코드 반환."""
    user = db_instance.fetch_one(
        "SELECT user_id FROM users WHERE user_id = %s",
        (user_id,)
    )
    username = user["user_id"] if user else user_id

    try:
        result = tfa.setup(user_id, username)
    except ValueError as e:
        # TOTP가 이미 설정되어 있는 경우, 기존 설정을 제거하고 재설정
        if "already configured" in str(e):
            logger.warn(f"TOTP already configured for {user_id}, resetting...")
            tfa.disable(user_id)
            result = tfa.setup(user_id, username)
        else:
            raise

    logger.debug(f"totp setup for user: {user_id}")
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
    logger.debug(f"totp activated for user: {user_id}")
    return {"success": True}


@router.post("/disable")
async def disable_totp(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """TOTP 비활성화 — 현재 코드 검증 후 해제."""
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    tfa.disable(user_id)
    logger.debug(f"totp disabled for user: {user_id}")
    return {"success": True}


@router.post("/regenerate-recovery")
async def regenerate_recovery_codes(body: TotpCodeRequest, user_id: str = Depends(verify_token)):
    """복구 코드 재생성 — 현재 코드 검증 후 새 복구 코드 발급."""
    if not tfa.verify(user_id, body.code):
        raise HTTPException(status_code=400, detail="invalid_code")
    new_codes = tfa.regenerate_recovery_codes(user_id)
    logger.debug(f"recovery codes regenerated for user: {user_id}")
    return {"recovery_codes": new_codes}
