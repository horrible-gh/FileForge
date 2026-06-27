"""P0007 flat-contract compatibility router (B0001 / 0003 group).

WHY THIS EXISTS
---------------
The legacy mail-server was absorbed into FileForge (commit e2b21fc) by copying
its verbose, account_uuid-keyed routers verbatim (`/mail/accounts/get_accounts`,
`/mail/sync/all`, `/mail/list/{account_uuid}`, ...). The FileForge client, however,
was built against the **P0007 flat REST contract** and calls `/mail/mails`,
`/mail/sync`, `/mail/accounts`, `/mail/drafts/{id}`, ... — none of which existed
on the server, so every mail request 404'd (B0001 / NR0003).

This router presents the P0007 surface the client speaks and maps it onto the
absorbed DB store (`mail_messages` / `mail_accounts`, populated by the IMAP sync
worker) and services. It reuses the dialect-correct SQL from `mail_anchor.json`
(no new inline SQL) and emits the P0007 success/error envelope expected by the
client's `unwrapEnvelope` (mail_envelope.dart):

    success:  {"ok": true,  "data": <...>, "meta": {<...>}}
    error:    {"ok": false, "error": {"code": "...", "message": "...", ...}}

Identity comes from the RS256 access token (current_user_uuid resolves the JWT
subject — a string user_id — to users.user_uuid, the FK key); the user's
mail account is resolved implicitly (single-primary model — P0007 §6.2), since the
client never carries account_uuid in the path.
"""

from fastapi import APIRouter, Depends, Body, Request, UploadFile, File
from fastapi.responses import JSONResponse, Response
from typing import Optional, Tuple
from datetime import datetime, timezone
from email.utils import parseaddr
from urllib.parse import urlparse, urlencode
import base64
import email
import hashlib
import hmac
import ipaddress
import json
import os
import re
import socket
import uuid as uuid_lib

import httpx

from config import settings, db
from routers.login.auth import current_user_uuid
from util.crypto import decrypt_password
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

MAIL_JSON = "mail_anchor.json"


# ──────────────────────────────────────────────────────────────────────────────
# Envelope helpers (P0007 §1.1/§1.2 — mirrored by client mail_envelope.dart)
# ──────────────────────────────────────────────────────────────────────────────

def _ok(data, meta: Optional[dict] = None):
    body = {"ok": True, "data": data}
    if meta is not None:
        body["meta"] = meta
    return body


def _err(code: str, message: str, status_code: int, details: Optional[dict] = None):
    err = {"code": code, "message": message}
    if details:
        err["details"] = details
    return JSONResponse(status_code=status_code, content={"ok": False, "error": err})


def _iso(value) -> str:
    """DB datetime (str/None/datetime) → ISO-8601 string (P0007 notation)."""
    if value is None:
        return ""
    try:
        return value.isoformat()  # datetime
    except AttributeError:
        return str(value)


def _addr_list(raw) -> list:
    """\"Name <a@b>, c@d\" → [{name, address}] (P0007 §3.3)."""
    if not raw:
        return []
    out = []
    for part in str(raw).split(","):
        part = part.strip()
        if not part:
            continue
        name, addr = parseaddr(part)
        out.append({"name": name or "", "address": addr or part})
    return out


# ──────────────────────────────────────────────────────────────────────────────
# Row → P0007 DTO reshaping
# ──────────────────────────────────────────────────────────────────────────────

def _account_to_p0007(row: dict) -> dict:
    """mail_accounts row → P0007 §3.6 Account (mail_account.dart)."""
    status = row.get("status")
    p_status = "connected" if status == "active" else (status or "")
    provider = row.get("account_type")
    if not provider:
        provider = "imap" if row.get("imap_host") else "gmail"
    return {
        "account_id": row.get("account_uuid", "") or "",
        "email": row.get("email", "") or "",
        "provider": provider,
        "status": p_status,
        "connected_at": _iso(row.get("created_at")),
    }


def _labels_for(row: dict) -> list:
    folder = (row.get("folder_name") or "").strip().lower()
    return [folder] if folder else ["inbox"]


def _summary_to_p0007(row: dict) -> dict:
    """integrated mail row → P0007 §3.1 MailSummary (mail.dart)."""
    return {
        "mail_id": row.get("message_uuid", "") or "",
        "thread_id": "",
        "from": {"name": row.get("from_name") or "", "address": row.get("from_email") or ""},
        "subject": row.get("subject") or "",
        "snippet": row.get("preview") or "",
        "received_at": _iso(row.get("sent_date")),
        "is_read": bool(row.get("is_read")),
        "has_attachment": bool(row.get("has_attachments")),
        "labels": _labels_for(row),
    }


