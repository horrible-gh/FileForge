from typing import Optional
from pydantic import BaseModel


class PushRequest(BaseModel):
    """Body for POST /fileforge/bolt/push (P0005 §2, L0006 §2.4).

    The absorbed FileForge contract drops the legacy SecureBolt fields
    ``group_id``/``timestamp``/``user_id`` (P0005 부록 A); identity is resolved
    from the access token, never the body. ``content`` is the client-encrypted
    opaque blob the server stores verbatim (zero-knowledge).
    """

    data_type: str
    content: str
    version: Optional[str] = "3.0"
