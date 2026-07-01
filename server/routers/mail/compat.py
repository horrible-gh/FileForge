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
from util.mail_time import iso_utc, now_utc_naive
from email.utils import parseaddr, getaddresses
from email.header import decode_header, make_header
from urllib.parse import urlparse, urlencode
import base64
import email
import hashlib
import hmac
import asyncio
import ipaddress
import json
import os
import re
import socket
import uuid as uuid_lib

import httpx

from config import settings, db, mail_storage_base, DBType, adapt_query
from routers.login.auth import current_user_uuid
from .sync import strip_html_to_text, make_preview

# A genuine HTML tag (``<div>``, ``<html lang=…>``, ``<br/>``, ``</p>``) — the tag
# name must be followed by whitespace, ``>`` or ``/>``. This deliberately does NOT
# match plain-text ``<https://…>`` URLs or ``<user@host>`` addresses (after the
# leading word comes ``:``/``@``), so legitimate bracketed text is left intact.
_HTML_TAGISH_RE = re.compile(r"</?[a-zA-Z][a-zA-Z0-9]*(?:\s|/?>)")
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
    """DB sent_date (UTC by storage convention) → ISO-8601 with explicit +00:00.

    The stored sent_date is naive-UTC (see util.mail_time / 0025.0003-NR). Emitting
    an explicit offset is what lets the client's DateTime.parse(...).toLocal()
    convert to the viewer's local zone instead of rendering UTC verbatim.
    """
    return iso_utc(value)


def _decode_mime_words(value: str) -> str:
    """Decode RFC 2047 encoded-words (``=?charset?B?..?=``) to plain text.

    R0001 / 0017: non-ASCII display names arrive encoded; ``parseaddr`` does NOT
    decode them, so an undecoded To header surfaced raw Base64 in the 宛先 field.
    Idempotent — already-plain text passes through unchanged.
    """
    if not value or "=?" not in value:
        return value or ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:  # noqa: BLE001 — never let a malformed encoded-word break the response
        return value


def _addr_list(raw) -> list:
    """\"Name <a@b>, c@d\" → [{name, address}] (P0007 §3.3).

    Uses ``getaddresses`` (comma-safe across quoted/encoded display names) and
    decodes RFC 2047 encoded-words in the display name so the 宛先 field shows the
    real name instead of raw Base64 (R0001).
    """
    if not raw:
        return []
    out = []
    for name, addr in getaddresses([str(raw)]):
        name = _decode_mime_words(name)
        if not name and not addr:
            continue
        out.append({"name": name or "", "address": addr or name})
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


# System folders the P0007 client surfaces as fixed label tabs (mail_list_screen
# kMailSystemLabels). Their identity is the `folder_type` enum value, NOT the
# display name: a Sent folder is `folder_type='sent'` regardless of whether its
# `folder_name` is "Sent", "보낸편지함" or "[Gmail]/Sent Mail". (B0001 / 0038)
_SYSTEM_FOLDER_TYPES = ("inbox", "sent", "drafts", "trash", "spam")


def _labels_for(row: dict) -> list:
    # Prefer the canonical folder_type so the Sent tab (label 'sent') matches a
    # sent folder no matter its localized display name (B0001 / 0038). Fall back to
    # the display name for custom folders and to "inbox" when no folder is joined.
    ftype = (row.get("folder_type") or "").strip().lower()
    if ftype in _SYSTEM_FOLDER_TYPES:
        return [ftype]
    folder = (row.get("folder_name") or "").strip().lower()
    return [folder] if folder else ["inbox"]


def _summary_to_p0007(row: dict) -> dict:
    """integrated mail row → P0007 §3.1 MailSummary (mail.dart).

    R0001 (0013): in the multi-account inbox the user could not tell *which of
    their own mailboxes* each message arrived in without opening it. The
    integrated-mail SQL already JOINs the owning account
    (`a.account_name`, `a.email as account_email`, `a.display_color`,
    `m.account_uuid`), but this summary mapper used to drop every one of those
    columns — so the client literally never received the account identity and
    the list could not render it. Surface it here as an `account` object the
    client can show as a per-row badge.
    """
    # Defense-in-depth (B0001 / 0018): an un-backfilled legacy preview may still hold
    # raw HTML markup (HTML-only mail had no text/plain). Strip it at read time so the
    # list never shows tags/comments even before the DB backfill lands. Detect a real
    # HTML comment or tag (``<div>``/``<html …``/``<br/>``) — NOT bracketed plain-text
    # URLs/emails (``<https://…>``, ``<a@b>``), which must survive intact. (Charset
    # mojibake in old previews can't be recovered here — that needs the .eml re-read
    # backfill — but raw markup always can.)
    snippet = row.get("preview") or ""
    if "<!--" in snippet or _HTML_TAGISH_RE.search(snippet):
        snippet = strip_html_to_text(snippet)
    return {
        "mail_id": row.get("message_uuid", "") or "",
        "thread_id": "",
        "from": {"name": row.get("from_name") or "", "address": row.get("from_email") or ""},
        "subject": row.get("subject") or "",
        "snippet": snippet,
        "received_at": _iso(row.get("sent_date")),
        "is_read": bool(row.get("is_read")),
        # R0001 (0027 mail pin): the integrated-mail SQL already SELECTs m.is_pinned
        # (and m.is_starred), but this mapper used to drop both — so the client never
        # received the pin state and could neither show it nor float pinned mail to the
        # top. Surface is_pinned (and the sibling is_starred) here. (is_starred is free
        # to expose and harmless to clients that ignore it.)
        "is_pinned": bool(row.get("is_pinned")),
        "is_starred": bool(row.get("is_starred")),
        "has_attachment": bool(row.get("has_attachments")),
        "labels": _labels_for(row),
        "account": {
            "account_id": row.get("account_uuid", "") or "",
            "email": row.get("account_email", "") or "",
            "name": row.get("account_name", "") or "",
            "color": row.get("display_color", "") or "",
        },
    }


