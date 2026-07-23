"""Session store behaviour (fileforge.default.0004 T1).

Covers the D0003 §9 verification points that live entirely in the store: per-session
isolation, immediate revocation, LRU eviction at the cap, sliding TTL, and the last-used
throttle. Endpoint-level checks (two-device login, transition from pre-session tokens) belong
with the session API in T2.
"""


def _create(store, user="u1", label="dev", sid=None, now=1000.0):
    return store.create_session(
        user,
        f"refresh-token-{sid or label}",
        device_label=label,
        client_type="test-agent",
        ip_display="203.0.113.9",
        sid=sid,
        now=now,
    )


def test_two_sessions_are_independent(session_store):
    """The whole point: a second device's login must not disturb the first."""
    sid_a, _ = _create(session_store, sid="a", now=1000)
    sid_b, _ = _create(session_store, sid="b", now=1001)

    assert session_store.is_session_alive("u1", sid_a)
    assert session_store.is_session_alive("u1", sid_b)
    assert session_store.get_refresh_token("u1", sid_a) != session_store.get_refresh_token("u1", sid_b)


def test_revoking_one_session_leaves_the_other_alive(session_store):
    _create(session_store, sid="a", now=1000)
    _create(session_store, sid="b", now=1001)

    assert session_store.revoke_session("u1", "a") is True
    assert session_store.is_session_alive("u1", "a") is False
    assert session_store.get_refresh_token("u1", "a") is None
    assert session_store.is_session_alive("u1", "b") is True


def test_revoking_an_unknown_session_reports_no_op(session_store):
    """A stranger's sid and a nonexistent sid must be indistinguishable (D0003 §7.4)."""
    assert session_store.revoke_session("u1", "never-existed") is False


def test_revoke_others_keeps_the_calling_session(session_store):
    for i in range(3):
        _create(session_store, sid=f"s{i}", now=1000 + i)

    assert session_store.revoke_other_sessions("u1", "s1") == 2
    assert [s["sid"] for s in session_store.list_sessions("u1")] == ["s1"]


def test_over_limit_login_evicts_least_recently_used(session_store):
    for i in range(session_store.MAX_SESSIONS_PER_USER):
        _create(session_store, sid=f"s{i}", now=1000 + i)

    _, evicted = _create(session_store, sid="new", now=2000)

    assert evicted == ["s0"]  # oldest last-used
    assert session_store.is_session_alive("u1", "s0") is False
    assert session_store.is_session_alive("u1", "new") is True
    assert len(session_store.list_sessions("u1")) == session_store.MAX_SESSIONS_PER_USER


def test_rotation_slides_every_session_key_ttl(session_store):
    """Without this a daily-used device dies 7 days after its first login (NR0005 F10-b)."""
    _create(session_store, sid="a", now=1000)
    session_store.redis.ttls["sessions:u1"] = 5  # simulate a nearly-expired key
    session_store.redis.ttls["session:u1:a"] = 5

    session_store.rotate_refresh_token("u1", "a", "rotated", now=2000)

    ttl = session_store.SESSION_TTL_SECONDS
    assert session_store.redis.ttls["sessions:u1"] == ttl
    assert session_store.redis.ttls["session:u1:a"] == ttl
    assert session_store.redis.ttls["session_refresh:u1:a"] == ttl
    assert session_store.get_refresh_token("u1", "a") == "rotated"
    assert session_store.list_sessions("u1")[0]["last_used_at"] == 2000


def test_last_used_touch_is_throttled(session_store):
    _create(session_store, sid="a", now=1000)

    assert session_store.check_and_touch("u1", "a", now=1000 + 10) is True
    assert session_store.redis.zscore("sessions:u1", "a") == 1000  # under the throttle: no write

    assert session_store.check_and_touch("u1", "a", now=1000 + session_store.LAST_USED_THROTTLE_SECONDS) is True
    assert session_store.redis.zscore("sessions:u1", "a") == 1000 + session_store.LAST_USED_THROTTLE_SECONDS


def test_touching_a_revoked_session_reports_dead(session_store):
    _create(session_store, sid="a", now=1000)
    session_store.revoke_session("u1", "a")

    assert session_store.check_and_touch("u1", "a", now=1100) is False


def test_list_is_newest_used_first_and_flags_the_current_session(session_store):
    _create(session_store, sid="old", label="PC", now=1000)
    _create(session_store, sid="new", label="Phone", now=2000)

    listed = session_store.list_sessions("u1", current_sid="old")

    assert [s["sid"] for s in listed] == ["new", "old"]
    assert listed[1]["is_current"] is True
    assert listed[0]["device_label"] == "Phone"
    assert listed[0]["ip_display"] == "203.0.113.9"


def test_list_survives_metadata_that_expired_early(session_store):
    """The account session list is the tie-breaker, not the metadata hash (D0003 §7.2)."""
    _create(session_store, sid="a", now=1000)
    session_store.redis.delete("session:u1:a")

    listed = session_store.list_sessions("u1")

    assert [s["sid"] for s in listed] == ["a"]
    assert listed[0]["device_label"] == "Unknown device"
    assert listed[0]["created_at"] == 1000


def test_client_supplied_device_name_wins_over_user_agent(session_store):
    class Req:
        headers = {"x-device-name": "  Shin's Laptop  ", "user-agent": "Mozilla/5.0 (Windows NT 10.0)"}
        client = type("C", (), {"host": "10.0.0.5"})()

    described = session_store.describe_request(Req())

    assert described["device_label"] == "Shin's Laptop"
    assert described["ip_display"] == "10.0.0.5"


def test_forwarded_for_left_most_hop_is_the_client(session_store):
    class Req:
        headers = {"x-forwarded-for": "198.51.100.7, 10.0.0.1", "user-agent": "okhttp (Android 14)"}
        client = type("C", (), {"host": "10.0.0.1"})()

    described = session_store.describe_request(Req())

    assert described["ip_display"] == "198.51.100.7"
    assert described["device_label"] == "Android"
