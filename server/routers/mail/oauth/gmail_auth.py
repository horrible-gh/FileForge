"""
Gmail OAuth2 인증 라우터
- OAuth2 플로우 처리
- 토큰 발급/갱신
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse
from config import settings, db, redis_client
from routers.login.auth import verify_token, current_user_uuid
from util.crypto import encrypt_password, decrypt_password
from services.gmail_service import GmailOAuthService
from urllib.parse import urlencode, urlsplit
import secrets

SECRET_KEY = settings.SECRET_KEY
db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

STATE_EXPIRE_SECONDS = 600  # 10분

gmail_oauth = GmailOAuthService()


def _first_allowed_origin() -> str:
    for origin in settings.ALLOWED_ORIGIN.split(","):
        origin = origin.strip()
        if origin and origin != "*":
            return origin.rstrip("/")
    return ""


def _origin_of(url: str) -> str:
    """절대 URL에서 scheme://host[:port] origin만 추출. 파싱 불가 시 ""."""
    try:
        parts = urlsplit((url or "").strip())
        if parts.scheme and parts.netloc:
            return f"{parts.scheme}://{parts.netloc}"
    except ValueError:
        pass
    return ""


def _frontend_base() -> str:
    """OAuth 콜백 완료 후 사용자를 되돌릴 프론트엔드 베이스 origin을 해석한다.

    우선순위: FRONTEND_BASE_URL > ALLOWED_ORIGIN의 첫 구체 origin >
    GOOGLE_REDIRECT_URI의 origin(최후 폴백).

    ALLOWED_ORIGIN=* 처럼 _first_allowed_origin()이 폴백 불가한 환경(B0001)에서도,
    GOOGLE_REDIRECT_URI는 콜백 동작의 전제라 항상 존재하므로 이를 최후 폴백으로 써서
    "계정은 생성됐는데 redirect 단계에서 500" 상태를 제거한다. 정확한 목적지는
    운영이 OAUTH_SUCCESS_REDIRECT_URL/FRONTEND_BASE_URL로 명시(.env.sample 참조).
    """
    base = settings.FRONTEND_BASE_URL.strip().rstrip("/")
    if base:
        return base
    base = _first_allowed_origin()
    if base:
        return base
    return _origin_of(settings.GOOGLE_REDIRECT_URI)


def _oauth_result_url(**params) -> str:
    callback_url = settings.OAUTH_SUCCESS_REDIRECT_URL.strip()
    if not callback_url:
        frontend_base = _frontend_base()
        if not frontend_base:
            raise HTTPException(
                status_code=500,
                detail="FRONTEND_BASE_URL 또는 OAUTH_SUCCESS_REDIRECT_URL 설정이 필요합니다.",
            )
        callback_url = f"{frontend_base}/dashboard/mail/oauth/gmail/callback"

    query = urlencode({key: value for key, value in params.items() if value is not None})
    return f"{callback_url}?{query}" if query else callback_url


@router.get("/auth_url")
async def get_gmail_auth_url(user_uuid: str = Depends(current_user_uuid)):
    """
    Gmail OAuth2 인증 URL 생성
    프론트엔드에서 이 URL로 사용자를 리다이렉트

    user_uuid는 인증 토큰에서 해석한 users.user_uuid(PK)이다. 이 값이 그대로
    Redis state에 저장되고 콜백에서 mail_accounts.user_uuid(FK)로 INSERT되므로,
    토큰의 문자열 user_id를 그대로 쓰면 FK 위반(1452)이 난다
    (fileforge.mailanchorpython.0004.0003-NR). current_user_uuid 의존성으로 해석.
    """
    state = f"{user_uuid}:{secrets.token_urlsafe(16)}"

    # Redis에 state 저장 (10분 TTL)
    redis_client.setex(f"gmail_oauth_state:{state}", STATE_EXPIRE_SECONDS, user_uuid)

    auth_url = gmail_oauth.generate_auth_url(state)

    return {"auth_url": auth_url, "state": state}