def _extract_body_from_eml(raw_email: bytes) -> Tuple[str, str]:
    """Parse a stored .eml (RFC822) and return (body_text, body_html).

    R0001 / 0006.0003-NR: the stored .eml is the **verbatim raw RFC822 message**
    (all transport/auth headers + MIME boundaries). Returning it as-is leaks the
    whole envelope into the detail body ("excessive info"). Here we re-parse it and
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
# Inline image surfacing (R0001 / 0007 group — "images not displaying")
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
# Remote image proxy (R0001 / 0008.0007-NR — "remote images CORS-blocked")
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
# them — the "some show, some are blocked" rework. The `(?<![\w-])` lookbehind keeps
# `\bsrc` from matching the tail of `data-src`. cid: images are already data: URIs
# by this point, so they never match.
_REMOTE_IMG_SRC_RE = re.compile(
    r"""(<img\b[^>]*?(?<![\w-])src\s*=\s*)"""
    r"""(?:"(https?://[^"]+)"|'(https?://[^']+)'|(https?://[^\s"'>]+))""",
    re.IGNORECASE,
)

# HTML `background="http(s)://…"` attribute — responsive marketing mail puts layout
# images on <td>/<table> via this attribute. The `(?<![\w-])` lookbehind keeps it
# from matching `data-background`; CSS `background:` uses a colon (→ _CSS_URL_RE), so
# the two never collide. (B0001 / 0015.0003-NR defect A — these bypassed the
# <img>-only rewrite and stayed CORS-blocked on Flutter-Web CanvasKit.)
_BG_ATTR_RE = re.compile(
    r"""((?<![\w-])background\s*=\s*)"""
    r"""(?:"(https?://[^"]+)"|'(https?://[^']+)'|(https?://[^\s"'>]+))""",
    re.IGNORECASE,
)

# CSS `url( http(s)://… )` inside inline style= or <style> blocks, e.g.
# `background:url(https://img1.kbcard.com/…/email_dot.jpg)` — the visible "not showing"
# in B0001. Quotes are optional in CSS. cid:/data: are not http(s):// so the
# inlined images never match. The same-origin proxy URL we emit always lives inside
# an `src="…"`/`background="…"`, never inside `url(…)`, so this pass never re-wraps it.
_CSS_URL_RE = re.compile(
    r"""(url\(\s*)"""
    r"""(?:"(https?://[^"]+)"|'(https?://[^']+)'|(https?://[^)\s"']+))"""
    r"""(\s*\))""",
    re.IGNORECASE,
)

_IMG_PROXY_TIMEOUT = 10.0              # seconds
_IMG_PROXY_MAX_BYTES = 12 * 1024 * 1024  # 12 MiB ceiling per image

# 1×1 fully transparent PNG — served (200) in place of a hard error when a remote
# mail image cannot be fetched or validated (B0001 / 0015.0003-NR defect B). Open-
# tracking beacons (email.kbcard.com/check.jsp) and senders whose TLS chain certifi
# can't verify otherwise surface as 502/415 console noise + a broken-image glyph; a
# transparent pixel renders nothing, the correct outcome for an un-loadable image.
_BLANK_PIXEL_PNG = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk"
    b"+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
)


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
    """Rewrite every remote image reference → same-origin signed proxy URL.

    Covers all the ways HTML mail sources a remote picture, not just ``<img src>``:

      * ``<img src=…>``              (double/single/unquoted)
      * ``<td>/<table background=…>``  attribute
      * CSS ``url(…)`` in ``style=`` / ``<style>`` (e.g. ``background:url(https://…)``)

    Responsive marketing mail (KB Card etc.) leans heavily on CSS background and the
    ``background`` attribute for layout images; the previous ``<img>``-only matcher
    left those CORS-blocked on Flutter-Web CanvasKit — the visible "not showing" in B0001
    (0015.0003-NR defect A). Attribute rewrites (``src=``/``background=``) emit the
    proxy URL double-quoted because they replace the whole attribute; the CSS
    ``url(…)`` rewrite emits it UNQUOTED because it is nested inside a (usually
    double-quoted) ``style="…"`` attribute and a double quote there would close the
    attribute early and make the HTML parser swallow the rest of the body (B0001 /
    0018 — KB statement rendered blank). cid: (already data: URIs by this point) and
    data: are never matched. The three passes target disjoint syntactic contexts, so
    the proxy URL one pass inserts is never re-wrapped by another (the emitted URL
    lives in ``src=…``/``background=…``/``url(…)``, none of which re-match).
    """
    if not html or not proxy_endpoint:
        return html

    def _attr_repl(m: "re.Match") -> str:
        prefix = m.group(1)
        url = m.group(2) or m.group(3) or m.group(4)  # dq | sq | unquoted
        return f'{prefix}"{_sign_remote_url(url, proxy_endpoint)}"'

    def _css_repl(m: "re.Match") -> str:
        url = m.group(2) or m.group(3) or m.group(4)  # dq | sq | unquoted
        # Emit the proxy URL UNQUOTED. A CSS url() almost always lives inside a
        # double-quoted style="…" attribute (`style="background:url(https://…)"`);
        # wrapping the rewritten URL in double quotes there — `style="…url("PROXY")…"`
        # — closes the attribute at the first inner quote, so the HTML parser treats
        # the rest of the URL/tag as garbage and SWALLOWS the remainder of the
        # document. That is exactly why the KB-statement body rendered blank in the
        # Flutter client (B0001 / 0018 — fwfh produced zero text widgets). The signed
        # proxy URL is pure [A-Za-z0-9_?=&/:.-] (urlsafe-base64 token + hex sig + the
        # endpoint path), i.e. a valid *unquoted* CSS url token, so it collides with
        # neither double- nor single-quoted style attributes nor a <style> block.
        return f'{m.group(1)}{_sign_remote_url(url, proxy_endpoint)}{m.group(5)}'

    html = _REMOTE_IMG_SRC_RE.sub(_attr_repl, html)
    html = _BG_ATTR_RE.sub(_attr_repl, html)
    html = _CSS_URL_RE.sub(_css_repl, html)
    return html


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


