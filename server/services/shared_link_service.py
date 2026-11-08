"""Capability links with object authorization and versioned password hashing."""
import base64
import hashlib
import hmac
import secrets
import uuid
from fastapi import HTTPException
from config import adapt_query
from security.access import require_user_node
from security import abuse

_ITERATIONS = 600_000
_PREFIX = "p2$600000$"


def hash_share_password(password: str) -> str:
    if len(password) > 1024:
        raise HTTPException(422, "share_password_too_long")
    salt = secrets.token_bytes(16)
    # 128-bit salt + 192-bit derived key. The versioned representation is exactly
    # 64 ASCII characters: compatible with existing MySQL/Postgres VARCHAR(64).
    derived = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _ITERATIONS, dklen=24)
    return _PREFIX + base64.urlsafe_b64encode(salt + derived).decode().rstrip("=")


class SharedLinkService:
    def __init__(self, db_instance, sqloader):
        self.db = db_instance
        self.sq = sqloader

    def create_link(self, node_uuid: str, node_type: str, created_by: str, password: str = None) -> dict:
        node = require_user_node(created_by, node_uuid)
        if node_type != node["type"]:
            raise HTTPException(422, "invalid_node_type")
        abuse.limit("share-create", created_by, 30, 300)
        token = uuid.uuid4().hex
        password_hash = hash_share_password(password) if password else None
        self.db.execute_query(
            self.sq.load_sql("file_forge.json", "share_link.create"),
            (token, node_uuid, node["type"], password_hash, created_by),
        )
        return {"token": token}

    def get_by_token(self, token: str) -> dict | None:
        link = self.db.fetch_one(self.sq.load_sql("file_forge.json", "share_link.get_by_token"), (token,))
        if not link:
            return None
        # A link must not outlive the creator's right to share its target.
        try:
            node = require_user_node(link["created_by"], link["node_uuid"])
        except HTTPException as exc:
            if exc.status_code in {401, 403, 404}:
                return None
            raise
        if link["node_type"] != node["type"]:
            return None
        return link

    def verify_password(self, link: dict, password: str) -> bool:
        stored = link["password_hash"]
        if stored is None:
            return True
        abuse.limit("share-password", link["token"], 20, 300)
        if not isinstance(password, str) or len(password) > 1024:
            return False
        if stored.startswith(_PREFIX):
            try:
                raw = base64.b64decode(stored[len(_PREFIX):] + "==", altchars=b"-_", validate=True)
                if len(raw) != 40:
                    return False
                expected = hashlib.pbkdf2_hmac("sha256", password.encode(), raw[:16], _ITERATIONS, dklen=24)
                valid = hmac.compare_digest(raw[16:], expected)
                if valid:
                    abuse.clear_limit("share-password", link["token"])
                return valid
            except (ValueError, TypeError):
                return False
        # Preserve existing links; upgrade only after a successful legacy check.
        if len(stored) != 64 or any(c not in "0123456789abcdef" for c in stored):
            return False
        if not hmac.compare_digest(hashlib.sha256(password.encode()).hexdigest(), stored):
            return False
        upgraded = hash_share_password(password)
        self.db.execute_query(
            adapt_query("UPDATE shared_links SET password_hash = ? WHERE token = ? AND password_hash = ?"),
            (upgraded, link["token"], stored),
        )
        abuse.clear_limit("share-password", link["token"])
        return True

    def get_user_links(self, user_id: str) -> list:
        return self.db.fetch_all(self.sq.load_sql("file_forge.json", "share_link.get_by_user"), (user_id,))

    def delete_link(self, token: str, user_id: str) -> None:
        self.db.execute_query(self.sq.load_sql("file_forge.json", "share_link.delete"), (token, user_id))

    def delete_by_node(self, node_uuid: str) -> None:
        self.db.execute_query(self.sq.load_sql("file_forge.json", "share_link.delete_by_node"), (node_uuid,))
