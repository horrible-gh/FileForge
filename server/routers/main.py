from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from .login import login, logout
from .storages import storages, bulk
from . import shared_link, public_share, totp
from routers.login.auth import verify_token, token_blacklist
import redis
from config import settings
import LogAssist.log as Logger
import sys
import io
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

# Windows 콘솔 인코딩 강제 UTF-8
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

Logger.logger_init()

ALLOWED_ORIGIN = settings.ALLOWED_ORIGIN.split(",")
CONTEXT = settings.CONTEXT

redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=[settings.RATE_LIMIT_DEFAULT]  # 전역 기본값
)

app = FastAPI()
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(SlowAPIMiddleware)  # 미들웨어로 자동 적용


app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(storages.router, prefix=f"{CONTEXT}/storages", tags=["Storages"])
app.include_router(bulk.router, prefix=f"{CONTEXT}/storages/bulk", tags=["Bulk"])
app.include_router(shared_link.router, prefix=f"{CONTEXT}/share", tags=["Share"])
app.include_router(public_share.router, prefix=f"{CONTEXT}/share", tags=["Share Public"])
app.include_router(totp.router, prefix=f"{CONTEXT}/auth/totp", tags=["TOTP"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGIN,  # 모든 도메인 허용 (보안 강화 필요)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"]  # 🔥 이게 핵심!
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
    Logger.debug(f"🔍 Request Headers: {request.headers}")  # ✅ 모든 헤더 출력
    return {"headers": dict(request.headers)}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    Logger.debug("💥 Validation error 발생")
    Logger.debug("⛳ 경로:", request.url)
    Logger.debug("📦 내용:\n", exc.errors())
    Logger.debug("📨 원본 body:\n", await request.body())
