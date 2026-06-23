#!/usr/bin/env python3
"""FileForge Dev test user creation script.

[WARNING] This tool is for development/testing only. Do not use in production!

Usage:
    python create_dev_user.py
    python create_dev_user.py --email admin@test.local --password secret123 --storage storage
    python create_dev_user.py --count 5
    python create_dev_user.py --role admin --email admin@test.local
    python create_dev_user.py --storage mystore
    python create_dev_user.py --list
    python create_dev_user.py --delete admin@test.local
    python create_dev_user.py --token admin@test.local

Defaults:
    email   : dev{N}@fileforge.local  (N = 1, 2, ...)
    password: devpass123
    role    : user
    storage : (first existing storage, or none)
"""

import os
import sys
import argparse
import uuid
from datetime import datetime, timedelta, timezone

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)
sys.path.insert(0, BASE_DIR)

# ==========================================
# Load .env (lazy init)
# ==========================================
_config_loaded = False
db_instance = None
settings = None
_adapt_query = None

def _load_config():
    """Lazy-load config and db."""
    global _config_loaded, db_instance, settings, _adapt_query
    if _config_loaded:
        return

    # Load .env first
    try:
        from dotenv import load_dotenv
        load_dotenv(os.path.join(BASE_DIR, ".env"))
    except ImportError:
        # Manual parsing if python-dotenv is not installed
        env_path = os.path.join(BASE_DIR, ".env")
        if os.path.exists(env_path):
            with open(env_path, encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        k, _, v = line.partition("=")
                        os.environ.setdefault(k.strip(), v.strip())

    # Import config
    try:
        from config import settings as _settings, db as _db, adapt_query as _aq
        settings = _settings
        db_instance = _db.db_instance
        _adapt_query = _aq
    except Exception as e:
        print(f"[!] Failed to load FileForge config: {e}")
        print("    Make sure .env is configured properly.")
        sys.exit(1)

    _config_loaded = True


def q(sql: str) -> str:
    """Adapt SQLite-style '?' placeholders in raw SQL to the configured DB driver
    (pymysql/psycopg use '%s'). Without this, this script only works on SQLite and
    silently fails to create storages/users on MySQL/PostgreSQL."""
    _load_config()
    return _adapt_query(sql)

def get_secret_key() -> str | None:
    """Get SECRET_KEY from settings."""
    _load_config()
    return settings.SECRET_KEY

def get_access_token_expire_minutes() -> int:
    """Get ACCESS_TOKEN_EXPIRE_MINUTES from settings."""
    _load_config()
    return settings.ACCESS_TOKEN_EXPIRE_MINUTES

def get_db_instance():
    """Get database instance."""
    _load_config()
    return db_instance

# ==========================================
# Crypto and Token utilities
# ==========================================
_pwd_context = None
_jwt_available = False

def _init_crypto():
    """Initialize password context."""
    global _pwd_context
    if _pwd_context is not None:
        return
    try:
        from passlib.context import CryptContext
        _pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
    except ImportError:
        pass

def hash_password(pw: str) -> str:
    """Hash password using pbkdf2_sha256 or sha256 fallback."""
    _init_crypto()
    if _pwd_context is not None:
        return _pwd_context.hash(pw)
    else:
        import hashlib
        return hashlib.sha256(pw.encode()).hexdigest()

def make_token(user_id: str, email: str | None = None) -> str | None:
    """Generate an RS256 access token for the user, matching the server's issuance path
    (mailanchor.ui.0003 T1). Falls back to None if the key/crypto stack is unavailable."""
    try:
        from routers.login import jwt_keys
        data = {"sub": user_id, "type": "access"}
        if email:
            data["email"] = email
        return jwt_keys.sign_access(
            data, timedelta(minutes=get_access_token_expire_minutes())
        )
    except Exception:
        return None


# ==========================================
# Database helper functions
# ==========================================

def create_or_get_storage(storage_name: str, storage_type: str = "file") -> str | None:
    """Return storage_uuid for the given name, creating the storage if it doesn't exist.

    storage_type must be one of the values permitted by the storages CHECK/ENUM
    constraint (file/note/password/mail — see migration _INIT_009_storages_003).
    """
    try:
        db = get_db_instance()
        row = db.fetch_one(
            q("SELECT storage_uuid FROM storages WHERE storage_name = ?"),
            (storage_name,)
        )
        if row:
            return row["storage_uuid"]

        # Create a new storage entry
        storage_uuid = str(uuid.uuid4())
        # DB-portable timestamp: 'YYYY-MM-DD HH:MM:SS' is accepted by MySQL DATETIME,
        # PostgreSQL TIMESTAMP, and SQLite TEXT alike. isoformat() ('...T...+00:00')
        # is rejected by MySQL (error 1292, incorrect datetime value).
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        db.execute(
            q("INSERT INTO storages (storage_uuid, storage_name, storage_path, storage_type, status, created_at, modified_at) "
              "VALUES (?, ?, ?, ?, 'active', ?, ?)"),
            (storage_uuid, storage_name, f"/{storage_name}", storage_type, now, now)
        )
        print(f"[+] Storage created: '{storage_name}' (type: {storage_type}, uuid: {storage_uuid})")
        return storage_uuid
    except Exception as e:
        import traceback
        print(f"[!] Error creating/getting storage '{storage_name}': {e}")
        traceback.print_exc()
        return None


def get_anonymous_group_uuid() -> str | None:
    """Get the UUID of the Anonymous group, or None if it doesn't exist."""
    try:
        db = get_db_instance()
        result = db.fetch_one(
            q("SELECT group_uuid FROM groups WHERE group_name = ?"),
            ("Anonymous group",)
        )
        return result.get("group_uuid") if result else None
    except Exception:
        return None


def user_exists(user_id: str) -> bool:
    """Check if a user already exists."""
    try:
        db = get_db_instance()
        result = db.fetch_one(
            q("SELECT 1 FROM users WHERE user_id = ?"),
            (user_id,)
        )
        return result is not None
    except Exception as e:
        print(f"[!] Error checking user existence: {e}")
        return False


def create_user_record(
    user_id: str,
    password: str,
    user_name: str | None = None,
    email: str | None = None,
    role: str = "user",
    storage_name: str | None = None,
    storage_type: str = "file",
) -> dict | None:
    """
    Create a new user record in the database.

    Returns:
        dict with keys: user_id, user_uuid, password, email, role, token (if generated)
        None if creation failed
    """
    try:
        db = get_db_instance()

        # Generate UUIDs
        user_uuid = str(uuid.uuid4())
        group_uuid = get_anonymous_group_uuid()

        # Hash password
        hashed_password = hash_password(password)

        # Default user_name to user_id if not provided
        if user_name is None:
            user_name = user_id

        # Default email to user_id if not provided
        if email is None:
            email = user_id

        # Get current timestamp
        # DB-portable timestamp: 'YYYY-MM-DD HH:MM:SS' is accepted by MySQL DATETIME,
        # PostgreSQL TIMESTAMP, and SQLite TEXT alike. isoformat() ('...T...+00:00')
        # is rejected by MySQL (error 1292, incorrect datetime value).
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

        # Insert into users table
        db.execute(
            q("INSERT INTO users (group_uuid, user_uuid, user_id, user_name, password, email, role, created_at, modified_at) "
              "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"),
            (group_uuid, user_uuid, user_id, user_name, hashed_password, email, role, now, now)
        )

        # Link user to storage
        if storage_name:
            storage_uuid = create_or_get_storage(storage_name, storage_type)
        else:
            storage_row = db.fetch_one("SELECT storage_uuid FROM storages LIMIT 1")
            storage_uuid = storage_row["storage_uuid"] if storage_row else None

        if storage_uuid:
            existing = db.fetch_one(
                q("SELECT 1 FROM user_storages WHERE user_uuid = ? AND storage_uuid = ?"),
                (user_uuid, storage_uuid)
            )
            if not existing:
                db.execute(
                    q("INSERT INTO user_storages (user_uuid, storage_uuid, is_default) VALUES (?, ?, 1)"),
                    (user_uuid, storage_uuid)
                )
        else:
            print("[!] Warning: no storages found — user_storages record was not created.")

        # Generate token
        token = make_token(user_id, email)

        result = {
            "user_id": user_id,
            "user_uuid": user_uuid,
            "password": password,
            "email": email,
            "role": role,
        }

        if token:
            result["token"] = token

        return result

    except Exception as e:
        import traceback
        print(f"[!] Error creating user: {e}")
        traceback.print_exc()
        return None


def list_users() -> list[dict]:
    """List all users from the database."""
    try:
        db = get_db_instance()
        rows = db.fetch_all(
            "SELECT user_id, user_name, email, role, created_at FROM users ORDER BY created_at"
        )
        if rows is None:
            return []
        return [dict(r) for r in rows]
    except Exception as e:
        print(f"[!] Error listing users: {e}")
        return []


def delete_user(user_id: str) -> bool:
    """Delete a user from the database."""
    try:
        # First, check if user exists
        if not user_exists(user_id):
            return False

        db = get_db_instance()

        # Delete user
        db.execute(
            q("DELETE FROM users WHERE user_id = ?"),
            (user_id,)
        )
        return True
    except Exception as e:
        print(f"[!] Error deleting user: {e}")
        return False


# ==========================================
# Output helper
# ==========================================
def print_user(info: dict, idx: int = 1) -> None:
    """Pretty-print user creation info."""
    print(f"\n  [{idx}] user created")
    print(f"      email   : {info['user_id']}")
    print(f"      password: {info['password']}")
    print(f"      role    : {info['role']}")
    if "token" in info:
        token_preview = info["token"][:50] + "..." if len(info["token"]) > 50 else info["token"]
        print(f"      token   : {token_preview}")
    else:
        print(f"      token   : (not generated - SECRET_KEY may be missing)")


# ==========================================
# CLI
# ==========================================
def build_parser() -> argparse.ArgumentParser:
    """Build command-line argument parser."""
    p = argparse.ArgumentParser(
        description="FileForge dev test user creation (development/testing only)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument("--email", help="Email address to create (default: dev{N}@fileforge.local)")
    p.add_argument("--password", default="devpass123", help="Password (default: devpass123)")
    p.add_argument("--role", choices=["user", "admin"], default="user",
                   help="User role (default: user)")
    p.add_argument("--count", type=int, default=1, metavar="N",
                   help="Number of users to create - auto-generates dev1~devN if --email is not set (default: 1)")
    p.add_argument("--list", action="store_true", help="List all registered users")
    p.add_argument("--delete", metavar="EMAIL", help="Delete the specified user")
    p.add_argument("--token", metavar="EMAIL", help="Re-issue JWT token for an existing user")
    p.add_argument(
        "--storage", metavar="NAME",
        help="Storage name to assign to created users. "
             "If the storage does not exist it will be created automatically.",
    )
    p.add_argument(
        "--storage-type", choices=["file", "note", "password", "mail"], default="file",
        help="storage_type for a newly created storage (default: file). "
             "Only applies when --storage names a storage that does not yet exist.",
    )
    return p


def main() -> None:
    """Main entry point."""
    args = build_parser().parse_args()

    # Print warning: development only
    print("\n[WARNING] This is a development tool. Do not use in production!\n")

    # ---- List
    if args.list:
        users = list_users()
        if not users:
            print("No registered users.")
        else:
            print(f"{'Email':<40} {'Name':<25} {'Role':<8} {'Created at'}")
            print("-" * 90)
            for u in users:
                created_at = u["created_at"][:19] if u["created_at"] else "N/A"
                print(f"{u['user_id']:<40} {u['user_name']:<25} {u['role']:<8} {created_at}")
        return

    # ---- Delete
    if args.delete:
        if delete_user(args.delete):
            print(f"[OK] User deleted: {args.delete}")
        else:
            print(f"[!] User not found: {args.delete}")
        return

    # ---- Re-issue token
    if args.token:
        if user_exists(args.token):
            token = make_token(args.token)
            print(f"\n  email : {args.token}")
            if token:
                print(f"  token : {token[:50]}...")
            else:
                print(f"  token : (not generated - SECRET_KEY may be missing)")
        else:
            print(f"[!] User not found: {args.token}")
        return

    # ---- Create
    emails: list[str] = []
    if args.email:
        emails = [args.email]
    else:
        emails = [f"dev{i}@fileforge.local" for i in range(1, args.count + 1)]

    # Load config only when needed
    _load_config()
    db_type = settings.DB_TYPE.value if hasattr(settings.DB_TYPE, 'value') else settings.DB_TYPE
    print(f"[*] Creating dev test users (DB type: {db_type})")

    created, skipped = [], []

    for idx, email in enumerate(emails, start=1):
        if user_exists(email):
            skipped.append(email)
            print(f"  [skip] user already exists: {email}")
            continue

        info = create_user_record(
            user_id=email,
            password=args.password,
            email=email,
            role=args.role,
            storage_name=args.storage,
            storage_type=args.storage_type,
        )

        if info:
            created.append(info)
            print_user(info, idx - len(skipped))
        else:
            skipped.append(email)

    print(f"\nDone: {len(created)} created, {len(skipped)} skipped")

    secret_key = get_secret_key()
    if not secret_key:
        print("\n[WARNING] SECRET_KEY is not set in .env. JWT tokens may be invalid.")


if __name__ == "__main__":
    main()
