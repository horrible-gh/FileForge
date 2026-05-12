import uuid
import hashlib


class SharedLinkService:
    def __init__(self, db_instance, sqloader):
        self.db = db_instance
        self.sq = sqloader

    def create_link(self, node_uuid: str, node_type: str, created_by: str, password: str = None) -> dict:
        """
        공유 링크 생성
        - token: uuid4 hex (32자)
        - password가 있으면 SHA-256 해시 저장
        - 중복 허용 (동일 노드에 여러 링크 생성 가능)
        """
        token = uuid.uuid4().hex
        password_hash = hashlib.sha256(password.encode()).hexdigest() if password else None
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.create"),
            (token, node_uuid, node_type, password_hash, created_by)
        )
        return {"token": token}

    def get_by_token(self, token: str) -> dict:
        """토큰으로 공유 링크 조회. 없으면 None 반환."""
        return self.db.fetch_one(
            self.sq.load_sql("file_forge.json", "share_link.get_by_token"),
            (token,)
        )

    def verify_password(self, link: dict, password: str) -> bool:
        """비밀번호 검증. password_hash가 None이면 항상 True."""
        if link["password_hash"] is None:
            return True
        return hashlib.sha256(password.encode()).hexdigest() == link["password_hash"]

    def get_user_links(self, user_id: str) -> list:
        """사용자가 생성한 모든 공유 링크 조회."""
        return self.db.fetch_all(
            self.sq.load_sql("file_forge.json", "share_link.get_by_user"),
            (user_id,)
        )

    def delete_link(self, token: str, user_id: str) -> None:
        """공유 링크 삭제. 본인이 만든 링크만 삭제 가능."""
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.delete"),
            (token, user_id)
        )

    def delete_by_node(self, node_uuid: str) -> None:
        """노드 삭제 시 연관된 공유 링크 일괄 삭제."""
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.delete_by_node"),
            (node_uuid,)
        )