def _extract_body_from_eml(raw_email: bytes) -> Tuple[str, str]:
    """Parse a stored .eml (RFC822) and return (body_text, body_html).

    R0001 / 0006.0003-NR: the stored .eml is the **verbatim raw RFC822 message**
    (all transport/auth headers + MIME boundaries). Returning it as-is leaks the
    whole envelope into the detail body ("과도한 정보"). Here we re-parse it and
    keep only the text/plain (preferred) and text/html body parts — the same rule
    the sync parser (sync.parse_email_message) and IMAPService._extract_body use.
    """
    body_text = ""
    body_html = ""
    try:
        msg = email.message_from_bytes(raw_email)
    except Exception:  # noqa: BLE001 — defensive; fall back to caller's preview
        return "", ""

    if msg.is_multipart():
        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get("Content-Disposition", ""))
            if "attachment" in disposition:
                continue
            try:
                payload = part.get_payload(decode=True)
                if not payload:
                    continue
                charset = part.get_content_charset() or "utf-8"
                decoded = payload.decode(charset, errors="replace")
            except Exception:  # noqa: BLE001 — skip undecodable parts
                continue
            if content_type == "text/plain" and not body_text:
                body_text = decoded
            elif content_type == "text/html" and not body_html:
                body_html = decoded
    else:
        try:
            payload = msg.get_payload(decode=True)
            if payload:
                charset = msg.get_content_charset() or "utf-8"
                decoded = payload.decode(charset, errors="replace")
                if msg.get_content_type() == "text/html":
                    body_html = decoded
                else:
                    body_text = decoded
        except Exception:  # noqa: BLE001
            pass
    return body_text, body_html


# ──────────────────────────────────────────────────────────────────────────────
# Inline image surfacing (R0001 / 0007 group — "이미지 표시가 되지 않음")
# ──────────────────────────────────────────────────────────────────────────────
#
# HTML mail embeds pictures as <img src="cid:ID">, where ID maps to a MIME part's
# Content-ID. The previous detail path (a) preferred the text/plain alternative,
# so the image-bearing HTML never reached the client, and (b) even when HTML was
# returned the client stripped every tag. We re-parse the stored .eml, collect the
# inline image parts, and rewrite each cid: reference to a self-contained data:
# URI. This needs no auth-bearing image endpoint, no extra round-trip, and no
# schema change — the raw .eml already holds the image bytes.

_CID_SRC_RE = re.compile(r"""src\s*=\s*(["'])cid:([^"']+)\1""", re.IGNORECASE)


def _inline_images_from_eml(raw_email: bytes) -> dict:
    """Map Content-ID (angle brackets stripped) → (content_type, raw bytes).

    Collects every image/* MIME part that carries a Content-ID so the HTML body's
    `cid:` references can be inlined as base64 data: URIs.
    """
    out: dict = {}
    try:
        msg = email.message_from_bytes(raw_email)
    except Exception:  # noqa: BLE001 — defensive
        return out
    if not msg.is_multipart():
        return out
    for part in msg.walk():
        ctype = part.get_content_type()
        if not ctype.startswith("image/"):
            continue
        cid = part.get("Content-ID")
        if not cid:
            continue
        cid = cid.strip().strip("<>").strip()
        if not cid or cid in out:
            continue
        try:
            payload = part.get_payload(decode=True)
        except Exception:  # noqa: BLE001 — skip undecodable parts
            continue
        if payload:
            out[cid] = (ctype, payload)
    return out


def _rewrite_cid_images(html: str, inline_images: dict) -> str:
    """Rewrite <img src="cid:ID"> → <img src="data:<ct>;base64,..."> in HTML."""
    if not html or not inline_images:
        return html

    def _repl(m: "re.Match") -> str:
        quote, cid = m.group(1), m.group(2).strip()
        entry = inline_images.get(cid)
        if not entry:
            return m.group(0)
        ctype, data = entry
        b64 = base64.b64encode(data).decode("ascii")
        return f"src={quote}data:{ctype};base64,{b64}{quote}"

    return _CID_SRC_RE.sub(_repl, html)


