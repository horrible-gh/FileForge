"""Object authorization at the API boundary.

The legacy storage handlers accept user/group/storage identifiers supplied by the
client. Those identifiers are NOT credentials. This dependency checks the signed
principal, every target object and its actual storage before a handler can run.
Unknown operations fail closed. SQL parameters use the project's DB adapter.
"""
from collections.abc import Mapping
from dataclasses import dataclass
from fastapi import Depends, HTTPException, Request
from config import db, adapt_query
from routers.login.auth import verify_token


@dataclass(frozen=True)
class Principal:
    user_uuid: str
    group_uuid: str | None


def principal_for(user_id: str) -> Principal:
    row = db.db_instance.fetch_one(
        adapt_query("SELECT user_uuid, group_uuid FROM users WHERE user_id = ?"),
        (user_id,),
    )
    if not row or not row.get("user_uuid"):
        raise HTTPException(401, "Invalid authentication credentials")
    return Principal(row["user_uuid"], row.get("group_uuid"))


def require_storage(principal: Principal, storage_uuid: str, permission: str) -> str:
    if not isinstance(storage_uuid, str) or not storage_uuid:
        raise HTTPException(422, "storage_uuid_required")
    if storage_uuid == "default":
        row = db.db_instance.fetch_one(
            adapt_query("SELECT storage_uuid FROM user_storages WHERE user_uuid = ? AND is_default = 1"),
            (principal.user_uuid,),
        )
        if not row:
            raise HTTPException(403, "storage_access_denied")
        storage_uuid = row["storage_uuid"]
    if permission not in {"read", "write"}:
        raise HTTPException(403, "storage_access_denied")
    modes = ("r", "rw") if permission == "read" else ("w", "rw")
    row = db.db_instance.fetch_one(
        adapt_query(
            "SELECT us.storage_uuid FROM user_storages us "
            "JOIN storages s ON s.storage_uuid = us.storage_uuid "
            "WHERE us.storage_uuid = ? AND s.status = 'active' "
            "AND (us.user_uuid = ? OR (us.group_uuid IS NOT NULL AND us.group_uuid = ?)) "
            "AND us.mode IN (?, ?)"
        ),
        (storage_uuid, principal.user_uuid, principal.group_uuid or None, *modes),
    )
    if not row:
        raise HTTPException(403, "storage_access_denied")
    return storage_uuid


def require_node(principal: Principal, node_uuid: str, permission: str,
                 storage_uuid: str | None = None, node_type: str | None = None) -> dict:
    if not isinstance(node_uuid, str) or not node_uuid:
        raise HTTPException(422, "node_uuid_required")
    node = db.db_instance.fetch_one(
        adapt_query("SELECT node_uuid, storage_uuid, type FROM nodes WHERE node_uuid = ?"),
        (node_uuid,),
    )
    if not node:
        raise HTTPException(404, "node_not_found")
    # Never authorize storage A and then operate on a node from storage B.
    if storage_uuid is not None and node["storage_uuid"] != storage_uuid:
        raise HTTPException(403, "storage_access_denied")
    require_storage(principal, node["storage_uuid"], permission)
    if node_type is not None and node["type"] != node_type:
        raise HTTPException(422, "invalid_node_type")
    return node


def require_user_node(user_id: str, node_uuid: str, permission: str = "read") -> dict:
    return require_node(principal_for(user_id), node_uuid, permission)


def _check_identity(principal: Principal, data: Mapping) -> None:
    # Keep the existing wire contract, but reject forged identity fields instead
    # of letting an old handler use them as its authorization identity.
    for name, expected in (("user_uuid", principal.user_uuid), ("group_uuid", principal.group_uuid)):
        supplied = data.get(name)
        if supplied not in (None, "") and supplied != expected:
            raise HTTPException(403, "identity_mismatch")


async def _parameters(request: Request) -> Mapping:
    if request.method in {"GET", "DELETE"}:
        data = request.query_params
    elif request.url.path.rstrip("/").endswith("/upload"):
        # FastAPI has already parsed/cached the multipart form for this handler.
        data = await request.form()
    else:
        try:
            data = await request.json()
        except (ValueError, UnicodeError):
            raise HTTPException(422, "invalid_request_body") from None
    if not isinstance(data, Mapping):
        raise HTTPException(422, "invalid_request_body")
    if hasattr(data, "getlist"):
        for field in ("user_uuid", "group_uuid", "storage_uuid", "node_uuid", "parent_uuid"):
            if len(data.getlist(field)) > 1:
                raise HTTPException(422, "duplicate_identifier")
    return data


async def authorize_storage_request(request: Request, user_id: str = Depends(verify_token)) -> None:
    """Mounted on BOTH storage routers by routers/main.py, before all handlers."""
    principal = principal_for(user_id)
    data = await _parameters(request)
    _check_identity(principal, data)
    path = request.url.path.rstrip("/")
    operation = path.rsplit("/", 1)[-1]
    if "/storages/bulk/" in path:
        if (request.method, operation) not in {("POST", "download"), ("POST", "delete")}:
            raise HTTPException(403, "operation_not_authorized")
        identifiers = data.get("node_uuids")
        if not isinstance(identifiers, list) or not identifiers or len(identifiers) > 500:
            raise HTTPException(422, "invalid_node_uuids")
        permission = "read" if operation == "download" else "write"
        # Preflight the ENTIRE batch. No handler runs, and no files are deleted,
        # until every node passes. Never silently skip an unauthorized item.
        for node_uuid in identifiers:
            require_node(principal, node_uuid, permission)
        return

    permissions = {
        ("GET", "get_user_storages"): "list",
        ("GET", "get_directory_trees"): "read",
        ("GET", "get_node_children"): "read",
        ("GET", "download"): "read",
        ("POST", "create_folder"): "write",
        ("POST", "upload"): "write",
        ("DELETE", "delete"): "write",
        ("PUT", "rename"): "write",
        ("PUT", "update_file_content"): "write",
    }
    permission = permissions.get((request.method, operation))
    if permission is None:
        raise HTTPException(403, "operation_not_authorized")
    if permission == "list":
        # This legacy endpoint also provisions a user's vault-storage mapping.
        if data.get("user_uuid") != principal.user_uuid:
            raise HTTPException(403, "identity_mismatch")
        return
    storage_uuid = require_storage(principal, data.get("storage_uuid"), permission)
    if operation in {"download", "delete", "rename", "update_file_content"}:
        require_node(principal, data.get("node_uuid"), permission, storage_uuid,
                     "file" if operation == "update_file_content" else None)
    else:
        parent = data.get("parent_uuid") if operation == "upload" else data.get("node_uuid")
        if parent:
            require_node(principal, parent, permission, storage_uuid, "folder")
    if operation in {"create_folder", "rename"}:
        name = data.get("folder_name" if operation == "create_folder" else "new_name")
        if not isinstance(name, str) or not name.strip() or name in {".", ".."} or any(c in name for c in ("/", "\\", "\x00")):
            raise HTTPException(422, "invalid_name")
