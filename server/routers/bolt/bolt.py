"""SecureBolt vault router (fileforge.securebolt.0001 absorption).

Presents the absorbed P0005 contract on the FileForge origin
(``/fileforge/bolt/push`` + ``/fileforge/bolt/pull``) and maps it onto the
``bolt_data`` store (DB0007). The vault is **zero-knowledge**: ``content`` is a
client-encrypted opaque Base64 ``Salted__…`` blob (L0006 §1/§6) that the server
stores and returns verbatim — it is never decrypted or structurally validated.

Absorption follows the MailAnchor precedent (NR0003 §3, D0004):
  * Identity is the RS256 access token; ``current_user_uuid`` resolves the JWT
    subject (string user_id) to ``users.user_uuid`` — the FK key on ``bolt_data``
    (avoids the 1452 FK misuse of the mail subsystem, 0004 선례).
  * SecureBolt's own login/logout/register/users/groups are NOT ported; FileForge
    identity is the single source (NR0003 §3-B).
  * The legacy ``?user_id=`` query / body ``user_id``/``group_id``/``timestamp``
    fields are dropped (P0005 부록 A); identity always comes from the token.

Response envelope mirrors the legacy SecureBolt shape the client consumes
(``{status, data, message}``), NOT the P0007 mail envelope.
"""

from fastapi import APIRouter, Depends, Body
from fastapi.responses import JSONResponse

from config import db
from routers.login.auth import current_user_uuid
from schemas.bolt import PushRequest
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

BOLT_JSON = "bolt"

# Allowed vault blob kinds (L0006 §1.3 / DB0007 CHECK). Exactly two.
ALLOWED_DATA_TYPES = {"password", "category"}


def _ok(message: str = None, data=None):
    body = {"status": "success"}
    if message is not None:
        body["message"] = message
    if data is not None:
        body["data"] = data
    return body


def _failed(message: str, status_code: int = 400):
    return JSONResponse(status_code=status_code, content={"status": "failed", "message": message})


@router.post("/push")
def push_bolt(body: PushRequest, user_uuid: str = Depends(current_user_uuid)):
    """Store (upsert) a client-encrypted vault blob for the authenticated user.

    Server push acceptance ladder (L0006 §4.2):
      1) identity unresolved          → 401 (raised by current_user_uuid)
      2) data_type missing/not allowed→ 400 {status:failed, "Unsupported data_type"}
      3) content missing/empty        → 400 {status:failed, "Empty content"}
      4) else                         → upsert → 200 {status:success}

    ``data_type``/``content`` are Optional in :class:`PushRequest` so a *missing*
    field is caught here and rendered as the legacy 400 envelope, rather than
    leaking FastAPI's 422 (L0006 §4.2 / P0005 부록 A — uniform error contract for
    absent vs blank).
    """
    if body.data_type not in ALLOWED_DATA_TYPES:
        logger.warning(f"bolt.push rejected unsupported data_type={body.data_type!r}")
        return _failed("Unsupported data_type")

    if not body.content:
        return _failed("Empty content")

    sql = sqloader.load_sql(BOLT_JSON, "push")
    db_instance.execute_query(
        sql,
        (user_uuid, body.data_type, body.content, body.version or "3.0"),
    )
    return _ok("Data pushed successfully")


@router.get("/pull")
def pull_bolt(user_uuid: str = Depends(current_user_uuid)):
    """Return the authenticated user's vault blobs (≤ 2 rows: password/category).

    Identity is resolved from the token only — the legacy ``?user_id=`` query is
    not accepted (L0006 §2.8). The server returns the opaque blobs unchanged.
    """
    sql = sqloader.load_sql(BOLT_JSON, "pull")
    rows = db_instance.fetch_all(sql, (user_uuid,)) or []
    data = [
        {
            "data_type": r["data_type"],
            "encrypted_data": r["content"],
            "version": r["version"],
        }
        for r in rows
    ]
    return _ok(data=data)