# ──────────────────────────────────────────────────────────────────────────────
# Remote image proxy (R0001 / 0008.0007-NR — "원격 이미지 CORS 차단")
# ──────────────────────────────────────────────────────────────────────────────
#
# HTML mail commonly sources its pictures from third-party servers
# (<img src="https://www.smbc-card.com/...png">). On the Flutter *Web* client the
# CanvasKit renderer must read the raw pixel bytes to paint them, so its
# NetworkImage fetch is subject to CORS — and third-party senders never send an
# Access-Control-Allow-Origin header, so every remote image is blocked and the
# mail (which is mostly images) shows as broken icons. The legacy Vue client
# rendered DOM <img> tags, which the browser displays CORS-exempt; the regression
# came entirely from the render medium changing to CanvasKit (NR0007 §2.3).
#
# CORS headers are the *sending* server's to grant, so the receiver can never fix
# this per-domain. The general solution is for FileForge to fetch the bytes
# server-side (server↔remote is not subject to browser CORS) and re-serve them
# from its own origin, where the existing CORSMiddleware grants the read. We
# rewrite each remote <img src> in the detail body to a same-origin proxy URL.
#
# Auth note: a Flutter-Web NetworkImage GET cannot carry the RS256 Bearer header,
# so the proxy is NOT gated on current_user_uuid. Instead each proxy URL is
# HMAC-signed with SECRET_KEY at rewrite time — only URLs the server itself
# embedded into a delivered mail can be proxied. This both removes the
# missing-header problem and bounds the SSRF surface to server-chosen URLs.
# Defense-in-depth (see image_proxy): scheme allowlist, private/loopback IP block,
# image/* content-type allowlist, timeout, size cap, redirects disabled.

# <img ... src=http(s)://...> — bounded to a single tag ([^>]). The src value may
# be double-quoted, single-quoted, OR **unquoted** (`src=https://…`): real mail
# (e.g. Google's `<img alt="" height=1 src=https://notifications.google.com/g/img/…>`
# tracking pixels) routinely omits the quotes, and a quote-only matcher left those
# remote images untouched so CanvasKit still hit them cross-origin and CORS-blocked
# them — the "일부는 나오는데 일부는 막힘" rework. The `(?<![\w-])` lookbehind keeps
# `\bsrc` from matching the tail of `data-src`. cid: images are already data: URIs
# by this point, so they never match.
_REMOTE_IMG_SRC_RE = re.compile(
    r"""(<img\b[^>]*?(?<![\w-])src\s*=\s*)"""
    r"""(?:"(https?://[^"]+)"|'(https?://[^']+)'|(https?://[^\s"'>]+))""",
    re.IGNORECASE,
)

_IMG_PROXY_TIMEOUT = 10.0              # seconds
_IMG_PROXY_MAX_BYTES = 12 * 1024 * 1024  # 12 MiB ceiling per image


def _img_proxy_sig(url: str) -> str:
    """HMAC-SHA256 of the remote URL, keyed by SECRET_KEY (unforgeable token)."""
    key = (settings.SECRET_KEY or "").encode("utf-8")
    return hmac.new(key, url.encode("utf-8"), hashlib.sha256).hexdigest()


def _sign_remote_url(url: str, proxy_endpoint: str) -> str:
    """Build the same-origin, HMAC-signed proxy URL for a remote image URL."""
    token = base64.urlsafe_b64encode(url.encode("utf-8")).decode("ascii").rstrip("=")
    qs = urlencode({"u": token, "sig": _img_proxy_sig(url)})
    return f"{proxy_endpoint}?{qs}"


def _rewrite_remote_images(html: str, proxy_endpoint: Optional[str]) -> str:
    """Rewrite remote <img src> → same-origin signed proxy URL (CORS-safe).

    Handles double-quoted, single-quoted, and unquoted ``src`` values; the
    rewritten value is always emitted double-quoted (the signed proxy URL carries
    ``?``/``&``, so an unquoted result would be malformed).
    """
    if not html or not proxy_endpoint:
        return html

    def _repl(m: "re.Match") -> str:
        prefix = m.group(1)
        url = m.group(2) or m.group(3) or m.group(4)  # dq | sq | unquoted
        return f'{prefix}"{_sign_remote_url(url, proxy_endpoint)}"'

    return _REMOTE_IMG_SRC_RE.sub(_repl, html)


