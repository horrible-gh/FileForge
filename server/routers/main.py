from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from .login import login, logout
from .storages import storages, bulk
from . import shared_link, public_share, totp
from routers.login.auth import verify_token, token_blacklist
from config import settings, redis_client
import LogAssist.log as Logger
import sys
import io
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

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
app.add_middleware(SlowAPIMiddleware)  # translated text text text


app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(storages.router, prefix=f"{CONTEXT}/storages", tags=["Storages"])
app.include_router(bulk.router, prefix=f"{CONTEXT}/storages/bulk", tags=["Bulk"])
app.include_router(shared_link.router, prefix=f"{CONTEXT}/share", tags=["Share"])
app.include_router(public_share.router, prefix=f"{CONTEXT}/share", tags=["Share Public"])
app.include_router(totp.router, prefix=f"{CONTEXT}/auth/totp", tags=["TOTP"])

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
