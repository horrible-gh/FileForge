from fastapi import APIRouter, Header, Query, HTTPException
from fastapi.responses import FileResponse
from config import db
from services.shared_link_service import SharedLinkService
from routers.storages._helper import get_physical_path
import LogAssist.log as logger
from urllib.parse import quote

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()


def _get_service() -> SharedLinkService:
    return SharedLinkService(db_instance, sqloader)


def _resolve_password(
    query_password: str | None,
    header_password: str | None,
) -> str | None:
    return query_password or header_password


def _check_password(link: dict, password: str | None):
    """
    비밀번호 검증.
    - password_hash가 있는데 password 미제공 → 401
    - password_hash가 있는데 password 틀림 → 403
    """
    service = _get_service()
    if link["password_hash"] is not None:
        if not password:
            raise HTTPException(status_code=401, detail="password_required")
        if not service.verify_password(link, password):
            raise HTTPException(status_code=403, detail="invalid_password")


def _get_storage_path(storage_uuid: str) -> str:
    row = db_instance.fetch_one(
        "SELECT storage_path FROM storages WHERE storage_uuid = %s",
        (storage_uuid,)
    )
    if not row:
        raise HTTPException(status_code=404, detail="Storage not found.")
    return row["storage_path"]


def _build_file_response(storage_path: str, node_uuid: str, name: str, mime_type: str) -> FileResponse:
    file_path = get_physical_path(storage_path, node_uuid, name)
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found.")
    encoded_filename = quote(name)
    return FileResponse(
        path=str(file_path),
        media_type=mime_type or "application/octet-stream",
        headers={
            "Content-Disposition": f"attachment; filename*=UTF-8''{encoded_filename}"
        }
    )


def _resolve_folder_path(root_uuid: str, path: str) -> str:
    """
    경로를 따라 탐색하여 최종 폴더 UUID 반환.
    예: path="subfolder1/subfolder2" → root_uuid의 하위 subfolder1의 하위 subfolder2의 UUID
    """
    current_uuid = root_uuid
    if not path or path == "/":
        return current_uuid

    path_parts = [p for p in path.split("/") if p]
    for part in path_parts:
        child = db_instance.fetch_one(
            "SELECT node_uuid FROM nodes WHERE parent_uuid = %s AND name = %s AND type = 'folder'",
            (current_uuid, part)
        )
        if not child:
            raise HTTPException(status_code=404, detail=f"Folder path not found: {part}")
        current_uuid = child["node_uuid"]

    return current_uuid


def _is_descendant(node_uuid: str, ancestor_uuid: str) -> bool:
    """
    node_uuid가 ancestor_uuid의 하위 노드인지 확인 (직속 또는 모든 하위).
    """
    current = node_uuid
    max_depth = 100  # 무한 루프 방지
    depth = 0

    while current and depth < max_depth:
        if current == ancestor_uuid:
            return True
        row = db_instance.fetch_one(
            "SELECT parent_uuid FROM nodes WHERE node_uuid = %s",
            (current,)
        )
        if not row or not row["parent_uuid"]:
            return False
        current = row["parent_uuid"]
        depth += 1

    return False


