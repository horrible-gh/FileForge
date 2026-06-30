"""
Gmail OAuth2 authentication router
- OAuth2 flow handling
- Token issuance/refresh
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

STATE_EXPIRE_SECONDS = 600  # 10 minutes

gmail_oauth = GmailOAuthService()


def _first_allowed_origin() -> str:
    for origin in settings.ALLOWED_ORIGIN.split(","):
        origin = origin.strip()
        if origin and origin != "*":
            return origin.rstrip("/")
    return ""


def _origin_of(url: str) -> str:
    """Extract only the scheme://host[:port] origin from an absolute URL. Returns "" if unparseable."""
    try:
        parts = urlsplit((url or "").strip())
        if parts.scheme and parts.netloc:
            return f"{parts.scheme}://{parts.netloc}"
    except ValueError:
        pass
    return ""


def _explicit_frontend_base() -> str:
    """The **explicitly configured frontend** origin to return the user to after the
    OAuth callback completes.

    Priority: FRONTEND_BASE_URL > the first concrete origin in ALLOWED_ORIGIN.

    Previously (0005.0003-NR) this also fell back to the origin of GOOGLE_REDIRECT_URI
    as a last resort, but that origin is not the *frontend* — it is the **backend
    (API server) itself**. The backend has no `/dashboard/mail/oauth/gmail/callback`
    route, so redirecting there made the browser show FastAPI's default 404
    `{"detail":"Not Found"}`
    (0011.0003-NR — "Not Found when linking 2+ accounts", which actually happened on
    every OAuth link). So the backend-origin fallback is removed, and when nothing is
    explicitly configured this returns "" so the caller falls back to a self-contained
    success page.
    """
    base = settings.FRONTEND_BASE_URL.strip().rstrip("/")
    if base:
        return base
    return _first_allowed_origin()


def _oauth_result_url(**params) -> Optional[str]:
    """A *real* frontend URL to return the browser to after success, or None.

    Order: OAUTH_SUCCESS_REDIRECT_URL (complete URL) > explicit frontend base +
    standard callback path. If neither is configured (a desktop/local setup with no
    web frontend) this returns None, and the caller returns a self-contained success
    HTML page instead of a RedirectResponse.
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
    """A self-contained OAuth result page returned directly to the browser.

    When there is no redirect destination in a setup without a web frontend
    (desktop/local), this shows the browser a human-readable notice instead of raw
    JSON (`{"detail":...}`).

    R0001/NR0003/T0004 §Option C — on success, rather than leaving the "close this and
    return to the app" guidance to the user, it tries the following in layers (to ease
    the mobile inconvenience):
      1) if a deeplink exists, auto-redirect to the custom scheme after a short delay
         → the OS brings the app to the foreground, and on receiving the deeplink the
         app reloads the account list to detect the connection.
      2) attempt window.close() after a countdown (fallback for desktop/script-opened windows).
      3) for environments where all of the above are blocked (mobile browsers, etc.),
         always expose a manual "Return to the FileForge app" button/link.
    The failure page does not auto-close/redirect because the user needs to read the message.
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
        # Inject into JS as a safe JSON string in a separate variable (prevents scheme/message injection).
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
    Generate the Gmail OAuth2 authentication URL.
    The frontend redirects the user to this URL.

    user_uuid is the users.user_uuid (PK) resolved from the auth token. This value is
    stored as-is in the Redis state and INSERTed as mail_accounts.user_uuid (FK) in the
    callback, so using the token's string user_id directly causes an FK violation (1452)
    (fileforge.mailanchorpython.0004.0003-NR). Resolved via the current_user_uuid dependency.
    """
    state = f"{user_uuid}:{secrets.token_urlsafe(16)}"

    # Store state in Redis (10-minute TTL)
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
    Handle the Google OAuth2 callback.
    The endpoint Google redirects to after authentication.
    """
    # This endpoint is a screen the **browser reaches directly** (external-browser OAuth return).
    # So failures are returned as human-readable HTML, not raw JSON (`{"detail":...}`).
    if error:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message=f"Google 인증이 취소되었거나 실패했습니다. ({error}) 앱으로 돌아가 다시 시도해 주세요.")

    if not code or not state:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message="인증 정보(code/state)가 누락되었습니다. 앱으로 돌아가 다시 시도해 주세요.")

    # Validate and delete state from Redis
    redis_key = f"gmail_oauth_state:{state}"
    user_uuid = redis_client.get(redis_key)

    if not user_uuid:
        return _oauth_result_page(
            success=False, status_code=400, heading="연결 실패",
            message="인증 요청이 만료되었거나 유효하지 않습니다. 앱으로 돌아가 다시 시도해 주세요.")

    redis_client.delete(redis_key)

    try:
        # Exchange the code for tokens
        token_data = await gmail_oauth.exchange_code_for_tokens(code)

        # Fetch user info
        user_info = await gmail_oauth.get_user_info(token_data["access_token"])

        # Encrypt tokens and store in DB. A missing refresh token must be stored as
        # NULL, NOT encrypt("") — AES pads b"" to a non-empty 16-byte block, so an
        # encrypted empty string is *truthy* and would defeat the "no refresh token →
        # reauth" guard, turning a recoverable reauth into a silent token-refresh
        # failure later (B0001 / NR0003 H3).
        encrypted_access = encrypt_password(SECRET_KEY, user_uuid, token_data["access_token"])
        raw_refresh = (token_data.get("refresh_token") or "").strip()
        encrypted_refresh = (
            encrypt_password(SECRET_KEY, user_uuid, raw_refresh) if raw_refresh else None
        )

        # Check for an existing account
        existing = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "gmail.get_account_by_email"),
            {"user_uuid": user_uuid, "email": user_info["email"]}
        )

        if existing:
            # Update tokens
            db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.update_tokens"),
                {
                    "account_uuid": existing["account_uuid"],
                    "access_token_encrypted": encrypted_access,
                    "refresh_token_encrypted": encrypted_refresh,
                    "token_expires_in": token_data.get("expires_in", 3600),
                }
            )
            # Also change account_type to gmail
            db_instance.execute_query(
                sqloader.load_sql("mail_anchor.json", "gmail.update_account_by_email"),
                {"account_uuid": existing["account_uuid"]}
            )
            account_uuid = existing["account_uuid"]
        else:
            # Create a new account
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

        # If an explicitly configured web frontend exists, redirect there (preserves existing behavior).
        # Otherwise (a desktop/local setup), instead of sending to a non-existent /dashboard
        # path that would show a 404, return a self-contained success page directly (0011.0003-NR).
        result_url = _oauth_result_url(gmail_connected="true", email=user_info["email"])
        if result_url:
            return RedirectResponse(url=result_url)
        deeplink = settings.OAUTH_SUCCESS_DEEPLINK.strip() or None
        return _oauth_result_page(
            success=True, heading="연결 완료",
            message=f"{user_info['email']} 계정이 연결되었습니다.",
            deeplink=deeplink, auto_close=True)

    except HTTPException:
        # 4xx/5xx intentionally raised inside (e.g. the redirect-URL builder) are
        # propagated as-is, preserving their meaning/message (removes the B0001 symptom
        # where the broad except below re-wrapped them with a double prefix like
        # "OAuth processing failed: 500: ...").
        raise
    except Exception as e:
        # Token exchange/store failures are also a browser screen, so guide via HTML (avoid raw JSON).
        import LogAssist.log as _logger
        _logger.error(f"[gmail callback] {e}")
        return _oauth_result_page(
            success=False, status_code=500, heading="연결 실패",
            message="계정 연결 중 오류가 발생했습니다. 앱으로 돌아가 다시 시도해 주세요.")


