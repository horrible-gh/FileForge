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
        
        # 1. all text text lookup
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
        
        # 2. ZIP file create
        zip_buffer = io.BytesIO()
        
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
            for node in nodes_info:
                storage_path = node['storage_path']
                node_name = node['name']
                node_type = node['type']
                node_uuid = node['node_uuid']
                parent_uuid = node['parent_uuid']
                
                if node_type == 'file':
                    # file add
                    file_path = get_physical_path(storage_path, node_uuid, node_name)

                    if file_path.exists():
                        zip_file.write(file_path, node_name)
                
                else:  # folder
                    # foldertext all child text translated text (text)
                    all_nodes = db_instance.fetch_all(
                        sqloader.load_sql("file_forge.json", "storages.get_bulk_download"),
                        (node_uuid,)
                    )
                    
                    # folder text all text add
                    for sub_node in all_nodes:
                        relative_path = sub_node['full_path']
                        
                        if sub_node['type'] == 'folder':
                            # empty foldertext add
                            folder_path_in_zip = relative_path + '/'
                            zip_file.writestr(folder_path_in_zip, '')
                            
                        elif sub_node['type'] == 'file':
                            file_path = get_physical_path(storage_path, sub_node['parent_uuid'], sub_node['name'])
                            
                            if file_path.exists():
                                zip_file.write(file_path, relative_path)
                            else:
                                logger.warn(f"file None: {file_path}")
        
        zip_buffer.seek(0)
        
        # 3. ZIP file return
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
        logger.error(f"text download failed: {e}")
        raise HTTPException(status_code=500, detail="Bulk download failed")

@router.post("/delete", dependencies=[Depends(verify_token)])
async def bulk_delete(request: UserStoragesRequest):
    try:
        deleted_count = 0
        errors = []
        
        for node_uuid in request.node_uuids:
            try:
                # storages.pytext delete_item text translated text
                node_type = delete_item(node_uuid)
                deleted_count += 1
                
            except Exception as e:
                logger.error(f"text {node_uuid} delete failed: {e}")
                errors.append(f"Node {node_uuid}: {str(e)}")
                continue
        
        return {
            "success": True,
            "deleted_count": deleted_count,
            "total_count": len(request.node_uuids),
            "errors": errors if errors else None
        }
        
    except Exception as e:
        logger.error(f"text delete failed: {e}")
        raise HTTPException(status_code=500, detail="Bulk delete failed")
        
    except Exception as e:
        logger.error(f"text delete failed: {e}")
        raise HTTPException(status_code=500, detail="Bulk delete failed")