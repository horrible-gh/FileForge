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
    Password verification.
    - password_hashtext translated text password translated text → 401
    - password_hashtext translated text password text → 403
    """
    service = _get_service()
    if link["password_hash"] is not None:
        if not password:
            raise HTTPException(status_code=401, detail="password_required")
        if not service.verify_password(link, password):
            raise HTTPException(status_code=403, detail="invalid_password")


def _get_storage_path(storage_uuid: str) -> str:
    row = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_storage_path"),
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
    pathtext text translated text text folder UUID return.
    example: path="subfolder1/subfolder2" → root_uuidtext child subfolder1text child subfolder2text UUID
    """
    current_uuid = root_uuid
    if not path or path == "/":
        return current_uuid

    path_parts = [p for p in path.split("/") if p]
    for part in path_parts:
        child = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_child_folder"),
            (current_uuid, part)
        )
        if not child:
            raise HTTPException(status_code=404, detail=f"Folder path not found: {part}")
        current_uuid = child["node_uuid"]

    return current_uuid


def _is_descendant(node_uuid: str, ancestor_uuid: str) -> bool:
    """
    node_uuidtext ancestor_uuidtext child translated text text (text text all child).
    """
    current = node_uuid
    max_depth = 100  # text text text
    depth = 0

    while current and depth < max_depth:
        if current == ancestor_uuid:
            return True
        row = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_parent_uuid"),
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
    text text text.
    - meta=true: file/folder text JSON translated text return (file translated text None)
    - path: folder text text child path text (example: "subfolder1/subfolder2")
    - file: translated text download text
    - folder: child file/folder text JSON text
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
            # file size lookup
            size_row = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_file_size"),
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

    # folder: pathtext text translated text target folder text
    target_uuid = _resolve_folder_path(node_uuid, path)

    # target foldertext text child file lookup
    files = db_instance.fetch_all(
        sqloader.load_sql("file_forge.json", "storages.get_folder_files"),
        (target_uuid,)
    )

    # target foldertext text child folder lookup
    folders = db_instance.fetch_all(
        sqloader.load_sql("file_forge.json", "storages.get_folder_subfolders"),
        (target_uuid,)
    )

    # target folder name lookup (pathtext text text roottext text)
    if path and path != "/":
        target_info = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_node_name"),
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
    folder text translated text text file download.
    file_uuidtext text foldertext child filetext verify (text text textfolder text).
    path: filetext text child path (example: "subfolder1/subfolder2")
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

    # filetext text foldertext child translated text verify
    if not _is_descendant(file_uuid, root_folder_uuid):
        raise HTTPException(status_code=404, detail="File not found in this shared folder.")

    # file text lookup
    file_node = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_file_node_with_mime"),
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