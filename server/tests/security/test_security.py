"""Regression tests against the actual security modules and FastAPI boundary.

Uses isolated SQLite data and a Redis double locally. SECURITY_TEST_REDIS_URL
switches the same abuse/replay tests to a real disposable Redis (CI service).
Authentication identity is a dependency seam here, not a forged production JWT.
"""
import asyncio
import importlib
import os
import sqlite3
import sys
import types
import uuid
from pathlib import Path
from unittest.mock import Mock

import pytest
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from fastapi.testclient import TestClient

SERVER = Path(__file__).resolve().parents[2]


class Database:
    def __init__(self):
        self.conn = sqlite3.connect(":memory:", check_same_thread=False)
        self.conn.row_factory = sqlite3.Row
        self.conn.executescript("""
        CREATE TABLE users(user_uuid TEXT PRIMARY KEY, user_id TEXT, group_uuid TEXT);
        CREATE TABLE storages(storage_uuid TEXT PRIMARY KEY, status TEXT);
        CREATE TABLE user_storages(user_uuid TEXT, group_uuid TEXT, storage_uuid TEXT, mode TEXT, is_default INTEGER);
        CREATE TABLE nodes(node_uuid TEXT PRIMARY KEY, storage_uuid TEXT, type TEXT);
        CREATE TABLE shared_links(token TEXT, node_uuid TEXT, node_type TEXT, password_hash VARCHAR(64), created_by TEXT);
        INSERT INTO users VALUES ('ua','alice','ga'),('ub','bob','gb'),('ug','groupmate','ga');
        INSERT INTO storages VALUES ('sa','active'),('sb','active'),('read','active'),('write','active'),('off','inactive'),('team','active');
        INSERT INTO user_storages VALUES ('ua',NULL,'sa','rw',1),('ub',NULL,'sb','rw',1),('ua',NULL,'read','r',0),('ua',NULL,'write','w',0),('ua',NULL,'off','rw',0),('ug','ga','team','rw',0);
        INSERT INTO nodes VALUES ('a','sa','file'),('af','sa','folder'),('b','sb','file'),('bf','sb','folder'),('r','read','file'),('w','write','file'),('t','team','file');
        """)

    def fetch_one(self, query, params=()):
        row = self.conn.execute(query, params).fetchone()
        return dict(row) if row else None

    def fetch_all(self, query, params=()):
        return [dict(row) for row in self.conn.execute(query, params).fetchall()]

    def execute_query(self, query, params=()):
        self.conn.execute(query, params)
        self.conn.commit()


class MemoryRedis:
    def __init__(self):
        self.values = {}
        self.ttls = {}
        self.broken = False

    def eval(self, script, count, *args):
        if self.broken:
            raise OSError("unavailable")
        keys, seconds = args[:count], int(args[count])
        if "INCR" in script:
            key = keys[0]
            self.values[key] = self.values.get(key, 0) + 1
            self.ttls.setdefault(key, seconds)
            return [self.values[key], self.ttls[key]]
        if any(key in self.values for key in keys):
            return 0
        for key in keys:
            self.values[key] = 1
            self.ttls[key] = seconds
        return 1

    def delete(self, key):
        self.values.pop(key, None)
        self.ttls.pop(key, None)