# Server package root (…/server) — compat.py is at …/server/routers/mail/compat.py.
# body_file_path is stored RELATIVE ("data/mails/…"); resolving it only against the
# process CWD silently failed when the server was launched from elsewhere, dropping
# the detail body to the raw-HTML preview rendered as plain text (B0001 / 0018 §4.1).
_SERVER_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _resolve_body_path(bfp: Optional[str]) -> Optional[str]:
    """Resolve a stored (possibly relative) body_file_path to an existing file.

    Tries the path as-is (absolute, or relative to CWD), then anchored to the
    server root. Returns the first existing path, else None.
    """
    if not bfp:
        return None

    def _try(p: Optional[str]) -> Optional[str]:
        if not p:
            return None
        if os.path.exists(p):
            return p
        if not os.path.isabs(p):
            anchored = os.path.join(_SERVER_ROOT, p)
            if os.path.exists(anchored):
                return anchored
        return None

    found = _try(bfp)
    if found:
        return found

    # 0021/R0001 migration safety: rows may carry any of several historical bases
    # (legacy `data/mails/...`, the interim `storage/mail/...`, or the DB-designated
    # absolute mail storage root) while the file physically lives under another during
    # a partial backfill. Re-anchor the per-account suffix (`{account}/messages/…` or
    # `{account}/attachments/…`) onto the DB-designated base so a body never silently
    # drops to a blank just because the base was switched.
    norm = bfp.replace("\\", "/")
    KNOWN_BASES = ("data/mails", "storage/mail")
    for base in KNOWN_BASES:
        if norm.startswith(base + "/"):
            suffix = norm[len(base) + 1:]           # {account}/messages/{..}/x.eml
            account = suffix.split("/", 1)[0] if "/" in suffix else None
            designated = mail_storage_base(account_uuid=account)
            found = _try(os.path.join(designated, *suffix.split("/")))
            if found:
                return found
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
    bfp = _resolve_body_path(row.get("body_file_path"))
    if bfp:
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
        # R0001 (0035) — the *receiving* account this mail arrived at, so a reply/forward
        # can default its sender to the same account instead of the arbitrary first one.
        "account_id": row.get("account_uuid", "") or "",
        "from": {"name": row.get("from_name") or "", "address": row.get("from_email") or ""},
        "to": _addr_list(row.get("to_emails")),
        "cc": _addr_list(row.get("cc_emails")),
        "subject": row.get("subject") or "",
        "received_at": _iso(row.get("sent_date")),
        "is_read": bool(row.get("is_read")),
        # R0001 (0027 mail pin) — get_mail SELECTs m.* so is_pinned is present; expose
        # it so the detail screen's pin toggle reflects the current state on open.
        "is_pinned": bool(row.get("is_pinned")),
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
    # 204 must be body-less: JSONResponse(content=None) emits b"null" (4 bytes),
    # which h11 rejects with "Too much data for declared Content-Length",
    # breaking the connection and failing the delete (B0001).
    return Response(status_code=204)


# ──────────────────────────────────────────────────────────────────────────────
# Sync (P0007 §7.15) — synchronous IMAP fetch → store merge
# ──────────────────────────────────────────────────────────────────────────────

def _gmail_refresh_token_usable(acc: dict, user_uuid: str) -> bool:
    """True iff a Gmail account has a *usable* (non-empty) refresh token.

    The bare `acc["refresh_token_encrypted"]` truthiness check is NOT sufficient
    (B0001 / NR0003 H3): a missing refresh token is stored as `encrypt("")`, which
    AES-pads `b""` to one non-empty 16-byte block — so the column is truthy even
    though there is no real token. Such accounts then sail past the guard and only
    fail later inside token refresh, *silently* (Google rejects the empty grant).
    Decrypt and require non-empty plaintext; any decrypt error is treated as
    "not usable" so the account is routed to reauth instead of a silent failure.
    """
    enc = acc.get("refresh_token_encrypted")
    if not enc:
        return False
    try:
        return bool((decrypt_password(settings.SECRET_KEY, user_uuid, enc) or "").strip())
    except Exception:  # noqa: BLE001
        return False


