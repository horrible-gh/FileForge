from fastapi import APIRouter, Depends
from config import db
from schemas.storages import CreateShareLinkRequest
from routers.login.auth import verify_token
from services.shared_link_service import SharedLinkService

router = APIRouter()
db_instance = db.db_instance
sqloader = db.sqloader


def get_service() -> SharedLinkService:
    return SharedLinkService(db_instance, sqloader)


@router.post("/create", dependencies=[Depends(verify_token)])
async def create_share_link(body: CreateShareLinkRequest, user_id: str = Depends(verify_token)):
    result = get_service().create_link(node_uuid=body.node_uuid, node_type=body.node_type,
                                       created_by=user_id, password=body.password)
    return {"token": result["token"], "url": f"/share/{result['token']}"}


@router.get("/list", dependencies=[Depends(verify_token)])
async def get_share_list(user_id: str = Depends(verify_token)):
    return get_service().get_user_links(user_id)


@router.delete("/{token}")
async def delete_share_link(token: str, user_id: str = Depends(verify_token)):
    get_service().delete_link(token=token, user_id=user_id)
    return {"success": True}
