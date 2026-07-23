"""Session management endpoints (fileforge.default.0004 T2).

The route handlers are awaited directly with an injected `(user_id, sid)` tuple rather than
driven through a TestClient: mounting the app would boot `config`'s DB and Redis singletons,
which is exactly what these tests exist to avoid (see conftest).
"""

import asyncio

import pytest
from fastapi import HTTPException


def _run(coro):
    return asyncio.run(coro)


def _seed(store, sids, user="u1"):
    for i, sid in enumerate(sids):
        store.create_session(
            user,
            f"refresh-{sid}",
            device_label=f"device-{sid}",
            client_type="test-agent",
            ip_display="203.0.113.9",
            sid=sid,
            now=1000 + i,
        )


def test_list_returns_own_sessions_newest_first_with_current_flagged(login_stack):
    _seed(login_stack.store, ["old", "new"])

    result = _run(login_stack.api.list_sessions(session=("u1", "old")))

    assert [s["sid"] for s in result["sessions"]] == ["new", "old"]
    assert result["current_sid"] == "old"
    assert result["session_unavailable"] is False
    assert [s["is_current"] for s in result["sessions"]] == [False, True]


def test_list_tells_pre_session_callers_to_sign_in_again(login_stack):
    """A token minted before this feature has no sid; D0003 §6 keeps it working."""
    _seed(login_stack.store, ["a"])

    result = _run(login_stack.api.list_sessions(session=("u1", None)))

    assert result == {"sessions": [], "current_sid": None, "session_unavailable": True}


def test_revoke_ends_only_the_named_session(login_stack):
    _seed(login_stack.store, ["a", "b"])

    result = _run(login_stack.api.revoke_session("b", session=("u1", "a")))

    assert result == {"revoked": 1, "was_current": False}
    assert login_stack.store.is_session_alive("u1", "a") is True
    assert login_stack.store.is_session_alive("u1", "b") is False


def test_revoking_own_session_reports_was_current(login_stack):
    _seed(login_stack.store, ["a"])

    result = _run(login_stack.api.revoke_session("a", session=("u1", "a")))

    assert result == {"revoked": 1, "was_current": True}
    assert login_stack.store.is_session_alive("u1", "a") is False


def test_another_accounts_session_is_indistinguishable_from_a_missing_one(login_stack):
    """404 either way, and the target must survive (D0003 §7.4)."""
    _seed(login_stack.store, ["mine"], user="u1")
    _seed(login_stack.store, ["theirs"], user="u2")

    with pytest.raises(HTTPException) as foreign:
        _run(login_stack.api.revoke_session("theirs", session=("u1", "mine")))
    with pytest.raises(HTTPException) as missing:
        _run(login_stack.api.revoke_session("no-such-sid", session=("u1", "mine")))

    assert foreign.value.status_code == missing.value.status_code == 404
    assert foreign.value.detail == missing.value.detail == "session_not_found"
    assert login_stack.store.is_session_alive("u2", "theirs") is True


def test_revoke_others_keeps_the_caller(login_stack):
    _seed(login_stack.store, ["a", "b", "c"])

    result = _run(login_stack.api.revoke_other_sessions(session=("u1", "b")))

    assert result == {"revoked": 2}
    assert [s["sid"] for s in login_stack.store.list_sessions("u1")] == ["b"]


def test_revoke_others_is_a_no_op_when_alone(login_stack):
    _seed(login_stack.store, ["a"])

    assert _run(login_stack.api.revoke_other_sessions(session=("u1", "a"))) == {"revoked": 0}
    assert login_stack.store.is_session_alive("u1", "a") is True


@pytest.mark.parametrize(
    "call",
    [
        lambda api: api.revoke_session("a", session=("u1", None)),
        lambda api: api.revoke_other_sessions(session=("u1", None)),
    ],
)
def test_mutations_require_a_session_bearing_token(login_stack, call):
    """Listing degrades gracefully for pre-session tokens; terminating cannot — there is no
    'this session' to keep, so revoke-others would sign the caller out of everything."""
    _seed(login_stack.store, ["a"])

    with pytest.raises(HTTPException) as exc:
        _run(call(login_stack.api))

    assert exc.value.status_code == 401
    assert exc.value.detail == "session_required"
    assert login_stack.store.is_session_alive("u1", "a") is True
