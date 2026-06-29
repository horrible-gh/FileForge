from fastapi import FastAPI, Depends, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from .login import login, logout
from .storages import storages, bulk
from . import shared_link, public_share, totp
from .mail import accounts as mail_accounts, mail as mail_core, sync as mail_sync, inbox as mail_inbox, files as mail_files, actions as mail_actions, drafts as mail_drafts, labels as mail_labels
from .mail import compat as mail_compat
from .mail.oauth import gmail_auth
from .bolt import bolt as bolt_vault
from routers.login.auth import verify_token, token_blacklist
from config import settings, redis_client
import LogAssist.log as Logger
import sys
import io
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
# NOTE: use a pure-ASGI rate-limit middleware, NOT SlowAPIMiddleware.
# SlowAPIMiddleware subclasses Starlette BaseHTTPMiddleware, which on
# Starlette 0.45.x + anyio 4.13 + Python 3.14 raises `RuntimeError: No response
# returned.` whenever an inner handler propagates an exception/response through
# call_next — that 500'd every real route (GET and POST) after auth (R0001
# blocker, TSR0012).
#
# We do NOT use slowapi's own SlowAPIASGIMiddleware directly either: its
# `_ASGIMiddlewareResponder.send_wrapper` re-sends the buffered
# `http.response.start` on *every* `http.response.body` chunk, so any multi-chunk
# response (a FileResponse for a file > 64 KB chunk_size — i.e. real mail
# attachments) emits a second response.start → uvicorn `RuntimeError: Expected
# ASGI message 'http.response.body', but got 'http.response.start'` and the
# browser sees `net::ERR_CONTENT_LENGTH_MISMATCH` (200, truncated body). That
# silently broke every attachment download (0019.0005-TR). StreamSafe...
# subclasses slowapi and corrects only the response-relay loop (start emitted
# once), reusing all of slowapi's rate-limiting logic unchanged.
from util.ratelimit_asgi import StreamSafeSlowAPIASGIMiddleware

# Force Windows console encoding to UTF-8
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

Logger.logger_init()

ALLOWED_ORIGIN = settings.ALLOWED_ORIGIN.split(",")
CONTEXT = settings.CONTEXT

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[settings.RATE_LIMIT_DEFAULT]  # text default value
)

app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(StreamSafeSlowAPIASGIMiddleware)  # pure-ASGI rate-limit middleware (see import note)


app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(storages.router, prefix=f"{CONTEXT}/storages", tags=["Storages"])
app.include_router(bulk.router, prefix=f"{CONTEXT}/storages/bulk", tags=["Bulk"])
app.include_router(shared_link.router, prefix=f"{CONTEXT}/share", tags=["Share"])
app.include_router(public_share.router, prefix=f"{CONTEXT}/share", tags=["Share Public"])
app.include_router(totp.router, prefix=f"{CONTEXT}/auth/totp", tags=["TOTP"])

# 🔹 Mail subsystem (absorbed from legacy mail-server — D0004 병합안 / NR0003 Gap D).
#    Same path prefixes as legacy (/fileforge/mail/*, /fileforge/oauth/gmail) so the
#    client keeps a single :8000/fileforge origin. Every mail route gates on the
#    server's RS256 verify_token (Auth Bridge — NR0003 Gap A, L0006 §2.1).
#
# 🔸 P0007 flat-contract compat layer (0003 group / B0001). The absorbed routers
#    below expose a verbose, account_uuid-keyed surface (get_accounts, /sync/all,
#    /list/{uuid}, ...) that NO client endpoint matches → every mail call 404'd.
#    The client speaks the P0007 flat REST contract (/mails, /sync, /accounts,
#    /drafts/{id}, ...). This router presents that contract and maps it onto the
#    same store/services. Registered FIRST so its flat exact paths win on any
#    overlap with the verbose routers (paths are disjoint today; this is defensive).
app.include_router(mail_compat.router, prefix=f"{CONTEXT}/mail", tags=["Mail (P0007)"])
app.include_router(mail_accounts.router, prefix=f"{CONTEXT}/mail/accounts", tags=["Mail Accounts"])
app.include_router(mail_core.router, prefix=f"{CONTEXT}/mail", tags=["Mail"])
app.include_router(mail_sync.router, prefix=f"{CONTEXT}/mail/sync", tags=["Mail Sync"])
app.include_router(mail_inbox.router, prefix=f"{CONTEXT}/mail/inbox", tags=["Mail Inbox"])
app.include_router(mail_files.router, prefix=f"{CONTEXT}/mail/files", tags=["Mail Files"])
app.include_router(mail_actions.router, prefix=f"{CONTEXT}/mail/actions", tags=["Mail Actions"])
app.include_router(mail_drafts.router, prefix=f"{CONTEXT}/mail/drafts", tags=["Mail Drafts"])
app.include_router(mail_labels.router, prefix=f"{CONTEXT}/mail/labels", tags=["Mail Labels"])
app.include_router(gmail_auth.router, prefix=f"{CONTEXT}/oauth/gmail", tags=["Gmail OAuth"])

# 🔹 SecureBolt vault subsystem (absorbed — fileforge.securebolt.0001, T0008).
#    Same :8000/fileforge origin as the rest of the platform. Zero-knowledge:
#    /bolt/push stores and /bolt/pull returns client-encrypted opaque blobs
#    keyed on users.user_uuid (current_user_uuid gate). DB0007 bolt_data table.
app.include_router(bolt_vault.router, prefix=f"{CONTEXT}/bolt", tags=["SecureBolt Vault"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGIN,  # all translated text allowed (security text text)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"]  # 🔥 text core!
)

@app.get(CONTEXT + "/")
async def read_root():
    return {"message": "Hello FastAPI"}

@app.get(CONTEXT + "/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}

@app.get(CONTEXT + "/items/{item_id}")
async def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "query": q}


@app.get(CONTEXT + "/debug-headers")
async def debug_headers(request: Request):
    Logger.debug(f"🔍 Request Headers: {request.headers}")  # ✅ all text text
    return {"headers": dict(request.headers)}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    Logger.debug("💥 Validation error text")
    Logger.debug("⛳ path:", request.url)
    Logger.debug("📦 content:\n", exc.errors())
    Logger.debug("📨 text body:\n", await request.body())
    # MUST return a response. Without this the handler returned None, which makes the
    # ASGI app finish without starting a response → uvicorn 500 ("ASGI callable returned
    # without starting response"). That turned every 422 into a 500; it was masked until
    # the SlowAPIMiddleware->ASGI fix above stopped 500-ing the whole surface first.
    # Mirror FastAPI's default RequestValidationError contract: 422 + {"detail": errors}.
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=jsonable_encoder({"detail": exc.errors()}),
    )
