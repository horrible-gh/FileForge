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

# 1. 라벨 목록 조회
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

# 2. 라벨 생성
@router.post("/create", dependencies=[Depends(verify_token)])
async def create_label(request: LabelCreateRequest):
    data = request.model_dump()

    # 중복 체크
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

# 3. 라벨 수정 (동적 SQL 생성)
@router.put("/{label_uuid}", dependencies=[Depends(verify_token)])
async def update_label(label_uuid: str, request: LabelUpdateRequest):
    data = request.model_dump()
    logger.debug(f"📝 update_label 원본 데이터: {data}")

    # 업데이트할 필드 동적 생성
    update_fields = []
    params = {"label_uuid": label_uuid}

    # 필드 매핑: request 필드명 → DB 컬럼명
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

    # 동적 SQL 생성
    query = f"""
        UPDATE mail_labels
        SET {", ".join(update_fields)}
        WHERE label_uuid = %(label_uuid)s
    """

    logger.debug(f"📝 실행 쿼리: {query}")

    db_instance.execute(query, params)

    return {"success": True, "message": "Label updated successfully"}

# 4. 라벨 삭제
@router.delete("/{label_uuid}", dependencies=[Depends(verify_token)])
async def delete_label(label_uuid: str):
    data = {"label_uuid": label_uuid}

    db_instance.execute(
        sqloader.load_sql("mail_anchor.json", "labels.delete_label"),
        data
    )

    return {"success": True, "message": "Label deleted successfully"}

# 5. 메일에 라벨 지정
@router.post("/assign", dependencies=[Depends(verify_token)])
async def assign_labels(request: MessageLabelAssignRequest):
    data = request.model_dump()

    # 기존 라벨 삭제
    db_instance.execute(
        sqloader.load_sql("mail_anchor.json", "labels.delete_message_labels"),
        {"message_uuid": data['message_uuid']}
    )

    # 새 라벨 지정
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

# 6. 메일의 라벨 조회
@router.get("/message/{message_uuid}", dependencies=[Depends(verify_token)])
async def get_message_labels(message_uuid: str):
    data = {"message_uuid": message_uuid}

    labels = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.get_message_labels"),
        data
    )

    return {"labels": labels}

# 7. 라벨별 메일 필터링 (✅ 응답 구조 수정)
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

    # ✅ MailList.vue가 기대하는 응답 구조로 맞춤
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

# 8. 라벨 통계
@router.get("/stats", dependencies=[Depends(verify_token)])
async def get_label_stats(request: LabelGetRequest = Depends()):
    data = request.model_dump()
    logger.debug("data", data)

    stats = db_instance.fetch_all(
        sqloader.load_sql("mail_anchor.json", "labels.get_label_stats"),
        data
    )

    return {"label_stats": stats}