@router.post("/sync")
def trigger_sync(user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/sync — fetch new mail for the user's accounts into the store.

    Runs inline (not background) so the store is merged by the time the client
    re-reads `/mails`. A single flaky account never turns the trigger into a 5xx —
    but, unlike before (B0001 / NR0003 H2), its failure is **no longer swallowed
    silently**. The common failure path (IMAP rejected / timeout / token refresh)
    does NOT raise: `sync_account_mails` catches it internally, records
    `sync_logs status='failed'`, and *returns* `{success: False, message}`. So we
    must inspect that return value — not just the `except` — and surface every
    failed account in the response `errors[]`. The caller can then show
    "account X didn't sync: <why>" instead of the inbox just appearing empty with
    no clue (which is exactly the multi-account "메일이 안온다" symptom).
    """
    from .sync import sync_account_mails
    accounts = _resolve_accounts(user_uuid)
    applied = 0
    reauth_required = False
    errors: list = []

    def _record_error(acc: dict, message) -> None:
        errors.append({
            "account_id": acc.get("account_uuid") or "",
            "email": acc.get("email") or acc.get("account_email") or "",
            "message": str(message) if message else "sync failed",
        })

    for acc in accounts:
        if not acc.get("sync_enabled", 1):
            continue
        # Gmail without a usable refresh token → reauth, surfaced (not a silent
        # token-refresh failure later). See _gmail_refresh_token_usable (H3).
        if acc.get("account_type") == "gmail" and not _gmail_refresh_token_usable(acc, user_uuid):
            reauth_required = True
            _record_error(acc, "re-authentication required (missing refresh token)")
            continue
        try:
            res = sync_account_mails(acc["account_uuid"], user_uuid, "INBOX") or {}
            applied += int(res.get("new_mails", 0) or 0)
            # H2: the common failure path returns success:False rather than raising.
            if res.get("success") is False:
                _record_error(acc, res.get("message"))
        except Exception as exc:  # noqa: BLE001 — 2nd-stage backstop for leaks outside sync's try
            logger.error(f"[compat sync] account {acc.get('account_uuid')}: {exc}")
            _record_error(acc, exc)
    return _ok({
        "state": "idle",
        "applied": applied,
        "reauth_required": reauth_required,
        "errors": errors,
    })


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

    # B0001 (0028): the Drafts label is backed by the dialect-free on-disk JSON
    # draft store (save_draft writes ONLY there — see _drafts_dir), never
    # `mail_messages`. The integrated-mail SQL below can therefore never surface a
    # saved draft, so the Drafts box stayed empty and a draft could not be reopened.
    # Serve the label straight from that store instead.
    if label and label.strip().lower() in ("draft", "drafts"):
        return _list_drafts_summaries(user_uuid, offset, lim)

    mail1 = sqloader.load_sql(MAIL_JSON, "inbox.get_integrated_mail1")
    mail2 = sqloader.load_sql(MAIL_JSON, "inbox.get_integrated_mail2")
    # mail1 ends on "AND a.status = 'active'"; it is designed to take further AND
    # clauses before mail2 (ORDER BY ... LIMIT ? OFFSET ?). Any bind params injected
    # here land *between* the leading user_uuid (mail1) and the trailing
    # limit/offset (mail2), so we extend the params tuple in that same order.
    params: list = [user_uuid]
    extra = " AND m.is_deleted = 0 "
    if unread:
        extra += " AND m.is_read = 0 "  # integer literal — no bind param

    # B0001 / 0026: lower the free-text search into the SQL WHERE so it filters the
    # *whole* archive (every account, every page), not just the current page a
    # post-pagination Python filter could see (the §4.1 "current-page-only" defect).
    # We match the same fields the old in-memory filter did, case-folded.
    if q and q.strip():
        ph = "?" if settings.DB_TYPE in (DBType.SQLITE, DBType.SQLITE3) else "%s"
        # LIKE wildcard-escape the needle so a user typing % or _ searches literally.
        needle = (
            q.strip().lower()
            .replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        )
        pattern = f"%{needle}%"
        # SQLite has no default LIKE escape char; MySQL/Postgres default to backslash.
        esc = " ESCAPE '\\'" if ph == "?" else ""
        extra += (
            f" AND (LOWER(m.subject) LIKE {ph}{esc}"
            f" OR LOWER(m.from_email) LIKE {ph}{esc}"
            f" OR LOWER(m.from_name) LIKE {ph}{esc}"
            f" OR LOWER(m.preview) LIKE {ph}{esc}) "
        )
        params.extend([pattern, pattern, pattern, pattern])

    # B0001 / 0038: scope the list to the requested label *in SQL*, by the canonical
    # folder_type. This makes the Sent tab (label 'sent') surface sent folders no
    # matter their localized folder_name ("보낸편지함"/"[Gmail]/Sent Mail"), and — now
    # that sent copies are persisted — keeps them from leaking into the Inbox tab.
    # Filtering before pagination also avoids the current-page-only defect that the
    # old post-fetch Python filter had. (Drafts are served from the JSON store above.)
    lab = (label or "").strip().lower()
    if lab and lab != "all":
        ph = "?" if settings.DB_TYPE in (DBType.SQLITE, DBType.SQLITE3) else "%s"
        if lab == "inbox":
            # Inbox = inbox-type mail (plus folder-less orphans); never sent/trash/spam.
            extra += " AND (f.folder_type = 'inbox' OR f.folder_type IS NULL) "
        elif lab in _SYSTEM_FOLDER_TYPES:
            extra += f" AND f.folder_type = {ph} "
            params.append(lab)
        else:
            # Custom folder label — match the display name (legacy behavior).
            extra += f" AND LOWER(f.folder_name) = {ph} "
            params.append(lab)

    sql = mail1 + extra + mail2
    params.extend([lim + 1, offset])
    # fetch one extra row to compute has_more without a second COUNT query
    rows = db_instance.fetch_all(sql, tuple(params)) or []
    has_more = len(rows) > lim
    rows = rows[:lim]

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

    # Past the SSRF/signature gates, an un-fetchable or non-image upstream is a
    # *normal* condition for mail (open-tracking beacons, dead CDNs, senders whose
    # TLS chain certifi can't complete e.g. email.kbcard.com). Rather than a hard
    # 502/415 — which the Flutter-Web client surfaces as a broken-image glyph plus a
    # console error (B0001 / 0015.0003-NR defect B) — serve a transparent 1×1 pixel
    # so the un-loadable image simply renders as nothing. Security gates above stay
    # hard errors; only post-fetch outcomes are tolerant. follow_redirects stays
    # False so a redirect can't slip past _is_safe_public_host (SSRF).
    def _blank() -> Response:
        return Response(content=_BLANK_PIXEL_PNG, media_type="image/png",
                        headers={"Cache-Control": "private, max-age=3600"})

    try:
        async with httpx.AsyncClient(timeout=_IMG_PROXY_TIMEOUT,
                                     follow_redirects=False) as client:
            resp = await client.get(url, headers={
                "User-Agent": "FileForge-ImageProxy/1.0",
                "Accept": "image/*",
            })
    except Exception as exc:  # noqa: BLE001 — unreachable host / TLS chain / timeout
        logger.info(f"[image-proxy] fetch failed {parsed.hostname}: {exc}")
        return _blank()

    ctype = (resp.headers.get("content-type") or "").split(";")[0].strip().lower()
    content = resp.content
    if (resp.status_code != 200 or not ctype.startswith("image/")
            or len(content) > _IMG_PROXY_MAX_BYTES):
        logger.info(f"[image-proxy] unservable {parsed.hostname} "
                    f"status={resp.status_code} ctype={ctype!r} bytes={len(content)}")
        return _blank()

    # CORS headers are added by the app's CORSMiddleware (echoes the app origin),
    # which is exactly what lets CanvasKit read these bytes cross-origin.
    return Response(content=content, media_type=ctype,
                    headers={"Cache-Control": "private, max-age=3600"})


@router.patch("/mails/{mail_id}")
async def set_mail_flags(mail_id: str, payload: dict = Body(default={}),
                         user_uuid: str = Depends(current_user_uuid)):
    """PATCH /mail/mails/{id} {is_read?, is_pinned?} — read/unread & pin state.

    Each flag is applied only when present in the payload, so a pin toggle never
    clobbers the read state (and vice-versa). The pin UPDATE is scoped to the
    caller's own mailboxes (ownership subquery on mail_accounts.user_uuid) — unlike
    the legacy /mail/actions/pin route (R0001 / 0027.0003-NR defect A: IDOR), a user
    can only pin/unpin messages that belong to one of their own accounts.
    """
    result = {"mail_id": mail_id}
    if "is_read" in payload:
        is_read = 1 if payload.get("is_read") else 0
        sql = sqloader.load_sql(MAIL_JSON, "update_message_read")
        # R0001 (0030): scope the read UPDATE to the caller's own mailboxes, same
        # ownership subquery the pin UPDATE already used (mail_accounts.user_uuid).
        # The legacy single-arg form (message_uuid only) let any authenticated user
        # flip the read flag of an arbitrary message (IDOR) — closed here.
        db_instance.execute_query(sql, (is_read, mail_id, user_uuid))
        result["is_read"] = bool(is_read)
    if "is_pinned" in payload:
        is_pinned = 1 if payload.get("is_pinned") else 0
        sql = sqloader.load_sql(MAIL_JSON, "update_message_pinned")
        db_instance.execute_query(sql, (is_pinned, mail_id, user_uuid))
        result["is_pinned"] = bool(is_pinned)
    return _ok(result)


@router.post("/mails/mark-all-read")
async def mark_all_read(user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/mails/mark-all-read — mark every unread mail in the caller's
    mailboxes as read (R0001 / 0030: "메일 전체 읽음처리").

    Scoped to the authenticated user's own accounts via the same ownership
    subquery the per-mail flag UPDATEs use, so it never touches another user's
    mail. A COUNT precedes the UPDATE so the response can report how many rows
    were flipped — `execute_query` returns lastrowid (not rowcount) on SQLite, so
    counting separately is the portable way to get an exact number across dialects.
    The UPDATE only touches `is_read = 0` rows, so re-invoking on an already-read
    box is a no-op (updated = 0).
    """
    cnt_sql = sqloader.load_sql(MAIL_JSON, "count_unread_for_user")
    row = db_instance.fetch_one(cnt_sql, (user_uuid,))
    updated = int((row or {}).get("cnt") or 0) if isinstance(row, dict) else 0
    if updated:
        upd_sql = sqloader.load_sql(MAIL_JSON, "mark_all_read_for_user")
        db_instance.execute_query(upd_sql, (user_uuid,))
    return _ok({"updated": updated})


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


def _compose_attachment_dir(user_uuid: str) -> str:
    return os.path.join(mail_storage_base(user_uuid=user_uuid),
                        "_compose_attachments", user_uuid)


def _safe_attachment_id(value) -> Optional[str]:
    if not value:
        return None
    safe = os.path.basename(str(value))
    return safe if safe == str(value) else None


def _attachment_ids_from_payload(payload: dict) -> list:
    ids = list(payload.get("attachment_ids") or [])
    for item in (payload.get("attachments") or []):
        if isinstance(item, dict) and item.get("attachment_id"):
            ids.append(item["attachment_id"])
    seen = set()
    out = []
    for raw in ids:
        value = str(raw or "")
        if value and value not in seen:
            seen.add(value)
            out.append(value)
    return out


def _read_staged_attachment_meta(user_uuid: str, attachment_id: str) -> dict:
    path = os.path.join(_compose_attachment_dir(user_uuid), attachment_id)
    meta = {
        "attachment_id": attachment_id,
        "filename": "attachment",
        "content_type": "application/octet-stream",
        "size_bytes": os.path.getsize(path) if os.path.exists(path) else 0,
    }
    meta_path = f"{path}.json"
    try:
        with open(meta_path, "r", encoding="utf-8") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            meta.update({
                "filename": loaded.get("filename") or meta["filename"],
                "content_type": loaded.get("content_type") or meta["content_type"],
                "size_bytes": int(loaded.get("size_bytes") or meta["size_bytes"]),
            })
    except (OSError, ValueError, TypeError):
        pass
    return meta


def _load_staged_attachments(
    user_uuid: str,
    attachment_ids: list,
) -> Tuple[Optional[list], Optional[JSONResponse]]:
    attachments = []
    base_dir = _compose_attachment_dir(user_uuid)
    for attachment_id in attachment_ids:
        safe = _safe_attachment_id(attachment_id)
        if not safe:
            return None, _err("VALIDATION_FAILED", "invalid attachment id", 400,
                              {"field": "attachment_ids"})
        path = os.path.join(base_dir, safe)
        if not os.path.exists(path):
            return None, _err("VALIDATION_FAILED", "attachment not found", 400,
                              {"field": "attachment_ids", "attachment_id": safe})
        meta = _read_staged_attachment_meta(user_uuid, safe)
        try:
            with open(path, "rb") as fh:
                content = fh.read()
        except OSError as exc:
            logger.error(f"[compat attachment] read failed {safe}: {exc}")
            return None, _err("UPSTREAM_UNAVAILABLE", "attachment read failed", 503,
                              {"attachment_id": safe})
        meta.update({
            "attachment_id": safe,
            "content": content,
            "filepath": path,
            "size_bytes": len(content),
        })
        attachments.append(meta)
    return attachments, None


def _attachment_public_records(user_uuid: str, attachment_ids: list) -> list:
    records = []
    for attachment_id in attachment_ids:
        safe = _safe_attachment_id(attachment_id)
        if not safe:
            continue
        path = os.path.join(_compose_attachment_dir(user_uuid), safe)
        if not os.path.exists(path):
            continue
        meta = _read_staged_attachment_meta(user_uuid, safe)
        records.append({
            "attachment_id": safe,
            "filename": meta.get("filename") or "",
            "size_bytes": int(meta.get("size_bytes") or 0),
            "content_type": meta.get("content_type") or "application/octet-stream",
        })
    return records


def _attach_mime_files(msg, attachments: list) -> None:
    from email import encoders
    from email.mime.base import MIMEBase

    for attachment in attachments or []:
        content = attachment.get("content") or b""
        if not content:
            continue
        content_type = attachment.get("content_type") or "application/octet-stream"
        maintype, subtype = (
            content_type.split("/", 1)
            if "/" in content_type else ("application", "octet-stream")
        )
        part = MIMEBase(maintype, subtype)
        part.set_payload(content)
        encoders.encode_base64(part)
        part.add_header(
            "Content-Disposition",
            "attachment",
            filename=("utf-8", "", attachment.get("filename") or "attachment"),
        )
        msg.attach(part)


def _persist_sent_message(user_uuid: str, account: dict, *, to_list, cc_list,
                          bcc_list, subject, body_text, body_html,
                          attachments: Optional[list] = None) -> str:
    """Store a copy of a just-sent message in the account's Sent folder (B0001 / 0038).

    The previous compat send transmitted over SMTP/Gmail and returned a throwaway
    uuid without writing anything to `mail_messages`, so the Sent tab — which reads
    that table — was permanently empty. This mirrors the legacy
    routers/mail/mail.py::send_mail save path (sent folder lookup/create + .eml +
    row) but with dialect-portable sqloader SQL.

    Best-effort by design: any storage failure is logged and swallowed so a hiccup
    never turns an already-delivered message into an error. Returns the message_uuid
    the row was (attempted to be) written under.
    """
    import time

    message_uuid = str(uuid_lib.uuid4())
    account_uuid = account.get("account_uuid")
    try:
        # 1) Resolve (or lazily create) the Sent folder by canonical folder_type.
        folder_uuid = None
        try:
            row = db_instance.fetch_one(
                sqloader.load_sql(MAIL_JSON, "inbox.get_sent_folder"), (account_uuid,))
            if row:
                folder_uuid = row.get("folder_uuid")
        except Exception as exc:  # noqa: BLE001
            logger.debug(f"[compat send/store] sent-folder lookup: {exc}")
        if not folder_uuid:
            folder_uuid = str(uuid_lib.uuid4())
            db_instance.execute_query(
                sqloader.load_sql(MAIL_JSON, "inbox.create_sent_folder"),
                (folder_uuid, account_uuid, "Sent", "[Gmail]/Sent Mail"))

        # 2) Build the RFC822 message. uid is negative so it never collides with a
        #    positive IMAP UID a future Sent-folder sync might assign.
        from email.mime.multipart import MIMEMultipart
        from email.mime.text import MIMEText

        timestamp = int(time.time() * 1000000)  # microseconds
        email_addr = account.get("email") or ""
        domain = email_addr.split("@")[-1] if "@" in email_addr else "localhost"
        message_id = f"<{message_uuid}.{timestamp}@{domain}>"
        uid = -timestamp

        if attachments:
            msg = MIMEMultipart("mixed")
            body_part = MIMEMultipart("alternative")
        else:
            msg = MIMEMultipart("alternative")
            body_part = msg
        msg["From"] = f"{account.get('account_name', email_addr)} <{email_addr}>"
        msg["To"] = ", ".join(to_list)
        if cc_list:
            msg["Cc"] = ", ".join(cc_list)
        msg["Subject"] = subject
        if body_text:
            body_part.attach(MIMEText(body_text, "plain", "utf-8"))
        if body_html:
            body_part.attach(MIMEText(body_html, "html", "utf-8"))
        if attachments:
            msg.attach(body_part)
            _attach_mime_files(msg, attachments)
        eml_str = msg.as_string()
        size_bytes = len(eml_str.encode("utf-8"))

        # 3) Persist the .eml beside received mail (best-effort — the DB row is what
        #    the list actually reads; a write failure must not lose the Sent entry).
        body_file_path = None
        try:
            eml_dir = os.path.join(
                mail_storage_base(account_uuid=account_uuid), account_uuid, "messages")
            os.makedirs(eml_dir, exist_ok=True)
            path = os.path.join(eml_dir, f"{message_uuid}.eml")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(eml_str)
            body_file_path = path
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[compat send/store] eml write failed: {exc}")

        # 4) Insert the Sent row (is_read=1 — the user authored it; naive-UTC per 0025).
        sent_at = now_utc_naive()
        db_instance.execute_query(
            sqloader.load_sql(MAIL_JSON, "inbox.insert_sent_message"),
            (
                message_uuid, account_uuid, folder_uuid, message_id, uid,
                email_addr, account.get("account_name", "") or "",
                ", ".join(to_list), ", ".join(cc_list or []), ", ".join(bcc_list or []),
                subject, make_preview(body_text, body_html, 200), sent_at, sent_at,
                1, 0, 0, 1 if attachments else 0, body_file_path, size_bytes,
            ))
        if attachments:
            _persist_sent_attachments(message_uuid, account_uuid, attachments)
        logger.info(f"[compat send/store] sent copy stored: {message_uuid}")
    except Exception as exc:  # noqa: BLE001 — never fail an already-sent message
        logger.error(f"[compat send/store] failed to store sent copy: {exc}")
    return message_uuid


def _persist_sent_attachments(message_uuid: str, account_uuid: str, attachments: list) -> None:
    base_dir = os.path.join(mail_storage_base(account_uuid=account_uuid),
                            account_uuid, "attachments")
    for attachment in attachments or []:
        attachment_uuid = str(uuid_lib.uuid4())
        filename = os.path.basename(attachment.get("filename") or "attachment")
        content = attachment.get("content") or b""
        subdir = attachment_uuid[:2]
        file_dir = os.path.join(base_dir, subdir)
        try:
            os.makedirs(file_dir, exist_ok=True)
            file_path = os.path.join(file_dir, f"{attachment_uuid}_{filename}")
            with open(file_path, "wb") as fh:
                fh.write(content)
            db_instance.execute_query(
                adapt_query(
                    "INSERT INTO mail_attachments "
                    "(attachment_uuid, message_uuid, filename, content_type, "
                    "size_bytes, file_path, is_inline, content_id) "
                    "VALUES (?, ?, ?, ?, ?, ?, 0, NULL)"
                ),
                (
                    attachment_uuid, message_uuid, filename,
                    attachment.get("content_type") or "application/octet-stream",
                    len(content), file_path,
                ),
            )
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[compat send/store] attachment persist failed: {exc}")


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
    attachment_ids = _attachment_ids_from_payload(payload)
    attachments, attachment_error = _load_staged_attachments(user_uuid, attachment_ids)
    if attachment_error is not None:
        return attachment_error

    accounts = _resolve_accounts(user_uuid)
    if not accounts:
        return _err("VALIDATION_FAILED", "no connected account to send from", 400)

    # R0001 (0035) — sender selection. With multiple linked accounts the client may
    # name which one to send from via `from_account_id` (P0007 SendPayload). When
    # provided it MUST match one of *this user's* active accounts (ownership is
    # already scoped by user_uuid in _resolve_accounts) — an unknown id is a
    # validation error rather than a silent fallback that would leak the wrong From.
    # When omitted, the default is the first account, now deterministic thanks to the
    # `display_order, created_at, account_uuid` tiebreaker in get_user_accounts.
    requested = (payload.get("from_account_id") or payload.get("account_id") or "").strip()
    if requested:
        account = next(
            (a for a in accounts if str(a.get("account_uuid") or "") == requested), None)
        if account is None:
            return _err("VALIDATION_FAILED", "from_account_id is not a connected account",
                        400, {"field": "from_account_id"})
    else:
        account = accounts[0]

    try:
        if account.get("account_type") == "gmail":
            # Gmail (OAuth/XOAUTH2) send — reuses the same OAuth send primitives as
            # routers/mail/mail.py::send_mail (refresh token → access token → XOAUTH2
            # SMTP). A missing refresh token is the only genuinely retriable/reauth
            # case; everything else attempts a real send instead of a blanket 503.
            if not account.get("refresh_token_encrypted"):
                return _err("REAUTH_REQUIRED",
                            "gmail account requires re-authentication (no refresh token)",
                            401, {"reason": "oauth reauth"})
            from services.gmail_service import GmailOAuthService, GmailSMTPService
            from email.mime.multipart import MIMEMultipart
            from email.mime.text import MIMEText

            refresh_token = decrypt_password(
                settings.SECRET_KEY, user_uuid, account["refresh_token_encrypted"])
            gmail_oauth = GmailOAuthService()
            # Sync endpoint runs in a threadpool, so a private event loop is safe here.
            token_data = asyncio.run(gmail_oauth.refresh_access_token(refresh_token))
            access_token = token_data["access_token"]

            smtp = GmailSMTPService(account["email"], access_token)
            connect_result = smtp.connect()
            if not connect_result.get("success"):
                return _err("SEND_FAILED",
                            connect_result.get("message", "gmail smtp connect failed"), 502)
            try:
                msg = MIMEMultipart("mixed")
                msg["From"] = f"{account.get('account_name', account['email'])} <{account['email']}>"
                msg["To"] = ", ".join(to_list)
                if cc_list:
                    msg["Cc"] = ", ".join(cc_list)
                msg["Subject"] = subject
                if body_html:
                    msg.attach(MIMEText(body_html, "html", "utf-8"))
                elif body_text:
                    msg.attach(MIMEText(body_text, "plain", "utf-8"))
                _attach_mime_files(msg, attachments or [])
                all_recipients = to_list + (cc_list or []) + (bcc_list or [])
                smtp.connection.sendmail(account["email"], all_recipients, msg.as_string())
            finally:
                smtp.disconnect()
            mid = _persist_sent_message(
                user_uuid, account, to_list=to_list, cc_list=cc_list, bcc_list=bcc_list,
                subject=subject, body_text=body_text, body_html=body_html,
                attachments=attachments)
            return _ok({"mail_id": mid, "status": "sent"})
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
                attachments=attachments or None,
            )
        finally:
            smtp.disconnect()
        if not send_result.get("success"):
            return _err("SEND_FAILED", send_result.get("message", "send failed"), 502)
    except Exception as exc:  # noqa: BLE001
        logger.error(f"[compat send] {exc}")
        return _err("SEND_FAILED", str(exc), 502)

    mid = _persist_sent_message(
        user_uuid, account, to_list=to_list, cc_list=cc_list, bcc_list=bcc_list,
        subject=subject, body_text=body_text, body_html=body_html,
        attachments=attachments)
    return _ok({"mail_id": mid, "status": "sent"})


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
    base = mail_storage_base(user_uuid=user_uuid)
    return os.path.join(base, "_drafts", user_uuid)


