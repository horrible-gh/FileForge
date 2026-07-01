from typing import Optional
from pydantic import BaseModel


class PushRequest(BaseModel):
    """Body for POST /fileforge/bolt/push (P0005 §2, L0006 §2.4).

    The absorbed FileForge contract drops the legacy SecureBolt fields
    ``group_id``/``timestamp``/``user_id`` (P0005 appendix A); identity is resolved
    from the access token, never the body. ``content`` is the client-encrypted
    opaque blob the server stores verbatim (zero-knowledge).

    ``data_type`` and ``content`` are intentionally **optional at the schema
    layer** (default ``None``) so a *missing* field is normalized by the handler
    into the legacy envelope ``400 {status:failed}`` (L0006 §4.2 acceptance
    ladder) instead of FastAPI's default ``422`` validation error. A missing
    ``data_type`` falls through "Unsupported data_type" and a missing/empty
    ``content`` through "Empty content" — keeping the P0005 error contract
    uniform whether the field is absent or blank.
    """

    data_type: Optional[str] = None
    content: Optional[str] = None
    version: Optional[str] = "3.0"