@router.get("/callback")
async def gmail_oauth_callback(
    code: str = Query(None),
    state: str = Query(None),
    error: str = Query(None),
):
    """
    Google OAuth2 콜백 처리
    Google 인증 후 리다이렉트되는 엔드포인트
    """
    if error:
        raise HTTPException(status_code=400, detail=f"OAuth 인증 실패: {error}")

    if not code or not state:
        raise HTTPException(status_code=400, detail="code 또는 state가 없습니다.")

    # Redis에서 state 검증 및 삭제
    redis_key = f"gmail_oauth_state:{state}"
    user_uuid = redis_client.get(redis_key)

    if not user_uuid:
        raise HTTPException(status_code=400, detail="잘못되거나 만료된 state 값입니다.")

    redis_client.delete(redis_key)

    try:
        # 토큰 교환
        token_data = await gmail_oauth.exchange_code_for_tokens(code)

        # 사용자 정보 조회
        user_info = await gmail_oauth.get_user_info(token_data["access_token"])

        # 토큰 암호화 후 DB 저장
        encrypted_access = encrypt_password(SECRET_KEY, user_uuid, token_data["access_token"])
        encrypted_refresh = encrypt_password(SECRET_KEY, user_uuid, token_data.get("refresh_token", ""))

        # 기존 계정 확인
        existing = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "gmail.get_account_by_email"),
            {"user_uuid": user_uuid, "email": user_info["email"]}
        )

        if existing:
            # 토큰 업데이트
            db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.update_tokens"),
                {
                    "account_uuid": existing["account_uuid"],
                    "access_token_encrypted": encrypted_access,
                    "refresh_token_encrypted": encrypted_refresh,
                    "token_expires_in": token_data.get("expires_in", 3600),
                }
            )
            # account_type도 gmail로 변경
            db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.update_account_by_email"),
                {"account_uuid": existing["account_uuid"]}
            )
            account_uuid = existing["account_uuid"]
        else:
            # 새 계정 생성
            result = db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.insert_account"),
                {
                    "user_uuid": user_uuid,
                    "account_name": user_info.get("name", user_info["email"]),
                    "email": user_info["email"],
                    "access_token_encrypted": encrypted_access,
                    "refresh_token_encrypted": encrypted_refresh,
                    "token_expires_in": token_data.get("expires_in", 3600),
                    "picture": user_info.get("picture"),
                }
            )

        return RedirectResponse(
            url=_oauth_result_url(gmail_connected="true", email=user_info["email"])
        )

    except HTTPException:
        # redirect-URL 빌더 등 내부에서 의도적으로 올린 4xx/5xx는 의미·메시지를
        # 보존하여 그대로 전파한다(아래 광범위 except가 "OAuth 처리 실패: 500: ..."
        # 처럼 이중 prefix로 재포장하던 B0001 증상 제거).
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"OAuth 처리 실패: {str(e)}")


@router.post("/refresh_token", dependencies=[Depends(verify_token)])
async def refresh_gmail_token(account_uuid: str = Query(...), user_uuid: str = Query(...)):
    """
    Gmail 토큰 갱신
    만료된 access_token을 refresh_token으로 갱신
    """
    # 계정 조회
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.get_account"),
        {"account_uuid": account_uuid, "user_uuid": user_uuid}
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없습니다.")

    if not account.get("refresh_token_encrypted"):
        raise HTTPException(status_code=400, detail="재인증이 필요합니다. (refresh_token 없음)")

    try:
        # refresh_token 복호화
        refresh_token = decrypt_password(
            SECRET_KEY, user_uuid, account["refresh_token_encrypted"]
        )

        # 토큰 갱신
        token_data = await gmail_oauth.refresh_access_token(refresh_token)

        # 새 토큰 암호화 후 저장
        encrypted_access = encrypt_password(SECRET_KEY, user_uuid, token_data["access_token"])

        db_instance.execute_query(
            sqloader.load_sql("mail_anchor.json", "gmail.update_access_token"),
            {
                "account_uuid": account_uuid,
                "access_token_encrypted": encrypted_access,
                "token_expires_in": token_data.get("expires_in", 3600),
            }
        )

        return {"success": True, "message": "토큰 갱신 완료"}

    except Exception as e:
        raise HTTPException(status_code=401, detail=f"토큰 갱신 실패: {str(e)}")


@router.delete("/disconnect/{account_uuid}", dependencies=[Depends(verify_token)])
async def disconnect_gmail(account_uuid: str, user_uuid: str = Query(...)):
    """
    Gmail 계정 연결 해제
    토큰 폐기 및 계정 비활성화
    """
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.get_account"),
        {"account_uuid": account_uuid, "user_uuid": user_uuid}
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없습니다.")

    try:
        # 토큰 폐기 시도
        if account.get("access_token_encrypted"):
            access_token = decrypt_password(
                SECRET_KEY, user_uuid, account["access_token_encrypted"]
            )
            await gmail_oauth.revoke_token(access_token)

        # 계정 비활성화
        db_instance.execute_query(
            sqloader.load_sql("mail_anchor.json", "gmail.deactivate_account"),
            {"account_uuid": account_uuid}
        )

        return {"success": True, "message": "Gmail 연결 해제 완료"}

    except Exception as e:
        # 폐기 실패해도 계정은 비활성화
        db_instance.execute_query(
            sqloader.load_sql("mail_anchor.json", "gmail.deactivate_account"),
            {"account_uuid": account_uuid}
        )
        return {"success": True, "message": "Gmail 연결 해제 완료 (토큰 폐기 실패)"}


@router.get("/accounts", dependencies=[Depends(verify_token)])
async def get_gmail_accounts(user_uuid: str = Query(...)):
    """
    Gmail 계정 목록 조회
    """
    accounts = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "gmail.get_accounts"),
        {"user_uuid": user_uuid}
    )
    return accounts or []
