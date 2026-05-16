from fastapi import APIRouter, Depends, UploadFile, Form, HTTPException, Request
from pathlib import Path
import hashlib
from fastapi.responses import FileResponse, StreamingResponse
import zipfile
import io
from fastapi.responses import StreamingResponse
from config import settings, db
from schemas.storages import UserStoragesRequest
from routers.login.auth import verify_token
import LogAssist.log as logger
from urllib.parse import quote
import uuid
from ._helper import get_physical_path, delete_item, permission_check, create_folders_from_path
from slowapi import Limiter
from slowapi.util import get_remote_address
import traceback

limiter = Limiter(key_func=get_remote_address)

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

@router.get("/get_user_storages", dependencies=[Depends(verify_token)])
async def get_user_storages(params: UserStoragesRequest = Depends()):
    dump_data = params.model_dump()
    logger.debug("dump_data", dump_data)
    data = (
        dump_data.get("user_uuid", ""),
        dump_data.get("group_uuid", ""),
    )
    return db_instance.fetch_all(sqloader.load_sql("file_forge.json", "storages.get_user_storages"), data)

@router.get("/get_directory_trees", dependencies=[Depends(verify_token)])
async def get_directory_trees(params: UserStoragesRequest = Depends()):
    dump_data = params.model_dump()
    logger.debug("dump_data", dump_data)

    storage_uuid = dump_data.get("storage_uuid", "")
    user_uuid = dump_data.get("user_uuid", "")
    search_type = 'directory'

    data = (
        storage_uuid,
        search_type,
        search_type,
        '',
        '',
        '',
        'folder',
        None,
        None,
    )
    tree_results = db_instance.fetch_all(sqloader.load_sql("file_forge.json", "storages.get_node_children"), data)

    return {
        "storage_uuid": storage_uuid,
        "tree": tree_results
    }


@router.get("/get_node_children", dependencies=[Depends(verify_token)])
async def get_node_children(params: UserStoragesRequest = Depends()):
    dump_data = params.model_dump()
    logger.debug("dump_data", dump_data)

    storage_uuid = dump_data.get("storage_uuid", "")
    user_uuid = dump_data.get("user_uuid", "")
    node_uuid = dump_data.get("node_uuid") or None
    search_type = 'file'
    breadcrumb_path_data = []
    search = dump_data.get("search", None)
    search_pattern = f"%{search}%" if search else None

    data = (
        storage_uuid,
        search_type,
        search_type,
        node_uuid,
        node_uuid,
        node_uuid,
        '%',
        search_pattern,
        search_pattern,
    )
    tree_results = db_instance.fetch_all(sqloader.load_sql("file_forge.json", "storages.get_node_children"), data)
    logger.debug("tree_results", tree_results)

    # 스토리지 경로 조회
    storage_info = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_storage_quota_limit"),
        (storage_uuid,)
    )
    storage_path = storage_info['storage_path'] if storage_info else None

    # 텍스트 파일이면 preview 추가
    text_extensions = ['txt', 'md', 'json', 'yaml', 'yml', 'xml', 'csv', 'log']

    for item in tree_results:
        item['preview'] = ''
        if item.get('type') == 'file' and storage_path:
            name = item.get('name', '')
            ext = name.split('.')[-1].lower() if '.' in name else ''
            if ext in text_extensions:
                try:
                    file_path = get_physical_path(storage_path, item['node_uuid'], name)
                    if file_path.exists():
                        with open(file_path, 'r', encoding='utf-8') as f:
                            content = f.read(200)  # 앞 200자
                            item['preview'] = content.strip()
                except Exception as e:
                    logger.error(f"preview 읽기 실패: {e}")

    current_result = {
        "node_uuid": node_uuid,
        "name": "Root",
        "parent_uuid": None
    }

    if node_uuid is not None:
        [current_data] = db_instance.fetch_all(
            sqloader.load_sql("file_forge.json", "storages.get_current_node"),
            (node_uuid,)
        )
        logger.debug("current_data", current_data)
        current_result = {
            "node_uuid": node_uuid,
            "name": current_data.get("name", ""),
            "parent_uuid": current_data.get("parent_uuid", "")
        }

        breadcrumb_path_data = db_instance.fetch_all(sqloader.load_sql("file_forge.json", "storages.get_breadcrumb_path"), (node_uuid,))
        logger.debug("breadcrumb_path_data", breadcrumb_path_data)

    return {
        "storage_uuid": storage_uuid,
        "current_node": current_result,
        "breadcrumb_path": breadcrumb_path_data,
        "children": tree_results
    }


