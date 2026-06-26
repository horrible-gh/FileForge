import uuid
import hashlib


class SharedLinkService:
    def __init__(self, db_instance, sqloader):
        self.db = db_instance
        self.sq = sqloader

    def create_link(self, node_uuid: str, node_type: str, created_by: str, password: str = None) -> dict:
        """
        Create a shared link
        - token: uuid4 hex (32text)
        - passwordtext translated text SHA-256 text save
        - Duplicates are allowed (Multiple links can be created for the same node)
        """
        token = uuid.uuid4().hex
        password_hash = hashlib.sha256(password.encode()).hexdigest() if password else None
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.create"),
            (token, node_uuid, node_type, password_hash, created_by)
        )
        return {"token": token}

    def get_by_token(self, token: str) -> dict:
        """Lookup a shared link by token. Return None when absent."""
        return self.db.fetch_one(
            self.sq.load_sql("file_forge.json", "share_link.get_by_token"),
            (token,)
        )

    def verify_password(self, link: dict, password: str) -> bool:
        """Password verification. Return True when password_hash is None."""
        if link["password_hash"] is None:
            return True
        return hashlib.sha256(password.encode()).hexdigest() == link["password_hash"]

    def get_user_links(self, user_id: str) -> list:
        """List every shared link created by the user."""
        return self.db.fetch_all(
            self.sq.load_sql("file_forge.json", "share_link.get_by_user"),
            (user_id,)
        )

    def delete_link(self, token: str, user_id: str) -> None:
        """Delete a shared link. Only links created by the user can be deleted."""
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.delete"),
            (token, user_id)
        )

    def delete_by_node(self, node_uuid: str) -> None:
        """Delete associated shared links when a node is deleted."""
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.delete_by_node"),
            (node_uuid,)
        )