def _is_safe_public_host(hostname: str) -> bool:
    """SSRF guard: every resolved address must be a routable public IP.

    Blocks private/loopback/link-local (incl. the 169.254.169.254 cloud metadata
    endpoint)/multicast/reserved/unspecified targets. A DNS failure is treated as
    unsafe (fail closed).
    """
    try:
        infos = socket.getaddrinfo(hostname, None)
    except Exception:  # noqa: BLE001 — unresolvable → unsafe
        return False
    if not infos:
        return False
    for info in infos:
        try:
            addr = ipaddress.ip_address(info[4][0])
        except ValueError:
            return False
        if (addr.is_private or addr.is_loopback or addr.is_link_local
                or addr.is_multicast or addr.is_reserved or addr.is_unspecified):
            return False
    return True


def _img_proxy_endpoint(request: Request) -> Optional[str]:
    """Absolute URL of the image-proxy route for the current origin, or None."""
    try:
        return str(request.url_for("image_proxy"))
    except Exception:  # noqa: BLE001 — route lookup is best-effort
        return None


def _detail_to_p0007(row: dict, attachments: list,
                     proxy_endpoint: Optional[str] = None) -> dict:
    """get_mail row (m.* + account) → P0007 §3.2 MailDetail (mail.dart).

    When ``proxy_endpoint`` is given, remote <img src> in an HTML body are rewritten
    to same-origin signed proxy URLs so Flutter-Web CanvasKit can read their bytes
    (R0001 / NR0007). Left untouched when None (e.g. unit calls without a request).
    """
    body_text = ""
    body_html = ""
    raw = b""
    bfp = row.get("body_file_path")
    if bfp and os.path.exists(bfp):
        try:
            with open(bfp, "rb") as fh:
                raw = fh.read()
        except OSError:
            raw = b""
    if raw:
        body_text, body_html = _extract_body_from_eml(raw)
    # Prefer HTML when it carries images so the pictures actually render in the
    # client (R0001 — cid: inline images are rewritten to data: URIs). For ordinary
    # mail keep the clean text/plain alternative (avoids the 0006 "excessive info"
    # markup noise). Finally fall back to whatever HTML/snippet exists.
    html_has_img = bool(body_html) and "<img" in body_html.lower()
    if html_has_img:
        body_format = "html"
        body_content = _rewrite_cid_images(body_html, _inline_images_from_eml(raw))
        # cid: images are now data: URIs; route the remaining remote images through
        # the same-origin proxy so CanvasKit's byte fetch isn't CORS-blocked.
        body_content = _rewrite_remote_images(body_content, proxy_endpoint)
    elif body_text:
        body_format, body_content = "text", body_text
    elif body_html:
        body_format, body_content = "html", body_html
    else:
        body_format, body_content = "text", (row.get("preview") or "")
    return {
        "mail_id": row.get("message_uuid", "") or "",
        "thread_id": "",
        "from": {"name": row.get("from_name") or "", "address": row.get("from_email") or ""},
        "to": _addr_list(row.get("to_emails")),
        "cc": _addr_list(row.get("cc_emails")),
        "subject": row.get("subject") or "",
        "received_at": _iso(row.get("sent_date")),
        "is_read": bool(row.get("is_read")),
        "body": {"format": body_format, "content": body_content},
        "attachments": attachments,
        "labels": _labels_for(row),
    }


def _resolve_accounts(user_uuid: str) -> list:
    """All active accounts for the user (single-primary model — implicit account)."""
    sql = sqloader.load_sql(MAIL_JSON, "get_user_accounts")
    return db_instance.fetch_all(sql, (user_uuid,)) or []


# ──────────────────────────────────────────────────────────────────────────────
# Accounts (P0007 §7.14)
# ──────────────────────────────────────────────────────────────────────────────

@router.get("/accounts")
async def list_accounts(user_uuid: str = Depends(current_user_uuid)):
    """GET /mail/accounts — connected accounts. (B0001 symptom #1)"""
    rows = _resolve_accounts(user_uuid)
    return _ok([_account_to_p0007(r) for r in rows])