@router.get("/download", dependencies=[Depends(verify_token)])
@limiter.limit(settings.RATE_LIMIT_DOWNLOAD)  # 설정파일에서 가져옴
async def download(request: Request, params: UserStoragesRequest = Depends()):
    dump_data = params.model_dump()
    logger.debug("dump_data", dump_data)

    storage_uuid = dump_data.get("storage_uuid", "")
    user_uuid = dump_data.get("user_uuid", "")
    node_uuid = dump_data.get("node_uuid", "")
    group_uuid = dump_data.get("group_uuid", "")

    permission_check(storage_uuid, user_uuid, group_uuid, "download")

    prm2 = (node_uuid,)

    # 노드 정보 먼저 조회 (타입 확인)
    node_info = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_node_by_uuid"),
        prm2
    )

    if not node_info:
        raise HTTPException(status_code=404, detail="Node not found.")

    # 스토리지 경로 가져오기
    storage_info = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_storage_path"),
        (node_info['storage_uuid'],)
    )
    storage_path = storage_info['storage_path']

    if node_info['type'] == 'file':
        # 단일 파일 다운로드
        file_path = get_physical_path(storage_path, node_info['node_uuid'], node_info['name'])

        logger.debug("file_path", file_path)

        if not file_path.exists():
            logger.error(f"File not found: {file_path}")
            raise HTTPException(status_code=404, detail="File not found.")

        # 한글 파일명 처리
        encoded_filename = quote(node_info['name'])
        return FileResponse(
            path=str(file_path),
            media_type='application/octet-stream',
            headers={
                'Content-Disposition': f'attachment; filename*=UTF-8\'\'{encoded_filename}'
            }
        )

    else:  # type == 'folder'
        # 폴더 다운로드 - ZIP으로 압축
        all_nodes = db_instance.fetch_all(
            sqloader.load_sql("file_forge.json", "storages.get_download"),
            prm2
        )
        logger.debug("all_nodes", all_nodes)

        if not all_nodes:
            raise HTTPException(status_code=404, detail="Folder is empty.")

        folder_name = node_info['name']

        # ZIP 파일 생성
        zip_buffer = io.BytesIO()
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
            for node in all_nodes:
                relative_path = node['full_path']

                if node['type'] == 'folder':
                    # 빈 폴더도 ZIP에 추가
                    folder_path_in_zip = relative_path + '/'
                    zip_file.writestr(folder_path_in_zip, '')

                elif node['type'] == 'file':
                    # 물리 파일 경로 (새로운 구조)
                    file_path = get_physical_path(storage_path, node['node_uuid'], node['name'])

                    if file_path.exists():
                        zip_file.write(file_path, relative_path)
                    else:
                        logger.warning(f"파일 없음: {file_path}")

        zip_buffer.seek(0)
        encoded_filename = quote(f"{folder_name}.zip")

        return StreamingResponse(
            zip_buffer,
            media_type='application/zip',
            headers={
                'Content-Disposition': f'attachment; filename="{folder_name}.zip"; filename*=UTF-8\'\'{encoded_filename}'
            }
        )

@router.post("/create_folder", dependencies=[Depends(verify_token)])
async def create_folder(params: UserStoragesRequest):
    dump_data = params.model_dump()
    logger.debug("dump_data", dump_data)

    storage_uuid = dump_data.get("storage_uuid", "")
    group_uuid = dump_data.get("user_uuid", "")
    user_uuid = dump_data.get("user_uuid", "")
    parent_node_uuid = dump_data.get("node_uuid", "")
    if not parent_node_uuid:
        parent_node_uuid = None
    type = 'folder'
    folder_name = dump_data.get("folder_name", "")
    node_uuid = str(uuid.uuid4())

    permission_check(storage_uuid, user_uuid, group_uuid, "upload")

    # 1. 물리 디렉터리 생성
    storage_path_result = db_instance.fetch_one(
        sqloader.load_sql("file_forge.json", "storages.get_storage_path"),
        (storage_uuid,)
    )
    logger.debug("storage_path_result", storage_path_result)

    if not parent_node_uuid:
        parent_path = ""
    else:
        parent_path = parent_node_uuid

    storage_path = storage_path_result['storage_path']
    folder_path = Path(storage_path, node_uuid)
    # folder_path.mkdir(parents=True, exist_ok=True)

    # 2. DB에 노드 삽입
    data = (
        storage_uuid,
        node_uuid,
        folder_name,
        type,
        parent_node_uuid,
        user_uuid
    )
    db_instance.execute_query(sqloader.load_sql("file_forge.json", "storages.insert_node"), data)

    # 3. 적절한 응답 반환
    return {
        "success": True,
        "node_uuid": node_uuid,
        "folder_name": folder_name,
        "parent_uuid": parent_node_uuid
    }


