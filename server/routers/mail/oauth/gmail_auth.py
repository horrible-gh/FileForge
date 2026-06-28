"""
Gmail OAuth2 인증 라우터
- OAuth2 플로우 처리
- 토큰 발급/갱신
"""
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import RedirectResponse, HTMLResponse
from config import settings, db, redis_client
from routers.login.auth import verify_token, current_user_uuid
from util.crypto import encrypt_password, decrypt_password
from services.gmail_service import GmailOAuthService
from urllib.parse import urlencode, urlsplit
from html import escape
from typing import Optional
import json
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


def _explicit_frontend_base() -> str:
    """OAuth 콜백 완료 후 사용자를 되돌릴, **명시적으로 설정된 프론트엔드** origin.

    우선순위: FRONTEND_BASE_URL > ALLOWED_ORIGIN의 첫 구체 origin.

    과거(0005.0003-NR)에는 여기에 GOOGLE_REDIRECT_URI의 origin까지 최후 폴백으로 두었으나,
    그 origin은 *프론트엔드*가 아니라 **백엔드(API 서버) 자신**이다. 백엔드에는
    `/dashboard/mail/oauth/gmail/callback` 라우트가 없으므로, 거기로 리다이렉트하면
    브라우저에 FastAPI 기본 404 `{"detail":"Not Found"}` 가 떴다
    (0011.0003-NR — "2계정 이상 연동 시 Not Found", 실제로는 OAuth 연동 전건에서 발생).
    따라서 백엔드 origin 폴백을 제거하고, 명시 설정이 없으면 "" 를 반환해
    호출부가 self-contained 성공 페이지로 폴백하도록 한다.
    """
    base = settings.FRONTEND_BASE_URL.strip().rstrip("/")
    if base:
        return base
    return _first_allowed_origin()


def _oauth_result_url(**params) -> Optional[str]:
    """성공 후 브라우저를 되돌릴 *실재하는* 프론트엔드 URL, 또는 None.

    OAUTH_SUCCESS_REDIRECT_URL(완성형) > 명시 프론트엔드 base + 표준 콜백 경로 순.
    어느 것도 설정되지 않았으면(웹 프론트가 없는 데스크톱/로컬 구성) None 을 돌려주고,
    호출부는 RedirectResponse 대신 self-contained 성공 HTML 을 반환한다.
    """
    callback_url = settings.OAUTH_SUCCESS_REDIRECT_URL.strip()
    if not callback_url:
        frontend_base = _explicit_frontend_base()
        if not frontend_base:
            return None
        callback_url = f"{frontend_base}/dashboard/mail/oauth/gmail/callback"

    query = urlencode({key: value for key, value in params.items() if value is not None})
    return f"{callback_url}?{query}" if query else callback_url


def _oauth_result_page(*, success: bool, heading: str, message: str,
                       status_code: int = 200,
                       deeplink: Optional[str] = None,
                       auto_close: bool = False) -> HTMLResponse:
    """브라우저로 직접 반환하는 self-contained OAuth 결과 페이지.

    웹 프론트엔드가 없는(데스크톱/로컬) 구성에서 redirect 목적지가 없을 때, 브라우저에
    raw JSON(`{"detail":...}`) 대신 사람이 읽을 수 있는 안내를 보여준다.

    R0001/NR0003/T0004 §Option C — 성공 시 "닫고 앱으로 돌아가세요" 안내를 수동에 맡기지
    않고 다음을 계층적으로 시도한다(모바일 불편 해소가 목적):
      1) deeplink 가 있으면 짧은 지연 후 커스텀 스킴으로 자동 리다이렉트 → OS 가 앱을
         foreground 로 올리고, 앱은 딥링크 수신 시 계정 목록을 재로딩해 연결을 감지한다.
      2) 카운트다운 후 window.close() 시도(데스크톱/스크립트로 열린 창 폴백).
      3) 위가 모두 막히는 환경(모바일 브라우저 등)을 위해 "FileForge 앱으로 돌아가기"
         수동 버튼/링크를 항상 노출한다.
    실패 페이지는 사용자가 메시지를 읽어야 하므로 자동 닫기/리다이렉트를 하지 않는다.
    """
    accent = "#1a73e8" if success else "#d93025"
    icon = "✓" if success else "✕"

    action_html = ""
    script_html = ""
    if success and deeplink:
        safe_link = escape(deeplink, quote=True)
        action_html = (
            f'<a class="btn" href="{safe_link}">FileForge 앱으로 돌아가기</a>'
        )
    if success:
        # JS는 별도 변수에 안전한 JSON 문자열로 주입(스킴/메시지 인젝션 방지).
        deeplink_js = json.dumps(deeplink) if deeplink else "null"
        script_html = f"""
<script>
(function() {{
  var deeplink = {deeplink_js};
  // 1) 딥링크 자동 복귀 시도(모바일 핵심 경로).
  if (deeplink) {{
    setTimeout(function() {{ try {{ window.location.href = deeplink; }} catch (e) {{}} }}, 600);
  }}
  // 2) 데스크톱/스크립트로 열린 창 폴백 — 카운트다운 후 자동 닫기.
  var remain = 3;
  var el = document.getElementById('countdown');
  var timer = setInterval(function() {{
    remain -= 1;
    if (el) {{ el.textContent = String(remain); }}
    if (remain <= 0) {{
      clearInterval(timer);
      try {{ window.close(); }} catch (e) {{}}
    }}
  }}, 1000);
}})();
</script>"""

    countdown_note = (
        '<p class="note">잠시 후(<span id="countdown">3</span>초) 이 창은 자동으로 닫힙니다. '
        '자동으로 닫히거나 앱으로 돌아가지 않으면 아래 버튼을 누르거나 창을 닫아 주세요.</p>'
        if success else ""
    )

    html = f"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{escape(heading)}</title>
