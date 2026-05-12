# schemas/storages.py
from typing import List
from pydantic import BaseModel

class UserStoragesRequest(BaseModel):
    node_uuids: List[str] | None = None
    group_uuid: str | None = None
    storage_uuid: str | None = None
    user_uuid: str | None = None
    node_uuid: str | None = None
    folder_name: str | None = None
    new_name: str | None = None
    content: str | None = None
    search: str | None = None


class CreateShareLinkRequest(BaseModel):
    node_uuid: str
    node_type: str  # 'file' | 'folder'
    password: str | None = None