@pytest.fixture
def stack(monkeypatch):
    if str(SERVER) not in sys.path:
        monkeypatch.syspath_prepend(str(SERVER))
    db = Database()
    redis = MemoryRedis()
    url = os.getenv("SECURITY_TEST_REDIS_URL")
    if url:
        from redis import Redis
        redis = Redis.from_url(url, decode_responses=True)
        redis.ping()
    cfg = types.ModuleType("config")
    cfg.db = types.SimpleNamespace(db_instance=db)
    cfg.adapt_query = lambda query: query
    cfg.redis_client = redis
    cfg.settings = types.SimpleNamespace(SECRET_KEY=uuid.uuid4().hex)
    auth = types.ModuleType("routers.login.auth")

    async def verify_token(request: Request):
        value = request.headers.get("authorization", "")
        if value != "Bearer test-alice":
            raise HTTPException(401, "not_authenticated")
        return "alice"

    auth.verify_token = verify_token
    monkeypatch.setitem(sys.modules, "config", cfg)
    monkeypatch.setitem(sys.modules, "routers.login.auth", auth)
    loaded = ["security.access", "security.abuse", "security.http", "services.shared_link_service"]
    for name in loaded:
        monkeypatch.delitem(sys.modules, name, raising=False)
    access, abuse, http, shares = [importlib.import_module(name) for name in loaded]
    yield types.SimpleNamespace(db=db, redis=redis, access=access, abuse=abuse,
                                http=http, shares=shares, auth=auth)
    db.conn.close()
    for name in loaded:
        sys.modules.pop(name, None)
    # Package attributes must not retain another test's config/client.
    import security
    for attr in ("access", "abuse", "http"):
        if hasattr(security, attr):
            delattr(security, attr)


def client_for(stack, method, path):
    app = FastAPI()
    touched = []

    async def handler():
        touched.append(True)
        return {"ok": True}

    app.add_api_route(path, handler, methods=[method],
                      dependencies=[Depends(stack.access.authorize_storage_request)])
    return TestClient(app), touched


def call_guard(stack, method, operation, data, *, auth=True):
    path = "/fileforge/storages/" + operation
    client, touched = client_for(stack, method, path)
    headers = {"Authorization": "Bearer test-alice"} if auth else {}
    if method in {"GET", "DELETE"}:
        response = client.request(method, path, params=data, headers=headers)
    elif operation == "upload":
        response = client.post(path, data=data, files={"file": ("note.txt", b"hello")}, headers=headers)
    else:
        response = client.request(method, path, json=data, headers=headers)
    return response, touched


@pytest.mark.parametrize("method,operation,data", [
    ("GET", "get_user_storages", {"user_uuid":"ua","group_uuid":"ga"}),
    ("GET", "get_directory_trees", {"storage_uuid":"sa"}),
    ("GET", "get_node_children", {"storage_uuid":"sa","node_uuid":"af"}),
    ("GET", "download", {"storage_uuid":"sa","node_uuid":"a"}),
    ("DELETE", "delete", {"storage_uuid":"sa","node_uuid":"a"}),
    ("PUT", "rename", {"storage_uuid":"sa","node_uuid":"a","new_name":"renamed.txt"}),
    ("PUT", "update_file_content", {"storage_uuid":"sa","node_uuid":"a","content":"hello"}),
    ("POST", "create_folder", {"storage_uuid":"sa","node_uuid":"af","folder_name":"new"}),
    ("POST", "upload", {"storage_uuid":"sa","parent_uuid":"af","user_uuid":"ua","group_uuid":"ga"}),
    ("POST", "bulk/download", {"node_uuids":["a","af"]}),
    ("POST", "bulk/delete", {"node_uuids":["a","af"]}),
    ("GET", "download", {"storage_uuid":"default","node_uuid":"a"}),
    ("GET", "download", {"storage_uuid":"team","node_uuid":"t"}),
])
def test_allowed_operations(stack, method, operation, data):
    response, touched = call_guard(stack, method, operation, data)
    assert response.status_code == 200, response.text
    assert touched == [True]


