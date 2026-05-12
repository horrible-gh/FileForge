from fastapi import APIRouter, Depends, HTTPException
from config import db
from schemas.storages import CreateShareLinkRequest
from routers.login.auth import verify_token
from services.shared_link_service import SharedLinkService
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

def get_service() -> SharedLinkService:
    return SharedLinkService(db_instance, sqloader)


@router.post("/create", dependencies=[Depends(verify_token)])
async def create_share_link(
    body: CreateShareLinkRequest,
    user_id: str = Depends(verify_token),
):
    service = get_service()
    logger.debug("create_share_link", body.model_dump())
    result = service.create_link(
        node_uuid=body.node_uuid,
        node_type=body.node_type,
        created_by=user_id,
        password=body.password,
    )
    return {"token": result["token"], "url": f"/share/{result['token']}"}


@router.get("/list", dependencies=[Depends(verify_token)])
async def get_share_list(user_id: str = Depends(verify_token)):
    service = get_service()
    links = service.get_user_links(user_id)
    return links


@router.delete("/{token}")
async def delete_share_link(token: str, user_id: str = Depends(verify_token)):
    service = get_service()
    service.delete_link(token=token, user_id=user_id)
    return {"success": True}