@router.get("/{token}")
async def public_share_access(
    token: str,
    password: str | None = Query(default=None),
    x_share_password: str | None = Header(default=None),
    meta: bool = Query(default=False),
    path: str = Query(default=""),
):
    """
    공유 링크 접근.
    - meta=true: 파일/폴더 모두 JSON 메타데이터 반환 (파일 스트리밍 없음)
    - path: 폴더 공유 시 하위 경로 지정 (예: "subfolder1/subfolder2")
    - 파일: 바이너리 다운로드 응답
    - 폴더: 하위 파일/폴더 목록 JSON 응답
    """
    service = _get_service()
    link = service.get_by_token(token)
    if not link:
        raise HTTPException(status_code=404, detail="Share link not found.")

    _check_password(link, _resolve_password(password, x_share_password))

    node_uuid = link["node_uuid"]
    node_type = link["node_type"]

    if node_type == "file":
        if meta:
            # 파일 크기 조회
            size_row = db_instance.fetch_one(
                "SELECT file_size FROM files WHERE node_uuid = %s",
                (node_uuid,)
            )
            return {
                "node_type": "file",
                "name": link["name"],
                "file_size": size_row["file_size"] if size_row else None,
                "mime_type": link["mime_type"],
            }
        storage_uuid = link["storage_uuid"]
        storage_path = _get_storage_path(storage_uuid)
        return _build_file_response(
            storage_path,
            node_uuid,
            link["name"],
            link["mime_type"],
        )

    # 폴더: path를 따라 탐색하여 target 폴더 결정
    target_uuid = _resolve_folder_path(node_uuid, path)

    # target 폴더의 직속 하위 파일 조회
    files = db_instance.fetch_all(
        "SELECT n.node_uuid, n.name, f.file_size, f.mime_type "
        "FROM nodes n JOIN files f ON n.node_uuid = f.node_uuid "
        "WHERE n.parent_uuid = %s AND n.type = 'file' "
        "ORDER BY n.name",
        (target_uuid,)
    )

    # target 폴더의 직속 하위 폴더 조회
    folders = db_instance.fetch_all(
        "SELECT node_uuid, name "
        "FROM nodes "
        "WHERE parent_uuid = %s AND type = 'folder' "
        "ORDER BY name",
        (target_uuid,)
    )

    # target 폴더 이름 조회 (path가 있는 경우 root와 다름)
    if path and path != "/":
        target_info = db_instance.fetch_one(
            "SELECT name FROM nodes WHERE node_uuid = %s",
            (target_uuid,)
        )
        folder_name = target_info["name"] if target_info else link["name"]
    else:
        folder_name = link["name"]

    return {
        "node_type": "folder",
        "folder_name": folder_name,
        "current_path": path if path else "",
        "items": [
            {"uuid": row["node_uuid"], "name": row["name"], "type": "folder"}
            for row in folders
        ] + [
            {
                "uuid": row["node_uuid"],
                "name": row["name"],
                "type": "file",
                "size": row["file_size"],
                "mime_type": row["mime_type"],
            }
            for row in files
        ],
    }


@router.get("/{token}/{file_uuid}")
async def public_share_file_download(
    token: str,
    file_uuid: str,
    password: str | None = Query(default=None),
    x_share_password: str | None = Header(default=None),
    path: str = Query(default=""),
):
    """
    폴더 공유 링크에서 개별 파일 다운로드.
    file_uuid가 공유 폴더의 하위 파일인지 검증 (직속 또는 서브폴더 내).
    path: 파일이 있는 하위 경로 (예: "subfolder1/subfolder2")
    """
    service = _get_service()
    link = service.get_by_token(token)
    if not link:
        raise HTTPException(status_code=404, detail="Share link not found.")

    if link["node_type"] != "folder":
        raise HTTPException(status_code=400, detail="This link is not a folder share.")

    _check_password(link, _resolve_password(password, x_share_password))

    root_folder_uuid = link["node_uuid"]
    storage_uuid = link["storage_uuid"]

    # 파일이 공유 폴더의 하위 노드인지 검증
    if not _is_descendant(file_uuid, root_folder_uuid):
        raise HTTPException(status_code=404, detail="File not found in this shared folder.")

    # 파일 정보 조회
    file_node = db_instance.fetch_one(
        "SELECT n.node_uuid, n.name, f.mime_type "
        "FROM nodes n JOIN files f ON n.node_uuid = f.node_uuid "
        "WHERE n.node_uuid = %s AND n.type = 'file'",
        (file_uuid,)
    )
    if not file_node:
        raise HTTPException(status_code=404, detail="File not found.")

    storage_path = _get_storage_path(storage_uuid)
    logger.debug("public_share_file_download", file_node)

    return _build_file_response(
        storage_path,
        file_node["node_uuid"],
        file_node["name"],
        file_node["mime_type"],
    )