"""Actual login/TOTP route regression; infrastructure alone is replaced.

CI installs the production authentication dependencies. Minimal offline runtimes
without passlib/slowapi skip this module, not the authorization regression suite.
"""
import importlib
import sys
import types
import uuid
from datetime import timedelta
from unittest.mock import Mock

import pytest
from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient

pytest.importorskip("passlib")
pytest.importorskip("slowapi")

from test_security import MemoryRedis


@pytest.fixture
def routes(monkeypatch, tmp_path):
    fake = MemoryRedis()
    settings = types.SimpleNamespace(SECRET_KEY=uuid.uuid4().hex, RATE_LIMIT_LOGIN="1000/minute",
                                     ACCESS_TOKEN_EXPIRE_MINUTES=30, REFRESH_TOKEN_EXPIRE_DAYS=7)
    cfg = types.ModuleType("config")
    cfg.settings, cfg.redis_client = settings, fake
    cfg.adapt_query = lambda q: q
    cfg.db = types.SimpleNamespace(db_instance=Mock(), sqloader=Mock())
    cfg.db.db_instance.fetch_one.return_value = {"user_id":"alice", "user_uuid":"ua", "user_name":"Alice"}
    cfg.tfa = types.SimpleNamespace(is_enabled=Mock(return_value=True), verify=Mock(return_value=False),
                                    setup=Mock(), activate=Mock(return_value=True), disable=Mock(),
                                    regenerate_recovery_codes=Mock(return_value=["recovery"]))
    monkeypatch.setitem(sys.modules, "config", cfg)
    auth = types.ModuleType("routers.login.auth")
    async def verified():
        return "alice"
    async def current():
        return ("alice", "session-a")
    auth.verify_token, auth.current_session = verified, current
    monkeypatch.setitem(sys.modules, "routers.login.auth", auth)
    store = types.ModuleType("routers.login.session_store")
    for name in ["new_session_id", "create_session", "describe_request", "revoke_other_sessions", "drop_legacy_refresh"]:
        setattr(store, name, Mock())
    store.new_session_id.return_value = "session-a"
    store.describe_request.return_value = {}
    store.revoke_other_sessions.return_value = 2
    monkeypatch.setitem(sys.modules, "routers.login.session_store", store)
    import routers.login as package
    monkeypatch.setattr(package, "session_store", store, raising=False)
    # Real RS256 signing and validation; use an ephemeral key directory.
    monkeypatch.delenv("JWT_PRIVATE_KEY", raising=False)
    monkeypatch.delenv("JWT_PRIVATE_KEY_FILE", raising=False)
    monkeypatch.setenv("JWT_KEYS_DIR", str(tmp_path / "keys"))
    loaded = ["security.abuse", "routers.login.jwt_keys", "routers.login.login", "routers.totp"]
    for name in loaded:
        monkeypatch.delitem(sys.modules, name, raising=False)
    abuse = importlib.import_module("security.abuse")
    keys = importlib.import_module("routers.login.jwt_keys")
    monkeypatch.setattr(package, "jwt_keys", keys, raising=False)
    login = importlib.import_module("routers.login.login")
    totp = importlib.import_module("routers.totp")
    app = FastAPI()
    app.state.limiter = login.limiter
    app.include_router(login.router, prefix="/login")
    app.include_router(totp.router, prefix="/auth/totp")
    yield types.SimpleNamespace(client=TestClient(app), login=login, totp=totp, keys=keys,
                                cfg=cfg, store=store, redis=fake, abuse=abuse)
    for name in loaded:
        sys.modules.pop(name, None)
    import security
    if hasattr(security, "abuse"):
        delattr(security, "abuse")


def pending(routes):
    return routes.login.create_access_token({"sub":"alice", "totp_pending":True, "jti":uuid.uuid4().hex}, timedelta(minutes=5))


def test_totp_sixth_attempt_rejected_before_verifier(routes):
    token = pending(routes)
    for _ in range(5):
        response = routes.client.post("/login/totp/verify", json={"temp_token":token,"code":"000000"})
        assert response.status_code == 401
    response = routes.client.post("/login/totp/verify", json={"temp_token":token,"code":"000000"})
    assert response.status_code == 429
    assert routes.cfg.tfa.verify.call_count == 5
    assert not routes.store.create_session.called