def _draft_path(user_uuid: str, draft_id: str) -> str:
    # draft_id is a server-minted uuid; guard against path traversal regardless.
    safe = os.path.basename(draft_id)
    return os.path.join(_drafts_dir(user_uuid), f"{safe}.json")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _draft_from_payload(payload: dict, draft_id: str, updated_at: str,
                        user_uuid: Optional[str] = None) -> dict:
    body = payload.get("body") or {}
    attachments = payload.get("attachments") or []
    if not attachments and user_uuid:
        attachments = _attachment_public_records(
            user_uuid, _attachment_ids_from_payload(payload))
    return {
        "draft_id": draft_id,
        "to": payload.get("to") or [],
        "cc": payload.get("cc") or [],
        "bcc": payload.get("bcc") or [],
        "subject": payload.get("subject") or "",
        "body": {"format": body.get("format", "text"), "content": body.get("content", "")},
        "attachments": attachments,
        "updated_at": updated_at,
    }


def _draft_to_summary(record: dict) -> dict:
    """A JSON-store draft record → P0007 §3.1 MailSummary (mail.dart).

    B0001 (0028): drafts live in the dialect-free on-disk JSON store, NOT in
    `mail_messages`, so the integrated-mail SQL behind the inbox/sent labels can
    never see them. The Drafts label is served straight from that store
    (list_mails early-branches into _list_drafts_summaries), and each record is
    shaped into the same MailSummary the list renders for any other mailbox.
    Conventionally a draft shows its *recipients* (where it is headed) rather than
    a sender, so the recipient line is surfaced in the `from` slot the list tile
    already renders. mail_id == draft_id so a tap re-opens it via GET /drafts/{id}.
    """
    def _addr(a) -> str:
        if isinstance(a, dict):
            return (a.get("address") or "").strip()
        return str(a or "").strip()

    recipients = [x for x in (_addr(a) for a in (record.get("to") or [])) if x]
    body = record.get("body") or {}
    content = body.get("content") or ""
    snippet = strip_html_to_text(content) if ("<" in content) else content
    snippet = (snippet or "").strip()[:200]
    return {
        "mail_id": record.get("draft_id", "") or "",
        "thread_id": "",
        "from": {
            "name": ", ".join(recipients),
            "address": recipients[0] if recipients else "",
        },
        "subject": record.get("subject") or "",
        "snippet": snippet,
        # updated_at is already an ISO-8601 string with an explicit UTC offset
        # (_now_iso → datetime.now(timezone.utc).isoformat()), which the client's
        # DateTime.parse(...).toLocal() renders in the viewer's zone.
        "received_at": record.get("updated_at") or "",
        "is_read": True,
        "is_pinned": False,
        "is_starred": False,
        "has_attachment": bool(record.get("attachments")),
        "labels": ["drafts"],
        "account": {"account_id": "", "email": "", "name": "", "color": ""},
    }