@router.post("/upload", dependencies=[Depends(verify_token)])
@limiter.limit(settings.RATE_LIMIT_UPLOAD)
async def upload_file(
    request: Request,
    file: UploadFile,
    storage_uuid: str = Form(...),
    parent_uuid: str = Form(...),
    user_uuid: str = Form(...),
    group_uuid: str = Form(...),
    relative_path: str = Form(None)  # 추가
):
    try:
        permission_check(storage_uuid, user_uuid, group_uuid, "upload")

        # 빈 문자열을 None으로 변환
        if not parent_uuid or parent_uuid == '':
            parent_uuid = None

        # relative_path가 있으면 폴더 구조 생성
        if relative_path and '/' in relative_path:
            parent_uuid = await create_folders_from_path(
                storage_uuid, parent_uuid, relative_path, user_uuid
            )

        # 1. 스토리지 정보 및 현재 사용량 조회
        storage_info = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_storage_quota_limit"),
            (storage_uuid,)
        )

        if not storage_info:
            raise HTTPException(status_code=404, detail="Storage not found")

        storage_path = storage_info['storage_path']
        quota_limit = storage_info['quota_limit']
        used_size = storage_info['used_size']

        # 2. 파일 크기 확인
        file_content = await file.read()
        file_size = len(file_content)

        # 3. 같은 이름의 기존 파일 체크 (덮어쓰기의 경우 기존 용량 제외)
        if parent_uuid is None:
            existing_node = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_existing_file_at_root"),
                (file.filename, storage_uuid)
            )
        else:
            existing_node = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_existing_file_in_folder"),
                (parent_uuid, file.filename)
            )

        # 4. 용량 체크
        if existing_node:
            # 덮어쓰기: 기존 파일 용량 제외하고 계산
            old_file_size = existing_node['file_size'] or 0
            new_used_size = used_size - old_file_size + file_size
            node_uuid = existing_node['node_uuid']
        else:
            # 새 파일: 그대로 추가
            new_used_size = used_size + file_size
            node_uuid = str(uuid.uuid4())

        # 5. 용량 초과 체크
        if new_used_size > quota_limit:
            raise HTTPException(
                status_code=413,
                detail=f"Storage quota exceeded. Available: {quota_limit - used_size} bytes, Required: {file_size} bytes"
            )

        # 6. 파일 저장 경로 생성
        file_path = get_physical_path(storage_path, node_uuid, file.filename)
        file_path.parent.mkdir(parents=True, exist_ok=True)

        # 7. 파일 저장
        with open(file_path, "wb") as f:
            f.write(file_content)

        # 8. 파일 해시 계산
        file_hash = hashlib.sha256(file_content).hexdigest()

        if existing_node:
            # 기존 파일 업데이트
            db_instance.execute_query(
                sqloader.load_sql("file_forge.json", "storages.update_file_on_upload"),
                (file_hash, file_size, file.content_type or 'application/octet-stream', user_uuid, node_uuid)
            )
        else:
            # 새 파일 INSERT
            prm1 = (
                storage_uuid,
                node_uuid,
                file.filename,
                'file',
                parent_uuid,
                user_uuid,
            )

            prm2 = (
                node_uuid,
                file_hash,
                file_size,
                file.content_type or 'application/octet-stream',
                user_uuid,
            )

            db_instance.execute_query(sqloader.load_sql("file_forge.json", "storages.insert_node"), prm1)
            db_instance.execute_query(sqloader.load_sql("file_forge.json", "storages.insert_file"), prm2)

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"파일 업로드 실패: {e}")
        logger.error(traceback.format_exc())
        raise HTTPException(status_code=500, detail="File upload failed")

    return {
        "success": True,
        "node_uuid": node_uuid,
        "filename": file.filename
    }