@pytest.mark.parametrize("method,operation,data", [
    ("GET", "get_user_storages", {"user_uuid":"ub"}),
    ("GET", "get_user_storages", {"user_uuid":"ua","group_uuid":"gb"}),
    ("GET", "get_directory_trees", {"storage_uuid":"sb"}),
    ("GET", "get_node_children", {"storage_uuid":"sb"}),
    ("GET", "get_node_children", {"storage_uuid":"sa","node_uuid":"bf"}),
    ("GET", "download", {"storage_uuid":"sa","node_uuid":"b"}),
    ("GET", "download", {"storage_uuid":"sb","node_uuid":"b","user_uuid":"ub"}),
    ("DELETE", "delete", {"storage_uuid":"sa","node_uuid":"b"}),
    ("PUT", "rename", {"storage_uuid":"sa","node_uuid":"b","new_name":"n"}),
    ("PUT", "update_file_content", {"storage_uuid":"sa","node_uuid":"b"}),
    ("POST", "create_folder", {"storage_uuid":"sa","node_uuid":"bf","folder_name":"n"}),
    ("POST", "upload", {"storage_uuid":"sa","parent_uuid":"bf","user_uuid":"ua"}),
    ("POST", "bulk/download", {"node_uuids":["a","b"]}),
    ("POST", "bulk/delete", {"node_uuids":["a","b"]}),
    ("DELETE", "delete", {"storage_uuid":"read","node_uuid":"r"}),
    ("GET", "download", {"storage_uuid":"write","node_uuid":"w"}),
    ("GET", "get_node_children", {"storage_uuid":"off"}),
    ("GET", "future_endpoint", {"storage_uuid":"sa"}),
])
def test_denied_without_handler_side_effects(stack, method, operation, data):
    response, touched = call_guard(stack, method, operation, data)
    assert response.status_code == 403, response.text
    assert touched == []


@pytest.mark.parametrize("method,operation,data", [
    ("GET", "download", {"storage_uuid":"sa"}),
    ("POST", "bulk/delete", {"node_uuids":[]}),
    ("POST", "bulk/delete", {"node_uuids":"a"}),
    ("POST", "bulk/delete", {"node_uuids":["a"] * 501}),
    ("POST", "create_folder", {"storage_uuid":"sa","node_uuid":"a","folder_name":"n"}),
    ("PUT", "rename", {"storage_uuid":"sa","node_uuid":"a","new_name":"../escape"}),
])
def test_invalid_requests_never_reach_handler(stack, method, operation, data):
    response, touched = call_guard(stack, method, operation, data)
    assert response.status_code == 422
    assert touched == []


def test_unauthenticated_blocked(stack):
    response, touched = call_guard(stack, "GET", "download", {"storage_uuid":"sa","node_uuid":"a"}, auth=False)
    assert response.status_code == 401 and not touched


def test_duplicate_query_identity_rejected(stack):
    response, touched = call_guard(stack, "GET", "download", [("storage_uuid","sa"),("node_uuid","a"),("user_uuid","ua"),("user_uuid","ub")])
    assert response.status_code == 422 and not touched


def test_limiter_budget_and_retry_after(stack):
    for _ in range(5):
        stack.abuse.limit("test", "alice", 5, 300)
    with pytest.raises(HTTPException) as exc:
        stack.abuse.limit("test", "alice", 5, 300)
    assert exc.value.status_code == 429
    assert int(exc.value.headers["Retry-After"]) > 0
    stack.abuse.limit("test", "bob", 5, 300)


def test_limiter_fails_closed(stack, monkeypatch):
    monkeypatch.setattr(stack.abuse.redis_client, "eval", Mock(side_effect=OSError("secret redis password")))
    with pytest.raises(HTTPException) as exc:
        stack.abuse.limit("test", "alice", 5, 300)
    assert exc.value.status_code == 503
    assert "secret" not in exc.value.detail


def test_totp_and_pending_token_single_use(stack):
    stack.abuse.consume_totp("alice", "123456", "pending-1")
    for code, token in [("123456", "pending-2"), ("654321", "pending-1")]:
        with pytest.raises(HTTPException) as exc:
            stack.abuse.consume_totp("alice", code, token)
        assert exc.value.status_code == 401
    stack.abuse.consume_totp("bob", "123456", "pending-3")
    stack.abuse.consume_totp("alice", "654321", "pending-2")


def test_login_limit_case_normalization(stack):
    request = Request({"type":"http","headers":[],"client":("198.51.100.10",123)})
    for _ in range(10):
        stack.abuse.login_attempt(request, "Alice")
    with pytest.raises(HTTPException) as exc:
        stack.abuse.login_attempt(request, "alice")
    assert exc.value.status_code == 429
    stack.abuse.login_success("ALICE")
    stack.abuse.login_attempt(request, "alice")


