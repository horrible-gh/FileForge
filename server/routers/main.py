from fastapi import FastAPI, Depends, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from .login import login, logout, sessions
from .storages import storages, bulk
from . import shared_link, public_share, totp
from .mail import accounts as mail_accounts, mail as mail_core, sync as mail_sync, inbox as mail_inbox, files as mail_files, actions as mail_actions, drafts as mail_drafts, labels as mail_labels
from .mail import compat as mail_compat
from .mail.oauth import gmail_auth
from .bolt import bolt as bolt_vault
from config import settings
import LogAssist.log as Logger
import sys
import io
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from util.ratelimit_asgi import StreamSafeSlowAPIASGIMiddleware
from security.access import authorize_storage_request
from security.abuse import limit_public_share
from security.http import SecurityHeadersMiddleware

# Preserve streaming responses: do not use BaseHTTPMiddleware here.
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')
Logger.logger_init()

ALLOWED_ORIGIN = [origin.strip() for origin in settings.ALLOWED_ORIGIN.split(",") if origin.strip()]
CONTEXT = settings.CONTEXT
limiter = Limiter(key_func=get_remote_address, default_limits=[settings.RATE_LIMIT_DEFAULT])
# Public production API does not expose interactive docs or debugging routes.
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(StreamSafeSlowAPIASGIMiddleware)

app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(sessions.router, prefix=f"{CONTEXT}/auth/sessions", tags=["Sessions"])
# These dependencies preflight every object before legacy handlers can run.
app.include_router(storages.router, prefix=f"{CONTEXT}/storages", tags=["Storages"],
                   dependencies=[Depends(authorize_storage_request)])
app.include_router(bulk.router, prefix=f"{CONTEXT}/storages/bulk", tags=["Bulk"],
                   dependencies=[Depends(authorize_storage_request)])
app.include_router(shared_link.router, prefix=f"{CONTEXT}/share", tags=["Share"])
app.include_router(public_share.router, prefix=f"{CONTEXT}/share", tags=["Share Public"],
                   dependencies=[Depends(limit_public_share)])
app.include_router(totp.router, prefix=f"{CONTEXT}/auth/totp", tags=["TOTP"])

# Keep the flat-contract compatibility routes first (existing client API).
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
app.include_router(bolt_vault.router, prefix=f"{CONTEXT}/bolt", tags=["SecureBolt Vault"])

app.add_middleware(CORSMiddleware, allow_origins=ALLOWED_ORIGIN,
                   allow_credentials="*" not in ALLOWED_ORIGIN,
                   allow_methods=["*"], allow_headers=["*"], expose_headers=["Content-Disposition"])
app.add_middleware(SecurityHeadersMiddleware)


@app.on_event("startup")
async def _start_idle_manager():
    try:
        from services.idle_manager import manager as idle_manager
        idle_manager.start()
    except Exception:
        Logger.error("[IDLE] startup hook failed")


@app.on_event("shutdown")
async def _stop_idle_manager():
    try:
        from services.idle_manager import manager as idle_manager
        idle_manager.stop()
    except Exception:
        Logger.error("[IDLE] shutdown hook failed")


@app.get(CONTEXT + "/")
async def read_root():
    return {"message": "Hello FastAPI"}


@app.get(CONTEXT + "/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    # Never log request bodies or echo validation 'input'/'ctx': these can
    # contain passwords, bearer/refresh tokens, OTPs and private mail text.
    errors = [{key: error[key] for key in ("loc", "msg", "type") if key in error}
              for error in exc.errors()]
    return JSONResponse(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        content=jsonable_encoder({"detail": errors}))