def test_totp_budget_shared_across_new_pending_tokens(routes):
    for _ in range(5):
        routes.client.post("/login/totp/verify", json={"temp_token":pending(routes),"code":"000000"})
    response = routes.client.post("/login/totp/verify", json={"temp_token":pending(routes),"code":"000000"})
    assert response.status_code == 429


def test_pending_token_and_otp_cannot_create_two_sessions(routes):
    routes.cfg.tfa.verify.return_value = True
    token = pending(routes)
    first = routes.client.post("/login/totp/verify", json={"temp_token":token,"code":"123456"})
    assert first.status_code == 200, first.text
    assert "access_token" in first.json() and "refresh_token" in first.json()
    repeat = routes.client.post("/login/totp/verify", json={"temp_token":token,"code":"654321"})
    assert repeat.status_code == 401
    repeat = routes.client.post("/login/totp/verify", json={"temp_token":pending(routes),"code":"123456"})
    assert repeat.status_code == 401
    assert routes.store.create_session.call_count == 1


def test_enabled_totp_cannot_be_reset_by_setup(routes):
    response = routes.client.post("/auth/totp/setup")
    assert response.status_code == 409
    assert not routes.cfg.tfa.setup.called


def test_disabled_totp_setup_still_works(routes):
    routes.cfg.tfa.is_enabled.return_value = False
    routes.cfg.tfa.setup.return_value = {"secret":"s", "qr_image":"q", "recovery_codes":["r"]}
    response = routes.client.post("/auth/totp/setup")
    assert response.status_code == 200
    assert response.json()["secret"] == "s"


def test_totp_disable_replay_and_session_revocation(routes):
    routes.cfg.tfa.verify.return_value = True
    response = routes.client.post("/auth/totp/disable", json={"code":"123456"})
    assert response.status_code == 200
    assert response.json()["revoked_sessions"] == 2
    routes.store.revoke_other_sessions.assert_called_once_with("alice", "session-a")
    repeat = routes.client.post("/auth/totp/disable", json={"code":"123456"})
    assert repeat.status_code == 401
    assert routes.cfg.tfa.disable.call_count == 1


def test_refresh_tokens_differ_within_same_second(routes):
    first = routes.login.create_refresh_token({"sub":"alice","sid":"session-a"})
    second = routes.login.create_refresh_token({"sub":"alice","sid":"session-a"})
    assert first != second


def test_redis_failure_prevents_totp_session_issuance(routes):
    routes.redis.broken = True
    response = routes.client.post("/login/totp/verify", json={"temp_token":pending(routes),"code":"123456"})
    assert response.status_code == 503
    assert not routes.store.create_session.called


def test_password_login_without_totp_still_issues_session(routes, monkeypatch):
    routes.cfg.tfa.is_enabled.return_value = False
    monkeypatch.setattr(routes.login, "authenticate_user", Mock(return_value={"user_id":"alice","user_name":"Alice"}))
    response = routes.client.post("/login", data={"username":"alice","password":"not-a-real-password"})
    assert response.status_code == 200, response.text
    assert response.json()["token_type"] == "bearer"
    assert routes.store.create_session.call_count == 1


def test_password_login_with_totp_does_not_issue_session(routes, monkeypatch):
    monkeypatch.setattr(routes.login, "authenticate_user", Mock(return_value={"user_id":"alice"}))
    response = routes.client.post("/login", data={"username":"alice","password":"not-a-real-password"})
    assert response.status_code == 200, response.text
    assert response.json()["totp_required"] is True
    assert "access_token" not in response.json()
    assert not routes.store.create_session.called


def test_password_guessing_has_redis_account_budget(routes, monkeypatch):
    monkeypatch.setattr(routes.login, "authenticate_user", Mock(return_value=False))
    for _ in range(10):
        assert routes.client.post("/login", data={"username":"alice","password":"wrong"}).status_code == 400
    response = routes.client.post("/login", data={"username":"alice","password":"wrong"})
    assert response.status_code == 429
    assert routes.login.authenticate_user.call_count == 10
