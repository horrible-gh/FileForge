from fastapi import APIRouter, Depends, HTTPException
from config import settings, db
from routers.login.auth import verify_token
from schemas.mail.labels import (
    LabelCreateRequest,
    LabelUpdateRequest,
    LabelGetRequest,
    MessageLabelAssignRequest,
    LabelFilterRequest
)
import LogAssist.log as logger

db_instance = db.db_instance
sqloader = db.sqloader

router = APIRouter()

# 1. Get label list
@router.get("/list", dependencies=[Depends(verify_token)])
async def get_labels(request: LabelGetRequest = Depends()):
    data = request.model_dump()
    logger.debug(f"🔍 get_labels 호출됨 - user_uuid: {data.get('user_uuid')}")

    result = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.get_labels"),
        data
    )

    logger.debug(f"📦 DB 결과: {result}")
    return {"labels": result}

# 2. Create label
@router.post("/create", dependencies=[Depends(verify_token)])
async def create_label(request: LabelCreateRequest):
    data = request.model_dump()

    # Duplicate check
    existing = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "labels.check_duplicate"),
        data
    )

    if existing:
        raise HTTPException(status_code=400, detail="Label name already exists")

    result = db_instance.execute(
        sqloader.load_sql("mail_anchor.json", "labels.create_label"),
        data
    )

    return {"success": True, "label_uuid": result, "message": "Label created successfully"}

# 3. Update label (dynamic SQL generation)
@router.put("/{label_uuid}", dependencies=[Depends(verify_token)])
async def update_label(label_uuid: str, request: LabelUpdateRequest):
    data = request.model_dump()
    logger.debug(f"📝 update_label 원본 데이터: {data}")

    # Build the fields to update dynamically
    update_fields = []
    params = {"label_uuid": label_uuid}

    # Field mapping: request field name → DB column name
    field_mapping = {
        "label_name": "label_name",
        "label_color": "label_color",
        "display_order": "display_order"
    }

    for field_key, column_name in field_mapping.items():
        if field_key in data and data[field_key] is not None:
            update_fields.append(f"{column_name} = %({field_key})s")
            params[field_key] = data[field_key]

    logger.debug(f"📝 update_fields: {update_fields}")
    logger.debug(f"📝 params: {params}")

    if not update_fields:
        raise HTTPException(status_code=400, detail="No fields to update")

    # Generate dynamic SQL
    query = f"""
        UPDATE mail_labels
        SET {", ".join(update_fields)}
        WHERE label_uuid = %(label_uuid)s
    """

    logger.debug(f"📝 실행 쿼리: {query}")

    db_instance.execute(query, params)

    return {"success": True, "message": "Label updated successfully"}

# 4. Delete label
@router.delete("/{label_uuid}", dependencies=[Depends(verify_token)])
async def delete_label(label_uuid: str):
    data = {"label_uuid": label_uuid}

    db_instance.execute(
        sqloader.load_sql("mail_anchor.json", "labels.delete_label"),
        data
    )

    return {"success": True, "message": "Label deleted successfully"}

# 5. Assign labels to a mail
@router.post("/assign", dependencies=[Depends(verify_token)])
async def assign_labels(request: MessageLabelAssignRequest):
    data = request.model_dump()

    # Delete existing labels
    db_instance.execute(
        sqloader.load_sql("mail_anchor.json", "labels.delete_message_labels"),
        {"message_uuid": data['message_uuid']}
    )

    # Assign new labels
    if data['label_uuids']:
        for label_uuid in data['label_uuids']:
            db_instance.execute(
                sqloader.load_sql("mail_anchor.json", "labels.assign_label"),
                {
                    "message_uuid": data['message_uuid'],
                    "label_uuid": label_uuid
                }
            )

    return {"success": True, "message": "Labels assigned successfully"}

# 6. Get a mail's labels
@router.get("/message/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_message_labels(message_uuid: str):
    data = {"message_uuid": message_uuid}

    labels = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.get_message_labels"),
        data
    )

    return {"labels": labels}

# 7. Filter mail by label (response structure fixed)
@router.get("/filter/{label_uuid}", dependencies=[Depends(verify_token)])
async def filter_by_label(label_uuid: str, request: LabelFilterRequest = Depends()):
    data = request.model_dump()
    data['label_uuid'] = label_uuid
    data['offset'] = (data['page'] - 1) * data['limit']

    logger.debug(f"🏷️ filter_by_label 호출 - label_uuid: {label_uuid}, data: {data}")

    messages = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.filter_messages"),
        data
    )

    logger.debug(f"🏷️ 필터링 결과: {len(messages)}개")

    total_result = db_instance.fetch_one(
        sqloader.load_sql("mail_anchor.json", "labels.filter_messages_count"),
        data
    )

    total = total_result['total'] if total_result else 0
    has_more = (data['page'] * data['limit']) < total

    # Match the response structure expected by MailList.vue
    return {
        "success": True,
        "messages": messages,
        "pagination": {
            "total": total,
            "page": data['page'],
            "limit": data['limit']
        },
        "has_more": has_more
    }

# 8. Label statistics
@router.get("/stats", dependencies=[Depends(verify_token)])
async def get_label_stats(request: LabelGetRequest = Depends()):
    data = request.model_dump()
    logger.debug("data", data)

    stats = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.get_label_stats"),
        data
    )

    return {"label_stats": stats}
