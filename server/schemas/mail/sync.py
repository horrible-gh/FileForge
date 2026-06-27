from typing import List, Optional
from pydantic import BaseModel

class SyncRequest(BaseModel):
    user_uuid: str