@router.delete("/delete", dependencies=[Depends(verify_token)])
async def delete_node(params: UserStoragesRequest = Depends()):

    dump_data = params.model_dump()
    node_uuid = dump_data.get("node_uuid")
    user_uuid = dump_data.get("user_uuid")
    group_uuid = dump_data.get("group_uuid")
    storage_uuid = dump_data.get("storage_uuid")

    try:
        permission_check(storage_uuid, user_uuid, group_uuid, "upload")

        node_type = delete_item(node_uuid)

        return {
            "success": True,
            "deleted_node_uuid": node_uuid,
            "type": node_type
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"삭제 실패: {e}")
        raise HTTPException(status_code=500, detail="Delete failed")

@router.put("/rename", dependencies=[Depends(verify_token)])
async def rename_node(request: UserStoragesRequest):  # 이름만 변경
    node_uuid = request.node_uuid
    new_name = request.new_name
    user_uuid = request.user_uuid
    group_uuid = request.group_uuid
    storage_uuid = request.storage_uuid

    try:
        permission_check(storage_uuid, user_uuid, group_uuid, "upload")

        # 1. 노드 정보 조회
        node_info = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_current_node"),
            (node_uuid,)
        )

        if not node_info:
            raise HTTPException(status_code=404, detail="Node not found")

        old_name = node_info['name']
        node_type = node_info['type']
        storage_path = node_info['storage_path']
        parent_uuid = node_info['parent_uuid']

        # 2. 중복 이름 체크
        if parent_uuid:
            duplicate = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_duplicate_in_folder"),
                (parent_uuid, new_name, node_uuid)
            )
        else:
            duplicate = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_duplicate_at_root"),
                (new_name, node_uuid)
            )

        if duplicate:
            raise HTTPException(status_code=409, detail="Name already exists")

        # 3. 파일인 경우만 물리 파일명 변경 (확장자만)
        if node_type == 'file':
            old_ext = Path(old_name).suffix
            new_ext = Path(new_name).suffix

            if old_ext != new_ext:
                old_path = get_physical_path(storage_path, node_uuid, old_name)
                new_path = get_physical_path(storage_path, node_uuid, new_name)

                if old_path.exists():
                    old_path.rename(new_path)

        # 4. DB 업데이트
        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.update_node_name"),
            (new_name, user_uuid, node_uuid)
        )

        return {
            "success": True,
            "node_uuid": node_uuid,
            "old_name": old_name,
            "new_name": new_name,
            "type": node_type
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"이름 변경 실패: {e}")
        raise HTTPException(status_code=500, detail="Rename failed")

@router.put("/update_file_content", dependencies=[Depends(verify_token)])
async def update_file_content(request: UserStoragesRequest):
    try:
        storage_uuid = request.storage_uuid
        node_uuid = request.node_uuid
        content = request.content
        user_uuid = request.user_uuid

        # 1. 노드 정보 조회
        node = db_instance.fetch_one(
            sqloader.load_sql("file_forge.json", "storages.get_current_node"),
            (node_uuid,)
        )

        if not node or node['type'] != 'file':
            raise HTTPException(status_code=404, detail="File not found")

        storage_path = node['storage_path']
        file_name = node['name']

        # 2. 물리 파일 경로
        file_path = get_physical_path(storage_path, node_uuid, file_name)
        logger.debug(f"저장 경로: {file_path}")
        logger.debug(f"내용: {content[:100]}")  # 앞 100자만

        # 3. 파일 저장
        content_bytes = content.encode('utf-8')
        with open(file_path, 'wb') as f:
            f.write(content_bytes)
        logger.debug(f"파일 저장 완료!")

        # 4. DB 업데이트 (파일 크기, 해시, 수정 정보)
        new_size = len(content_bytes)
        new_hash = hashlib.sha256(content_bytes).hexdigest()

        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.update_file_content"),
            (new_size, new_hash, user_uuid, node_uuid)
        )
        db_instance.execute_query(
            sqloader.load_sql("file_forge.json", "storages.update_node_modified"),
            (node_uuid,)
        )

        return {
            "success": True,
            "message": "File updated successfully",
            "new_size": new_size  # ← 새 크기 반환
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"파일 수정 실패: {e}")
        raise HTTPException(status_code=500, detail="File update failed")
