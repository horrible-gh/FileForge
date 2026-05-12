from fastapi import HTTPException
from config import settings, db
import LogAssist.log as logger
from pathlib import Path
import uuid
import os

db_instance = db.db_instance
sqloader = db.sqloader

def delete_item(node_uuid):
    # 1. 노드 정보 조회 (파일인지 폴더인지 확인)
    node_info = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_current_node"),
        (node_uuid,)
    )
    logger.debug("node_info", node_info)

    if not node_info:
        raise HTTPException(status_code=404, detail="Node not found")

    node_type = node_info['type']
    storage_path = node_info['storage_path']
    parent_uuid = node_info['parent_uuid']
    file_name = node_info['name']

    if node_type == 'file':
        # 파일 삭제
        # 물리 파일 경로
        file_path = get_physical_path(storage_path, node_uuid, node_info['name'])

        # 물리 파일 삭제
        if file_path.exists():
            file_path.unlink()

        # DB에서 삭제
        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.delete_file"),
            (node_uuid,)
        )
        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.delete_file_node"),
            (node_uuid,)
        )

    else:  # folder
        # 폴더 삭제 (재귀)
        # 1. 하위 모든 파일/폴더 조회 (재귀 쿼리)
        child_nodes = db_instance.fetch_all(
            sqloader.load_sql("file_forge.json", "storages.get_folder_nodes"),
            (node_uuid,)
        )

        # 2. 모든 파일 DB 레코드 삭제
        for child in child_nodes:
            db_instance.execute_query(
                sqloader.load_sql("file_forge.json", "storages.delete_file"),
                (child['node_uuid'],)
            )

        # 3. 모든 노드 삭제 (하위 폴더 + 파일 + 자기 자신)
        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.delete_folder_nodes"),
            (node_uuid,)
        )

        # 4. 물리 디렉터리 삭제
        for child in child_nodes:
            if child['type'] == 'file':
                child_file_path = get_physical_path(storage_path, child['node_uuid'], child['name'])
                if child_file_path.exists():
                    child_file_path.unlink()

                # 빈 디렉터리도 정리
                parent_dir = child_file_path.parent
                if parent_dir.exists() and not any(parent_dir.iterdir()):
                    parent_dir.rmdir()
                    # 한 단계 더 위도 확인
                    grandparent_dir = parent_dir.parent
                    if grandparent_dir.exists() and not any(grandparent_dir.iterdir()):
                        grandparent_dir.rmdir()

    return node_type


def get_physical_path(storage_path: str, file_uuid: str, file_name: str) -> Path:
    ext = Path(file_name).suffix

    prefix = file_uuid[:2]
    suffix = file_uuid[-2:]
    physical_name = f"{file_uuid}{ext}"

    # 슬래시를 OS 구분자로 변환
    clean_path = storage_path.replace('/', os.sep).lstrip(os.sep)

    return Path(clean_path, prefix, suffix, physical_name)

def permission_check(storage_uuid, user_uuid, group_uuid, permission_type):
    prm1 = (storage_uuid, storage_uuid, user_uuid, group_uuid)

    if permission_type == "upload":
        sql = "storages.get_upload_permission"
    elif permission_type == "download":
        sql = "storages.get_download_permission"
    else:
        raise HTTPException(status_code=503, detail="Server error.")

    has_permission = db_instance.fetch_all(sqloader.load_sql("file_forge.json", sql), prm1)
    logger.debug("has_permission", has_permission)

    if not has_permission:
        raise HTTPException(status_code=403, detail="You have not permission.")

async def create_folders_from_path(storage_uuid: str, parent_uuid: str, relative_path: str, user_uuid: str) -> str:
    """
    relative_path에서 폴더 경로 추출해서 순차 생성
    예: "폴더A/폴더B/파일.txt" → 폴더A, 폴더B 생성 후 폴더B의 uuid 반환
    """
    parts = relative_path.split('/')
    folder_parts = parts[:-1]  # 마지막은 파일명이니까 제외

    current_parent = parent_uuid

    for folder_name in folder_parts:
        if not folder_name:
            continue

        # 이미 존재하는지 확인
        if current_parent is None:
            existing = db_instance.fetch_one(
                "SELECT node_uuid FROM nodes WHERE storage_uuid = ? AND parent_uuid IS NULL AND name = ? AND type = 'folder'",
                (storage_uuid, folder_name)
            )
        else:
            existing = db_instance.fetch_one(
                "SELECT node_uuid FROM nodes WHERE storage_uuid = ? AND parent_uuid = ? AND name = ? AND type = 'folder'",
                (storage_uuid, current_parent, folder_name)
            )

        if existing:
            current_parent = existing['node_uuid']
        else:
            # 폴더 생성
            new_uuid = str(uuid.uuid4())
            db_instance.execute_query(
                "INSERT INTO nodes (storage_uuid, node_uuid, name, type, parent_uuid, creator_uuid, created_at) VALUES (?, ?, ?, 'folder', ?, ?, NOW())",
                (storage_uuid, new_uuid, folder_name, current_parent, user_uuid)
            )
            current_parent = new_uuid

    return current_parent
