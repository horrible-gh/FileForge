"""Test bootstrap for the server package.

`server/` had no automated tests before this change (NR0005 F19), and the reason is
structural: importing anything under `routers/` pulls in `config`, which builds the DB and
Redis singletons at import time. So the session-store tests stub `config` in `sys.modules`
*before* the module under test is imported, and hand it an in-memory Redis double. That keeps
the key-schema logic — LRU eviction, sliding TTL, per-session isolation — testable without a
database or a Redis server.
"""

import sys
import types
from pathlib import Path

import pytest

SERVER_ROOT = Path(__file__).resolve().parents[1]
if str(SERVER_ROOT) not in sys.path:
    sys.path.insert(0, str(SERVER_ROOT))


class FakeRedis:
    """Just enough Redis for session_store: strings, hashes, sorted sets, pipelines.

    Expiries are recorded rather than enforced; the tests assert on the recorded TTL, which is
    what the sliding-TTL requirement (D0003 §7.1) is actually about.
    """

    def __init__(self):
        self.strings = {}
        self.hashes = {}
        self.zsets = {}
        self.ttls = {}

    # -- strings ---------------------------------------------------------------
    def setex(self, key, ttl, value):
        self.strings[key] = value
        self.ttls[key] = ttl
        return True

    def get(self, key):
        return self.strings.get(key)

    def exists(self, key):
        return int(key in self.strings or key in self.hashes or key in self.zsets)

    def delete(self, key):
        found = 0
        for store in (self.strings, self.hashes, self.zsets):
            if key in store:
                del store[key]
                found = 1
        self.ttls.pop(key, None)
        return found

    def expire(self, key, ttl):
        self.ttls[key] = ttl
        return True

    # -- hashes ----------------------------------------------------------------
    def hset(self, key, mapping=None, **kwargs):
        self.hashes.setdefault(key, {}).update(mapping or {})
        return len(mapping or {})

    def hgetall(self, key):
        return dict(self.hashes.get(key, {}))

    # -- sorted sets -----------------------------------------------------------
    def zadd(self, key, mapping):
        self.zsets.setdefault(key, {}).update(mapping)
        return len(mapping)

    def zcard(self, key):
        return len(self.zsets.get(key, {}))

    def zscore(self, key, member):
        return self.zsets.get(key, {}).get(member)

    def zrem(self, key, member):
        removed = self.zsets.get(key, {}).pop(member, None)
        return 0 if removed is None else 1

    def _sorted(self, key):
        return sorted(self.zsets.get(key, {}).items(), key=lambda kv: kv[1])

    def zrange(self, key, start, end, withscores=False):
        items = self._sorted(key)
        sliced = items[start:] if end == -1 else items[start:end + 1]
        return sliced if withscores else [m for m, _ in sliced]

    def zrevrange(self, key, start, end, withscores=False):
        items = list(reversed(self._sorted(key)))
        sliced = items[start:] if end == -1 else items[start:end + 1]
        return sliced if withscores else [m for m, _ in sliced]

    # -- pipeline --------------------------------------------------------------
    def pipeline(self):
        return FakePipeline(self)


class FakePipeline:
    def __init__(self, client):
        self._client = client
        self._queue = []

    def __getattr__(self, name):
        def queue(*args, **kwargs):
            self._queue.append((name, args, kwargs))
            return self
        return queue

    def execute(self):
        results = [getattr(self._client, n)(*a, **k) for n, a, k in self._queue]
        self._queue = []
        return results


@pytest.fixture
def login_stack(monkeypatch):
    """Import the login package's session modules against a stubbed config + FakeRedis.

    `session_store` and `sessions` are loaded together from one stub so they share a single
    FakeRedis — importing them separately would give the router a different store than the
    tests write to.
    """
    import importlib

    fake = FakeRedis()
    stub = types.ModuleType("config")
    stub.redis_client = fake
    stub.settings = types.SimpleNamespace(
        REFRESH_TOKEN_EXPIRE_DAYS=7,
        SECRET_KEY="test-secret",
        ACCESS_TOKEN_EXPIRE_MINUTES=30,
    )
    stub.db = types.SimpleNamespace(db_instance=None, sqloader=None)
    monkeypatch.setitem(sys.modules, "config", stub)
    for cached in [m for m in sys.modules if m.startswith("routers.login.")]:
        monkeypatch.delitem(sys.modules, cached, raising=False)

    store = importlib.reload(importlib.import_module("routers.login.session_store"))
    api = importlib.reload(importlib.import_module("routers.login.sessions"))
    store.redis = fake  # convenience handle for assertions

    yield types.SimpleNamespace(store=store, api=api, redis=fake)

    for cached in [m for m in list(sys.modules) if m.startswith("routers.login.")]:
        sys.modules.pop(cached, None)


@pytest.fixture
def session_store(login_stack):
    return login_stack.store
