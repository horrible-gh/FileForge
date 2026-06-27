from pydantic import BaseModel
from typing import List, Optional

class LabelGetRequest(BaseModel):
    user_uuid: str

class LabelCreateRequest(BaseModel):
    user_uuid: str
    label_name: str
    label_color: str = "#4a6cf7"

class LabelUpdateRequest(BaseModel):
    label_name: Optional[str] = None
    label_color: Optional[str] = None
    display_order: Optional[int] = None

class MessageLabelAssignRequest(BaseModel):
    message_uuid: str
    label_uuids: List[str]

class LabelFilterRequest(BaseModel):
    user_uuid: str
    page: int = 1
    limit: int = 50