def _list_drafts_summaries(user_uuid: str, offset: int, lim: int):
    """Serve the Drafts label from the on-disk JSON store (B0001 / 0028).

    Drafts are persisted by save_draft/update_draft to `_drafts/{user_uuid}/*.json`
    and are absent from `mail_messages`; the inbox/sent SQL behind list_mails can
    never surface them. Read the store directly, newest-edit-first, with the same
    offset/limit paging contract the SQL path uses (has_more when more remain).
    Corrupt/unreadable records are skipped (logged) rather than failing the page.
    """
    directory = _drafts_dir(user_uuid)
    try:
        names = os.listdir(directory)
    except FileNotFoundError:
        names = []
    except OSError as exc:
        logger.error(f"[compat draft list] {exc}")
        names = []

    records = []
    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(directory, name), "r", encoding="utf-8") as fh:
                rec = json.load(fh)
        except (OSError, ValueError) as exc:
            logger.error(f"[compat draft list] skip {name}: {exc}")
            continue
        if isinstance(rec, dict):
            records.append(rec)

    # newest edit first — updated_at is an ISO-8601 string, lexically sortable.
    records.sort(key=lambda r: r.get("updated_at") or "", reverse=True)
    total = len(records)
    window = records[offset: offset + lim]
    has_more = total > offset + lim
    items = [_draft_to_summary(r) for r in window]
    meta = {
        "next_cursor": str(offset + lim) if has_more else None,
        "has_more": has_more,
        "count": len(items),
    }
    return _ok(items, meta)


