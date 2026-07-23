"""Session management endpoints (fileforge.default.0004 T2).

Lets a user see where their account is signed in and cut any of it off — the visible half of
the multi-session work whose storage layer landed in T1 (`session_store`). Three routes,
matching D0003 §7.4:

  GET    /sessions                — this account's sessions, most recently used first
  DELETE /sessions/{sid}          — end one session
  POST   /sessions/revoke-others  — end every session except the caller's

Every route authenticates through ``auth.current_session``, the payload-preserving dependency
added in T1, because a session route needs the caller's own ``sid`` and the 116-call-site
``verify_token`` only yields a user id (NR0005 F3).

Someone else's sid is treated exactly like a sid that never existed (404 + no state change),
so this endpoint cannot be used to probe whether a given session belongs to another account
(D0003 §7.4).
"""

from fastapi import APIRouter, Depends, HTTPException

from . import session_store
from .auth import current_session

router = APIRouter()


@router.get("")
@router.get("/")
async def list_sessions(session: tuple = Depends(current_session)):
    """Return this account's live sessions.

    ``sid`` is absent for tokens minted before this feature shipped. Rather than 401 such a
    caller (D0003 §6 keeps them working), the list comes back empty with a flag the client
    turns into "sign in again to see your devices" (D0003 §8 전환 기간 안내).
    """
    user_id, sid = session
    if not sid:
        return {"sessions": [], "current_sid": None, "session_unavailable": True}
    return {
        "sessions": session_store.list_sessions(user_id, current_sid=sid),
        "current_sid": sid,
        "session_unavailable": False,
    }


@router.delete("/{target_sid}")
async def revoke_session(target_sid: str, session: tuple = Depends(current_session)):
    """End one session.

    Ending your own session here is allowed and behaves like a logout: the UI offers no such
    button (D0003 §8 shows "현재 세션" instead), but refusing a request that expresses exactly
    what the endpoint does would be arbitrary, and the caller's very next request is rejected
    by the T1 gate either way. FlowGate answers 409 here (NR0005 §6); FileForge does not, and
    reports it via ``was_current`` so a client can route straight to the login screen.
    """
    user_id, sid = session
    if not sid:
        raise HTTPException(status_code=401, detail="session_required")

    if not session_store.revoke_session(user_id, target_sid):
        # Also the answer for another account's sid: `revoke_session` is scoped to this
        # user_id, so a foreign sid simply is not found here.
        raise HTTPException(status_code=404, detail="session_not_found")

    return {"revoked": 1, "was_current": target_sid == sid}


@router.post("/revoke-others")
async def revoke_other_sessions(session: tuple = Depends(current_session)):
    """End every session but this one."""
    user_id, sid = session
    if not sid:
        raise HTTPException(status_code=401, detail="session_required")
    return {"revoked": session_store.revoke_other_sessions(user_id, sid)}