def test_raw_proxy_header_does_not_change_limit_key(stack):
    request = Request({"type":"http","headers":[(b"x-forwarded-for",b"spoofed")],"client":("198.51.100.9",123)})
    assert stack.abuse.client_ip(request) == "198.51.100.9"


class Queries:
    def load_sql(self, _, key):
        return {
            "share_link.create":"INSERT INTO shared_links VALUES (?,?,?,?,?)",
            "share_link.get_by_token":"SELECT * FROM shared_links WHERE token = ?",
        }[key]


def test_new_share_password_is_salted_and_fits_legacy_column(stack):
    first = stack.shares.hash_share_password("correct")
    second = stack.shares.hash_share_password("correct")
    assert first != second and len(first) == 64 and first.startswith("p2$600000$")
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    assert svc.verify_password({"token":"x","password_hash":first}, "correct")
    assert not svc.verify_password({"token":"x","password_hash":first}, "wrong")


def test_legacy_share_hash_upgrades_only_after_correct_password(stack):
    import hashlib
    old = hashlib.sha256(b"correct").hexdigest()
    stack.db.execute_query("INSERT INTO shared_links VALUES (?,?,?,?,?)", ("legacy","a","file",old,"alice"))
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    link = svc.get_by_token("legacy")
    assert not svc.verify_password(link, "wrong")
    assert svc.get_by_token("legacy")["password_hash"] == old
    assert svc.verify_password(link, "correct")
    upgraded = svc.get_by_token("legacy")
    assert upgraded["password_hash"].startswith("p2$600000$")
    assert svc.verify_password(upgraded, "correct")


def test_share_ownership_and_revocation(stack):
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    with pytest.raises(HTTPException) as exc:
        svc.create_link("b", "file", "alice")
    assert exc.value.status_code == 403
    token = svc.create_link("a", "file", "alice")["token"]
    assert svc.get_by_token(token)
    stack.db.execute_query("DELETE FROM user_storages WHERE storage_uuid = 'sa'")
    assert svc.get_by_token(token) is None


def test_share_type_cannot_be_spoofed(stack):
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    with pytest.raises(HTTPException) as exc:
        svc.create_link("a", "folder", "alice")
    assert exc.value.status_code == 422


def test_correct_share_downloads_do_not_exhaust_password_budget(stack):
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    link = {"token":"many-downloads", "password_hash":stack.shares.hash_share_password("p")}
    for _ in range(22):
        assert svc.verify_password(link, "p")


def test_shared_password_bruteforce_rejected(stack):
    svc = stack.shares.SharedLinkService(stack.db, Queries())
    link = {"token":"password-target", "password_hash":"0" * 64}
    for _ in range(20):
        assert not svc.verify_password(link, "wrong")
    with pytest.raises(HTTPException) as exc:
        svc.verify_password(link, "wrong")
    assert exc.value.status_code == 429


def test_security_headers_preserve_streams_and_strip_proxy_spoof(stack):
    app = FastAPI()
    app.add_middleware(stack.http.SecurityHeadersMiddleware)
    @app.get("/")
    async def download(request: Request):
        assert "x-forwarded-for" not in request.headers
        assert "x-real-ip" not in request.headers
        return StreamingResponse(iter([b"one", b"two", b"three"]))
    response = TestClient(app).get("/", headers={"X-Forwarded-For":"spoofed","X-Real-IP":"spoofed"})
    assert response.content == b"onetwothree"
    assert response.headers["cache-control"] == "private, no-store"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert response.headers["x-content-type-options"] == "nosniff"


def test_production_router_registration_is_guarded():
    import ast
    main = ast.parse((SERVER / "routers" / "main.py").read_text())
    guarded = set()
    for node in ast.walk(main):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "include_router":
            arg = ast.unparse(node.args[0])
            for keyword in node.keywords:
                if keyword.arg == "dependencies" and "authorize_storage_request" in ast.unparse(keyword.value):
                    guarded.add(arg)
    assert guarded == {"storages.router", "bulk.router"}
    assert "debug-headers" not in (SERVER / "routers" / "main.py").read_text()