<style>
  body {{ font-family: -apple-system, "Segoe UI", Roboto, sans-serif; background:#f6f8fc;
         margin:0; display:flex; min-height:100vh; align-items:center; justify-content:center; }}
  .card {{ background:#fff; border-radius:14px; padding:40px 36px; max-width:380px; text-align:center;
           box-shadow:0 2px 16px rgba(0,0,0,.08); }}
  .badge {{ width:56px; height:56px; border-radius:50%; background:{accent}; color:#fff;
            font-size:30px; line-height:56px; margin:0 auto 18px; }}
  h1 {{ font-size:20px; margin:0 0 10px; color:#202124; }}
  p {{ font-size:14px; color:#5f6368; line-height:1.6; margin:0; }}
  .note {{ font-size:13px; color:#80868b; margin-top:14px; }}
  .btn {{ display:inline-block; margin-top:18px; padding:10px 22px; background:{accent};
          color:#fff; text-decoration:none; border-radius:8px; font-size:14px; }}
</style></head>
<body><div class="card">
  <div class="badge">{icon}</div>
  <h1>{escape(heading)}</h1>
  <p>{escape(message)}</p>
  {countdown_note}
  {action_html}
</div>{script_html}</body></html>"""
    return HTMLResponse(content=html, status_code=status_code)


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
    # 이 엔드포인트는 **브라우저가 직접 도달**하는 화면이다(외부 브라우저 OAuth 복귀).
    # 따라서 실패도 raw JSON(`{"detail":...}`)이 아니라 사람이 읽는 HTML 로 돌려준다.
    if error:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message=f"Google 인증이 취소되었거나 실패했습니다. ({error}) 앱으로 돌아가 다시 시도해 주세요.")

    if not code or not state:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message="인증 정보(code/state)가 누락되었습니다. 앱으로 돌아가 다시 시도해 주세요.")

    # Redis에서 state 검증 및 삭제
    redis_key = f"gmail_oauth_state:{state}"
    user_uuid = redis_client.get(redis_key)

    if not user_uuid:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message="인증 요청이 만료되었거나 유효하지 않습니다. 앱으로 돌아가 다시 시도해 주세요.")

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

        # 명시적으로 설정된 웹 프론트엔드가 있으면 그곳으로 리다이렉트(기존 동작 유지).
        # 없으면(데스크톱/로컬 구성) 존재하지 않는 /dashboard 경로로 보내 404 를 띄우는
        # 대신 self-contained 성공 페이지를 직접 반환한다(0011.0003-NR).
        result_url = _oauth_result_url(gmail_connected="true", email=user_info["email"])
        if result_url:
            return RedirectResponse(url=result_url)
        deeplink = settings.OAUTH_SUCCESS_DEEPLINK.strip() or None
        return _oauth_result_page(
            success=True, heading="연결 완료",
            message=f"{user_info['email']} 계정이 연결되었습니다.",
            deeplink=deeplink, auto_close=True)

    except HTTPException:
        # redirect-URL 빌더 등 내부에서 의도적으로 올린 4xx/5xx는 의미·메시지를
        # 보존하여 그대로 전파한다(아래 광범위 except가 "OAuth 처리 실패: 500: ..."
        # 처럼 이중 prefix로 재포장하던 B0001 증상 제거).
        raise
    except Exception as e:
        # 토큰 교환/저장 단계 실패도 브라우저 화면이므로 HTML 로 안내(raw JSON 회피).
        import LogAssist.log as _logger
        _logger.error(f"[gmail callback] {e}")
        return _oauth_result_page(
            success=False, status_code=500, heading="연결 실패",
            message="계정 연결 중 오류가 발생했습니다. 앱으로 돌아가 다시 시도해 주세요.")


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
