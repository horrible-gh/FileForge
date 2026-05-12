from fastapi import APIRouter,  Depends, HTTPException
from fastapi.responses import Response
import zipfile
import io
from config import settings, db
from schemas.storages import UserStoragesRequest
from routers.login.auth import verify_token
import LogAssist.log as logger
from urllib.parse import quote
from ._helper import get_physical_path, delete_item


db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

@router.post("/download", dependencies=[Depends(verify_token)])
async def bulk_download(request: UserStoragesRequest):
    try:
        node_uuids = request.node_uuids
        
        # 1. 모든 노드 정보 조회
        nodes_info = []
        for node_uuid in node_uuids:
            node = db_instance.fetch_one(
                sqloader.load_sql("file_forge.json", "storages.get_current_node"),
                (node_uuid,)
            )
            if node:
                nodes_info.append(node)
        
        if not nodes_info:
            raise HTTPException(status_code=404, detail="No files found")
        
        # 2. ZIP 파일 생성
        zip_buffer = io.BytesIO()
        
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
            for node in nodes_info:
                storage_path = node['storage_path']
                node_name = node['name']
                node_type = node['type']
                node_uuid = node['node_uuid']
                parent_uuid = node['parent_uuid']
                
                if node_type == 'file':
                    # 파일 추가
                    file_path = get_physical_path(storage_path, node_uuid, node_name)

                    if file_path.exists():
                        zip_file.write(file_path, node_name)
                
                else:  # folder
                    # 폴더의 모든 하위 항목 가져오기 (재귀)
                    all_nodes = db_instance.fetch_all(
                        sqloader.load_sql("file_forge.json", "storages.get_bulk_download"),
                        (node_uuid,)
                    )
                    
                    # 폴더 내 모든 항목 추가
                    for sub_node in all_nodes:
                        relative_path = sub_node['full_path']
                        
                        if sub_node['type'] == 'folder':
                            # 빈 폴더도 추가
                            folder_path_in_zip = relative_path + '/'
                            zip_file.writestr(folder_path_in_zip, '')
                            
                        elif sub_node['type'] == 'file':
                            file_path = get_physical_path(storage_path, sub_node['parent_uuid'], sub_node['name'])
                            
                            if file_path.exists():
                                zip_file.write(file_path, relative_path)
                            else:
                                logger.warn(f"파일 없음: {file_path}")
        
        zip_buffer.seek(0)
        
        # 3. ZIP 파일 반환
        filename = f"download_{len(node_uuids)}_items.zip"
        encoded_filename = quote(filename)
        
        return Response(
            content=zip_buffer.getvalue(),
            media_type="application/zip",
            headers={
                'Content-Disposition': f'attachment; filename*=UTF-8\'\'{encoded_filename}'
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"벌크 다운로드 실패: {e}")
        raise HTTPException(status_code=500, detail="Bulk download failed")

@router.post("/delete", dependencies=[Depends(verify_token)])
async def bulk_delete(request: UserStoragesRequest):
    try:
        deleted_count = 0
        errors = []
        
        for node_uuid in request.node_uuids:
            try:
                # storages.py의 delete_item 함수 재사용
                node_type = delete_item(node_uuid)
                deleted_count += 1
                
            except Exception as e:
                logger.error(f"노드 {node_uuid} 삭제 실패: {e}")
                errors.append(f"Node {node_uuid}: {str(e)}")
                continue
        
        return {
            "success": True,
            "deleted_count": deleted_count,
            "total_count": len(request.node_uuids),
            "errors": errors if errors else None
        }
        
    except Exception as e:
        logger.error(f"벌크 삭제 실패: {e}")
        raise HTTPException(status_code=500, detail="Bulk delete failed")
        
    except Exception as e:
        logger.error(f"벌크 삭제 실패: {e}")
        raise HTTPException(status_code=500, detail="Bulk delete failed")