@router.post("/drafts")
async def save_draft(payload: dict = Body(default={}), user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/drafts — create a draft, return its id + updated_at."""
    draft_id = str(uuid_lib.uuid4())
    updated_at = _now_iso()
    record = _draft_from_payload(payload, draft_id, updated_at, user_uuid)
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
    record = _draft_from_payload(payload, draft_id, updated_at, user_uuid)
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
    # 204 must be body-less (see delete_account / B0001).
    return Response(status_code=204)


@router.post("/attachments")
async def upload_attachment(file: UploadFile = File(...),
                            user_uuid: str = Depends(current_user_uuid)):
    """POST /mail/attachments — stage a compose attachment, return its handle."""
    attachment_id = str(uuid_lib.uuid4())
    content = await file.read()
    base = mail_storage_base(user_uuid=user_uuid)
    dest_dir = os.path.join(base, "_compose_attachments", user_uuid)
    meta = {
        "attachment_id": attachment_id,
        "filename": file.filename or "",
        "size_bytes": len(content),
        "content_type": file.content_type or "application/octet-stream",
    }
    try:
        os.makedirs(dest_dir, exist_ok=True)
        with open(os.path.join(dest_dir, attachment_id), "wb") as fh:
            fh.write(content)
        with open(os.path.join(dest_dir, f"{attachment_id}.json"), "w", encoding="utf-8") as fh:
            json.dump(meta, fh, ensure_ascii=False)
    except OSError as exc:
        logger.error(f"[compat attachment] store failed: {exc}")
        return _err("UPSTREAM_UNAVAILABLE", "attachment store failed", 503)
    return _ok(meta)
