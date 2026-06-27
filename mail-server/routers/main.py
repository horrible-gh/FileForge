from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from .login import login, logout, totp
from .mail import accounts, mail, sync, inbox, files, actions, drafts, labels
from .mail.oauth import gmail_auth
from config import settings
from util import jsonutil as json
import LogAssist.log as logger
import sys
import io

# Windows 콘솔 인코딩 강제 UTF-8
if sys.platform == 'win32':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')

#logger.logger_init()

ALLOWED_ORIGIN = settings.ALLOWED_ORIGIN.split(",")
CONTEXT = settings.CONTEXT

logger_config = json.json_read("logger.json")
logger.logger_init(logger_config)

app = FastAPI()
app.include_router(login.router, prefix=f"{CONTEXT}/login", tags=["Login"])
app.include_router(logout.router, prefix=f"{CONTEXT}/logout", tags=["Logout"])
app.include_router(totp.router, prefix=f"{CONTEXT}", tags=["2FA"])
app.include_router(accounts.router, prefix=f"{CONTEXT}/mail/accounts", tags=["Mail Accounts"])
app.include_router(mail.router, prefix=f"{CONTEXT}/mail", tags=["Mail"])
app.include_router(sync.router, prefix=f"{CONTEXT}/mail/sync", tags=["Sync"])
app.include_router(inbox.router, prefix=f"{CONTEXT}/mail/inbox", tags=["Inbox"])
app.include_router(files.router, prefix=f"{CONTEXT}/mail/files", tags=["Files"])
app.include_router(actions.router, prefix=f"{CONTEXT}/mail/actions", tags=["Actions"])
app.include_router(drafts.router, prefix=f"{CONTEXT}/mail/drafts", tags=["drafts"])
app.include_router(labels.router, prefix=f"{CONTEXT}/mail/labels", tags=["labels"])
app.include_router(gmail_auth.router, prefix=f"{CONTEXT}/oauth/gmail", tags=["Gmail OAuth"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGIN,  # 모든 도메인 허용 (보안 강화 필요)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["Content-Disposition"]  # 🔥 이게 핵심!
)

for route in app.routes:
    logger.debug(route.path, route.methods if hasattr(route, 'methods') else '')

@app.get(CONTEXT + "/")
async def read_root():
    return {"message": "Hello FastAPI"}

@app.get(CONTEXT + "/items/{item_id}")
async def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "query": q}


@app.get(CONTEXT + "/debug-headers")
async def debug_headers(request: Request):
    logger.debug(f"🔍 Request Headers: {request.headers}")  # ✅ 모든 헤더 출력
    return {"headers": dict(request.headers)}


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.debug("💥 Validation error 발생")
    logger.debug("⛳ 경로:", request.url)
    logger.debug("📦 내용:\n", exc.errors())
    logger.debug("📨 원본 body:\n", await request.body())