@router.get("/accounts/oauth/authorize")
async def authorize_account(provider: str, user_uuid: str = Depends(current_user_uuid)):
    """GET /mail/accounts/oauth/authorize?provider= — provider consent URL."""
    provider = (provider or "").lower()
    if provider not in ("gmail", "outlook"):
        return _err("VALIDATION_FAILED", f"provider '{provider}' does not use OAuth", 400,
                    {"field": "provider"})
    try:
        from .oauth import gmail_auth
        result = await gmail_auth.get_gmail_auth_url(user_uuid=user_uuid)
    except Exception as exc:  # noqa: BLE001 — surface as enveloped error, never 404/500
        logger.error(f"[compat authorize] {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "oauth not configured", 503,
                    {"reason": "oauth not configured"})
    auth_url = None
    if isinstance(result, dict):
        auth_url = result.get("auth_url") or result.get("url")
    if not auth_url:
        return _err("UPSTREAM_UNAVAILABLE", "authorize response missing auth_url", 503,
                    {"reason": "oauth not configured"})
    return _ok({"auth_url": auth_url, "state": result.get("state", "") if isinstance(result, dict) else ""})


@router.post("/accounts")
async def connect_account(payload: dict = Body(default={}), user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/accounts — connect via provider + auth_code.

    The live Gmail connection is completed through the browser-redirect callback
    (`/oauth/gmail/callback`), so a direct code-exchange here is intentionally
    surfaced as an enveloped, retriable error rather than a 404 — the client's
    primary path is authorize() → browser → callback → listAccounts().
    """
    provider = (payload.get("provider") or "").lower()
    if provider not in ("gmail", "outlook", "imap"):
        return _err("VALIDATION_FAILED", "unknown provider", 400, {"field": "provider"})
    if not payload.get("auth_code"):
        return _err("VALIDATION_FAILED", "auth_code required", 400, {"field": "auth_code"})
    return _err(
        "UPSTREAM_UNAVAILABLE",
        "complete the connection via the browser OAuth flow (authorize → callback)",
        503,
        {"reason": "oauth exchange via callback"},
    )


@router.delete("/accounts/{account_id}")
async def delete_account(account_id: str, user_uuid: str = Depends(current_user_uuid)):
    """DELETE /mail/accounts/{id} — disconnect account."""
    sql = sqloader.load_sql(MAIL_JSON, "accounts.remove_account")
    db_instance.execute_query(sql, {"account_uuid": account_id})
    return JSONResponse(status_code=204, content=None)


# ──────────────────────────────────────────────────────────────────────────────
# Sync (P0007 §7.15) — synchronous IMAP fetch → store merge
# ──────────────────────────────────────────────────────────────────────────────

@router.post("/sync")
def trigger_sync(user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/sync — fetch new mail for the user's accounts into the store.

    Runs inline (not background) so the store is merged by the time the client
    re-reads `/mails`. Per-account failures are swallowed (logged) so a single
    flaky account never turns the trigger into a 5xx. (B0001 symptom #2)
    """
    from .sync import sync_account_mails
    accounts = _resolve_accounts(user_uuid)
    applied = 0
    reauth_required = False
    for acc in accounts:
        if not acc.get("sync_enabled", 1):
            continue
        if acc.get("account_type") == "gmail" and not acc.get("refresh_token_encrypted"):
            reauth_required = True
            continue
        try:
            res = sync_account_mails(acc["account_uuid"], user_uuid, "INBOX")
            applied += int((res or {}).get("new_mails", 0) or 0)
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[compat sync] account {acc.get('account_uuid')}: {exc}")
    return _ok({"state": "idle", "applied": applied, "reauth_required": reauth_required})


# ──────────────────────────────────────────────────────────────────────────────
# Mails (P0007 §7.1/§7.3) — read from the store
# ──────────────────────────────────────────────────────────────────────────────

@router.get("/mails")
async def list_mails(
    label: Optional[str] = None,
    q: Optional[str] = None,
    unread: Optional[bool] = None,
    cursor: Optional[str] = None,
    limit: int = 20,
    user_uuid: str = Depends(current_user_uuid),
):
    """GET /mail/mails — paginated mail summaries from the store. (B0001 symptom #3)"""
    try:
        lim = max(1, min(int(limit or 20), 100))
    except (TypeError, ValueError):
        lim = 20
    try:
        offset = max(0, int(cursor)) if cursor else 0
    except (TypeError, ValueError):
        offset = 0

    mail1 = sqloader.load_sql(MAIL_JSON, "inbox.get_integrated_mail1")
    mail2 = sqloader.load_sql(MAIL_JSON, "inbox.get_integrated_mail2")
    # mail1 ends on "AND a.status = 'active'"; it is designed to take further AND
    # clauses before mail2 (ORDER BY ... LIMIT ? OFFSET ?). Integer literals only
    # → dialect-safe (no extra bind params inserted between the existing ones).
    extra = " AND m.is_deleted = 0 "
    if unread:
        extra += " AND m.is_read = 0 "
    sql = mail1 + extra + mail2
    # fetch one extra row to compute has_more without a second COUNT query
    rows = db_instance.fetch_all(sql, (user_uuid, lim + 1, offset)) or []
    has_more = len(rows) > lim
    rows = rows[:lim]

    if q:
        ql = q.lower()
        rows = [
            r for r in rows
            if ql in (
                f"{r.get('subject', '')}{r.get('from_email', '')}"
                f"{r.get('from_name', '')}{r.get('preview', '')}"
            ).lower()
        ]
    if label and label.lower() not in ("inbox", "all", ""):
        rows = [r for r in rows if (r.get("folder_name") or "").lower() == label.lower()]

    items = [_summary_to_p0007(r) for r in rows]
    meta = {
        "next_cursor": str(offset + lim) if has_more else None,
        "has_more": has_more,
        "count": len(items),
    }
    return _ok(items, meta)


@router.get("/mails/{mail_id}")
async def get_mail(mail_id: str, request: Request,
                   user_uuid: str = Depends(current_user_uuid)):
    """GET /mail/mails/{id} — full mail detail from the store."""
    sql = sqloader.load_sql(MAIL_JSON, "inbox.get_mail")
    row = db_instance.fetch_one(sql, (mail_id, user_uuid))
    if not row:
        return _err("MAIL_NOT_FOUND", "mail not found", 404)
    attachments = []
    try:
        att_sql = sqloader.load_sql(MAIL_JSON, "inbox.get_attachment")
        for a in (db_instance.fetch_all(att_sql, (mail_id,)) or []):
            attachments.append({
                "attachment_id": a.get("attachment_uuid", "") or "",
                "filename": a.get("filename", "") or "",
                "size_bytes": int(a.get("size_bytes") or 0),
                "content_type": a.get("content_type", "") or "",
            })
    except Exception as exc:  # noqa: BLE001 — attachments are best-effort
        logger.debug(f"[compat detail] attachments load failed: {exc}")
    return _ok(_detail_to_p0007(row, attachments, _img_proxy_endpoint(request)))


@router.get("/image-proxy", name="image_proxy")
async def image_proxy(u: str, sig: str):
    """GET /mail/image-proxy?u=&sig= — re-serve a remote mail image same-origin.

    Resolves the CORS block on remote <img> in the Flutter-Web client (R0001 /
    0008.0007-NR). Intentionally unauthenticated — a NetworkImage GET cannot carry
    the Bearer header — but gated by the HMAC signature so only URLs the server
    itself embedded into a delivered mail can be fetched. The remaining SSRF
    defenses run before any outbound request is made.
    """
    try:
        pad = "=" * (-len(u) % 4)
        url = base64.urlsafe_b64decode(u + pad).decode("utf-8")
    except Exception:  # noqa: BLE001 — malformed token
        return _err("VALIDATION_FAILED", "bad image token", 400, {"field": "u"})

    # Signature gate: rejects any URL the server did not sign (SSRF gate #1).
    if not hmac.compare_digest(_img_proxy_sig(url), sig or ""):
        return _err("VALIDATION_FAILED", "bad image signature", 403, {"field": "sig"})

    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        return _err("VALIDATION_FAILED", "unsupported image url", 400, {"field": "u"})
    if not _is_safe_public_host(parsed.hostname):
        return _err("VALIDATION_FAILED", "blocked image host", 403, {"field": "u"})

    try:
        async with httpx.AsyncClient(timeout=_IMG_PROXY_TIMEOUT,
                                     follow_redirects=False) as client:
            resp = await client.get(url, headers={
                "User-Agent": "FileForge-ImageProxy/1.0",
                "Accept": "image/*",
            })
    except Exception as exc:  # noqa: BLE001
        logger.warning(f"[image-proxy] fetch failed {parsed.hostname}: {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "image fetch failed", 502)

    if resp.status_code != 200:
        return _err("UPSTREAM_UNAVAILABLE", "image fetch failed", 502,
                    {"upstream_status": resp.status_code})
    ctype = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
    if not ctype.startswith("image/"):
        return _err("VALIDATION_FAILED", "not an image", 415, {"content_type": ctype})
    content = resp.content
    if len(content) > _IMG_PROXY_MAX_BYTES:
        return _err("VALIDATION_FAILED", "image too large", 413)

    # CORS headers are added by the app's CORSMiddleware (echoes the app origin),
    # which is exactly what lets CanvasKit read these bytes cross-origin.
    return Response(content=content, media_type=ctype,
                    headers={"Cache-Control": "private, max-age=3600"})


@router.patch("/mails/{mail_id}")
async def set_mail_read(mail_id: str, payload: dict = Body(default={}),
                        user_uuid: str = Depends(current_user_uuid)):
    """PATCH /mail/mails/{id} {is_read} — read/unread state."""
    is_read = 1 if payload.get("is_read") else 0
    sql = sqloader.load_sql(MAIL_JSON, "update_message_read")
    db_instance.execute_query(sql, (is_read, mail_id))
    return _ok({"mail_id": mail_id, "is_read": bool(is_read)})


# ──────────────────────────────────────────────────────────────────────────────
# Send (P0007 §7.5)
# ──────────────────────────────────────────────────────────────────────────────

def _addrs_to_strings(items) -> list:
    out = []
    for a in (items or []):
        if isinstance(a, dict):
            addr = a.get("address")
            if addr:
                out.append(addr)
        elif a:
            out.append(str(a))
    return out


@router.post("/mails")
def send_mail(payload: dict = Body(default={}), user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/mails — send a message from the user's primary account."""
    to_list = _addrs_to_strings(payload.get("to"))
    if not to_list:
        return _err("RECIPIENT_INVALID", "at least one recipient is required", 422,
                    {"field": "to"})
    cc_list = _addrs_to_strings(payload.get("cc")) or None
    bcc_list = _addrs_to_strings(payload.get("bcc")) or None
    body = payload.get("body") or {}
    subject = payload.get("subject") or ""
    body_text = body.get("content", "") if body.get("format") != "html" else ""
    body_html = body.get("content", "") if body.get("format") == "html" else ""

    accounts = _resolve_accounts(user_uuid)
    if not accounts:
        return _err("VALIDATION_FAILED", "no connected account to send from", 400)
    account = accounts[0]

    try:
        if account.get("account_type") == "gmail":
            return _err("UPSTREAM_UNAVAILABLE",
                        "gmail send requires an active OAuth session; reconnect if needed",
                        503, {"reason": "oauth send"})
        from services.smtp_service import SMTPService
        smtp_password = decrypt_password(
            settings.SECRET_KEY, user_uuid, account["smtp_password_encrypted"])
        smtp = SMTPService(
            host=account["smtp_host"],
            port=account["smtp_port"],
            username=account["smtp_username"],
            password=smtp_password,
        )
        connect_result = smtp.connect()
        if not connect_result.get("success"):
            return _err("SEND_FAILED", connect_result.get("message", "smtp connect failed"), 502)
        try:
            send_result = smtp.send_mail(
                from_name=account.get("account_name", account["email"]),
                from_email=account["email"],
                to_addresses=to_list,
                subject=subject,
                body_text=body_text,
                body_html=body_html,
                cc_addresses=cc_list,
                bcc_addresses=bcc_list,
                attachments=None,
            )
        finally:
            smtp.disconnect()
        if not send_result.get("success"):
            return _err("SEND_FAILED", send_result.get("message", "send failed"), 502)
    except Exception as exc:  # noqa: BLE001
        logger.error(f"[compat send] {exc}")
        return _err("SEND_FAILED", str(exc), 502)

    return _ok({"mail_id": str(uuid_lib.uuid4()), "status": "sent"})


# ──────────────────────────────────────────────────────────────────────────────
# Attachments (P0007 §7.11) — compose-time upload, best-effort store-to-disk
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Drafts (P0007 §7.9/§7.10) — self-contained on-disk store
# ──────────────────────────────────────────────────────────────────────────────
#
# The absorbed drafts router (`/mail/drafts/save`, `/delete`) uses MySQL-flavored
# inline SQL (`%(...)s`, NOW()) that is not portable to the sqlite/pg deployments,
# and its shape (Form fields + account_uuid) does not match the P0007 client
# (JSON SendPayload, no account in path). Rather than reshape fragile SQL we back
# the P0007 draft CRUD with a dialect-independent JSON file store keyed per user.

def _drafts_dir(user_uuid: str) -> str:
    base = settings.MAIL_STORAGE_BASE_PATH or "./data/mails"
    return os.path.join(base, "_drafts", user_uuid)


def _draft_path(user_uuid: str, draft_id: str) -> str:
    # draft_id is a server-minted uuid; guard against path traversal regardless.
    safe = os.path.basename(draft_id)
    return os.path.join(_drafts_dir(user_uuid), f"{safe}.json")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _draft_from_payload(payload: dict, draft_id: str, updated_at: str) -> dict:
    body = payload.get("body") or {}
    return {
        "draft_id": draft_id,
        "to": payload.get("to") or [],
        "cc": payload.get("cc") or [],
        "bcc": payload.get("bcc") or [],
        "subject": payload.get("subject") or "",
        "body": {"format": body.get("format", "text"), "content": body.get("content", "")},
        "attachments": payload.get("attachments") or [],
        "updated_at": updated_at,
    }


@router.post("/drafts")
async def save_draft(payload: dict = Body(default={}), user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/drafts — create a draft, return its id + updated_at."""
    draft_id = str(uuid_lib.uuid4())
    updated_at = _now_iso()
    record = _draft_from_payload(payload, draft_id, updated_at)
    try:
        os.makedirs(_drafts_dir(user_uuid), exist_ok=True)
        with open(_draft_path(user_uuid, draft_id), "w", encoding="utf-8") as fh:
            json.dump(record, fh, ensure_ascii=False)
    except OSError as exc:
        logger.error(f"[compat draft save] {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "draft store failed", 503)
    return _ok({"draft_id": draft_id, "updated_at": updated_at})


@router.get("/drafts/{draft_id}")
async def get_draft(draft_id: str, user_uuid: str = Depends(current_user_uuid)):
    """GET /mail/drafts/{id} — load a draft (P0007 §3 MailDraft)."""
    path = _draft_path(user_uuid, draft_id)
    if not os.path.exists(path):
        return _err("MAIL_NOT_FOUND", "draft not found", 404)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return _ok(json.load(fh))
    except (OSError, json.JSONDecodeError) as exc:
        logger.error(f"[compat draft get] {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "draft read failed", 503)


@router.put("/drafts/{draft_id}")
async def update_draft(draft_id: str, payload: dict = Body(default={}),
                       user_uuid: str = Depends(current_user_uuid)):
    """PUT /mail/drafts/{id} — overwrite a draft (optimistic via base_updated_at)."""
    path = _draft_path(user_uuid, draft_id)
    if not os.path.exists(path):
        return _err("MAIL_NOT_FOUND", "draft not found", 404)
    base = payload.get("base_updated_at")
    if base:
        try:
            with open(path, "r", encoding="utf-8") as fh:
                current = json.load(fh)
            if current.get("updated_at") and current["updated_at"] != base:
                return _err("DRAFT_CONFLICT", "draft was modified elsewhere", 409,
                            {"updated_at": current["updated_at"]})
        except (OSError, json.JSONDecodeError):
            pass
    updated_at = _now_iso()
    record = _draft_from_payload(payload, draft_id, updated_at)
    try:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(record, fh, ensure_ascii=False)
    except OSError as exc:
        logger.error(f"[compat draft update] {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "draft store failed", 503)
    return _ok({"draft_id": draft_id, "updated_at": updated_at})


@router.delete("/drafts/{draft_id}")
async def delete_draft(draft_id: str, user_uuid: str = Depends(current_user_uuid)):
    """DELETE /mail/drafts/{id} — remove a draft."""
    path = _draft_path(user_uuid, draft_id)
    try:
        if os.path.exists(path):
            os.remove(path)
    except OSError as exc:
        logger.error(f"[compat draft delete] {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "draft delete failed", 503)
    return JSONResponse(status_code=204, content=None)


@router.post("/attachments")
async def upload_attachment(file: UploadFile = File(...),
                            user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/attachments — stage a compose attachment, return its handle."""
    attachment_id = str(uuid_lib.uuid4())
    content = await file.read()
    base = settings.MAIL_STORAGE_BASE_PATH or "./data/mails"
    dest_dir = os.path.join(base, "_compose_attachments", user_uuid)
    try:
        os.makedirs(dest_dir, exist_ok=True)
        with open(os.path.join(dest_dir, attachment_id), "wb") as fh:
            fh.write(content)
    except OSError as exc:
        logger.error(f"[compat attachment] store failed: {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "attachment store failed", 503)
    return _ok({
        "attachment_id": attachment_id,
        "filename": file.filename or "",
        "size_bytes": len(content),
        "content_type": file.content_type or "application/octet-stream",
    })