@router.post("/refresh_token", dependencies=[Depends(verify_token)])
async def refresh_gmail_token(account_uuid: str = Query(...), user_uuid: str = Query(...)):
    """
    Refresh the Gmail token.
    Refresh an expired access_token using the refresh_token.
    """
    # Look up the account
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.get_account"),
        {"account_uuid": account_uuid, "user_uuid": user_uuid}
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없습니다.")

    if not account.get("refresh_token_encrypted"):
        raise HTTPException(status_code=400, detail="재인증이 필요합니다. (refresh_token 없음)")

    try:
        # Decrypt the refresh_token
        refresh_token = decrypt_password(
            SECRET_KEY, user_uuid, account["refresh_token_encrypted"]
        )

        # Refresh the token
        token_data = await gmail_oauth.refresh_access_token(refresh_token)

        # Encrypt the new token and store it
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
    Disconnect the Gmail account.
    Revoke tokens and deactivate the account.
    """
    account = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "gmail.get_account"),
        {"account_uuid": account_uuid, "user_uuid": user_uuid}
    )

    if not account:
        raise HTTPException(status_code=404, detail="계정을 찾을 수 없습니다.")

    try:
        # Attempt to revoke the token
        if account.get("access_token_encrypted"):
            access_token = decrypt_password(
                SECRET_KEY, user_uuid, account["access_token_encrypted"]
            )
            await gmail_oauth.revoke_token(access_token)

        # Deactivate the account
        db_instance.execute_query(
            sqloader.load_sql("mail_anchor.json", "gmail.deactivate_account"),
            {"account_uuid": account_uuid}
        )

        return {"success": True, "message": "Gmail 연결 해제 완료"}

    except Exception as e:
        # Deactivate the account even if revocation fails
        db_instance.execute_query(
            sqloader.load_sql("mail_anchor.json", "gmail.deactivate_account"),
            {"account_uuid": account_uuid}
        )
        return {"success": True, "message": "Gmail 연결 해제 완료 (토큰 폐기 실패)"}


@router.get("/accounts", dependencies=[Depends(verify_token)])
async def get_gmail_accounts(user_uuid: str = Query(...)):
    """
    List Gmail accounts.
    """
    accounts = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "gmail.get_accounts"),
        {"user_uuid": user_uuid}
    )
    return accounts or []
