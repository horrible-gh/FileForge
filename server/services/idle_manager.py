"""IMAP IDLE manager — server-side real-time mail receive (R0001 / 0033, D0004).

NR0003 found the absorbed mail subsystem has **no background worker**: mail only
arrives when the client polls ``POST /mail/sync`` (~10s, foreground + inbox only).
This manager closes that gap. On server startup it enumerates every
sync-enabled active account and supervises one daemon worker per account. Each
worker keeps a long-lived IMAP connection to the account's INBOX in IDLE
(``services.imap_idle``); when the mail server *pushes* a change it wakes the
**existing** incremental sync engine (``routers.mail.sync.sync_account_mails``),
which opens its own short-lived connection to fetch+store the new mail. The IDLE
link only waits — it never issues FETCH — so the two connections never interleave.

Design choices (per D0004 / NR0003):
- One worker = one daemon thread (the whole IMAP/sync stack is synchronous,
  thread-based — NR0003 G2). aioimaplib is the documented scale path.
- Connection lifetime is capped (CONNECTION_TTL) so a worker reconnects well
  before IDLE's 29-min ceiling AND refreshes the Gmail OAuth token (NR0003 G3).
- Reconnects use exponential backoff with jitter (NR0003 G6).
- Servers without the IDLE capability fall back to periodic sync (NR0003 §3).
- Sync calls go through the existing in-memory dedup guard so an IDLE-triggered
  sync never races a client-triggered one (NR0003 G9).
- Multi-worker (uvicorn --workers N) single-owner election is DEFERRED — the
  stack runs --workers 1 today (NR0003 G5); guarded only by the enable toggle.
"""

from __future__ import annotations

import asyncio
import random
import threading
import time
from typing import Dict, List, Optional

import imaplib

import LogAssist.log as logger
from config import settings, db

db_instance = db.db_instance
sqloader = db.sqloader


# Recycle a worker's IDLE connection before this many seconds elapse. Kept well
# under imap_idle.IDLE_MAX_SECONDS (29 min) so we satisfy the RFC 2177 re-IDLE
# advice AND pick up a freshly refreshed Gmail access token each cycle.
CONNECTION_TTL_SECONDS = 25 * 60
# Longest single IDLE wait before we DONE/re-IDLE for keepalive (a quiet server
# is checked for liveness this often). Always <= the remaining TTL.
IDLE_WAIT_SLICE_SECONDS = 5 * 60
# Reconnect backoff bounds (exponential, with jitter).
BACKOFF_BASE_SECONDS = 5
BACKOFF_MAX_SECONDS = 5 * 60
# Fallback (non-IDLE server) sync cadence.
FALLBACK_POLL_SECONDS = 60


class IdleManager:
    """Owns the lifecycle of all IDLE workers. One instance per process."""

    def __init__(self) -> None:
        self._stop = threading.Event()
        self._workers: Dict[str, threading.Thread] = {}
        self._bootstrap: Optional[threading.Thread] = None
        self._started = False

    # ── lifecycle ─────────────────────────────────────────────────────────────

    def start(self) -> None:
        """Begin supervising workers. Returns immediately (non-blocking).

        No-op when disabled by config or when running under pytest (so the test
        suite never opens real IMAP sockets). Enumeration + per-account worker
        spawn happen on a background thread so a slow/unreachable DB cannot delay
        server startup.
        """
        if self._started:
            return
        if not getattr(settings, "MAIL_IDLE_ENABLED", True):
            logger.info("[IDLE] disabled via MAIL_IDLE_ENABLED — not starting")
            return
        import os
        if "PYTEST_CURRENT_TEST" in os.environ:
            logger.info("[IDLE] pytest detected — manager not started")
            return
        self._started = True
        self._stop.clear()
        self._bootstrap = threading.Thread(
            target=self._run_bootstrap, name="idle-bootstrap", daemon=True
        )
        self._bootstrap.start()
        logger.info("[IDLE] manager started")

    def stop(self) -> None:
        """Signal all workers to exit and wait briefly for them to wind down."""
        if not self._started:
            return
        logger.info("[IDLE] manager stopping…")
        self._stop.set()
        # Daemon threads will die with the process; give graceful DONE/logout a
        # short window so we do not leave sockets half-open on a clean shutdown.
        for t in list(self._workers.values()):
            t.join(timeout=3)
        self._started = False
        logger.info("[IDLE] manager stopped")

    # ── bootstrap ─────────────────────────────────────────────────────────────

    def _run_bootstrap(self) -> None:
        try:
            accounts = self._enumerate_accounts()
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[IDLE] account enumeration failed: {exc}")
            return
        if not accounts:
            logger.info("[IDLE] no sync-enabled accounts — nothing to watch")
            return
        logger.info(f"[IDLE] supervising {len(accounts)} account(s)")
        for acc in accounts:
            if self._stop.is_set():
                break
            account_uuid = acc.get("account_uuid")
            user_uuid = acc.get("user_uuid")
            if not account_uuid or not user_uuid:
                continue
            t = threading.Thread(
                target=self._run_worker,
                args=(account_uuid, user_uuid, acc.get("account_type")),
                name=f"idle-{account_uuid[:8]}",
                daemon=True,
            )
            self._workers[account_uuid] = t
            t.start()

    def _enumerate_accounts(self) -> List[dict]:
        """All active accounts; sync_enabled filtered here for dialect safety."""
        rows = db_instance.fetch_all(
            sqloader.load_sql("mail_anchor.json", "idle.get_active_sync_accounts"),
            {},
        ) or []
        out = []
        for r in rows:
            # sync_enabled may be 1/0 (mysql/sqlite) or True/False (postgres);
            # default to enabled when the column is absent/NULL (matches the
            # compat trigger_sync default, NR0003 §2.2).
            if r.get("sync_enabled", 1) in (0, False, "0"):
                continue
            out.append(r)
        return out

    # ── per-account worker ────────────────────────────────────────────────────

    def _run_worker(self, account_uuid: str, user_uuid: str, account_type) -> None:
        backoff = BACKOFF_BASE_SECONDS
        while not self._stop.is_set():
            imap = None
            try:
                imap = self._open_connection(account_uuid, user_uuid)
                conn = imap.connection
                conn.select("INBOX", readonly=True)

                if not _supports_idle(conn):
                    logger.warn(
                        f"[IDLE] {account_uuid[:8]} server lacks IDLE — polling fallback"
                    )
                    self._fallback_poll(account_uuid, user_uuid)
                    backoff = BACKOFF_BASE_SECONDS
                    _safe_logout(imap)
                    continue

                logger.info(f"[IDLE] {account_uuid[:8]} entering IDLE on INBOX")
                self._idle_cycle(conn, account_uuid, user_uuid)
                # Clean TTL-driven recycle → reset backoff and reconnect.
                backoff = BACKOFF_BASE_SECONDS
                _safe_logout(imap)
            except Exception as exc:  # noqa: BLE001
                _safe_logout(imap)
                if self._stop.is_set():
                    break
                logger.warn(
                    f"[IDLE] {account_uuid[:8]} connection error: {exc} — "
                    f"reconnecting in ~{backoff}s"
                )
                # Backoff with jitter; interruptible by stop().
                jitter = random.uniform(0, backoff * 0.25)
                self._stop.wait(backoff + jitter)
                backoff = min(backoff * 2, BACKOFF_MAX_SECONDS)
        logger.info(f"[IDLE] {account_uuid[:8]} worker exiting")

    def _idle_cycle(self, conn, account_uuid: str, user_uuid: str) -> None:
        """Drive IDLE on one connection until its TTL elapses or stop is set."""
        from services import imap_idle

        deadline = time.monotonic() + CONNECTION_TTL_SECONDS
        while not self._stop.is_set():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return  # recycle the connection (fresh token, fresh socket)
            wait_for = min(IDLE_WAIT_SLICE_SECONDS, remaining)

            tag = imap_idle.idle_start(conn)
            try:
                changed = imap_idle.idle_wait(conn, wait_for)
            finally:
                imap_idle.idle_done(conn, tag)

            if changed and not self._stop.is_set():
                logger.info(f"[IDLE] {account_uuid[:8]} push received → sync")
                self._trigger_sync(account_uuid, user_uuid)

    def _fallback_poll(self, account_uuid: str, user_uuid: str) -> None:
        """Periodic sync for servers without IDLE; returns on stop/TTL."""
        deadline = time.monotonic() + CONNECTION_TTL_SECONDS
        while not self._stop.is_set() and time.monotonic() < deadline:
            self._trigger_sync(account_uuid, user_uuid)
            self._stop.wait(FALLBACK_POLL_SECONDS)

    def _trigger_sync(self, account_uuid: str, user_uuid: str) -> None:
        """Wake the existing incremental sync engine (its own connection).

        Goes through routers.mail.sync, which holds the in-memory dedup guard so
        an IDLE-triggered sync never collides with a client-triggered one
        (NR0003 G9). Failures are swallowed — a flaky sync must not kill the
        IDLE worker; the next push (or TTL recycle) retries.
        """
        try:
            from routers.mail.sync import sync_account_mails

            sync_account_mails(account_uuid, user_uuid, "INBOX")
        except Exception as exc:  # noqa: BLE001
            logger.error(f"[IDLE] {account_uuid[:8]} sync failed: {exc}")

    # ── connection building (mirrors sync.sync_account_mails, NR0003 §2.2) ─────

    def _open_connection(self, account_uuid: str, user_uuid: str):
        """Open + authenticate an IMAP connection for the account.

        Gmail accounts refresh their OAuth access token first (NR0003 G3); other
        accounts use the stored IMAP password. Returns the connected service
        object (``.connection`` is the imaplib link).
        """
        from util.crypto import encrypt_password, decrypt_password

        account = db_instance.fetch_one(
            sqloader.load_sql("mail_anchor.json", "get_account"),
            (account_uuid,),
        )
        if not account:
            raise RuntimeError("account not found")

        if account.get("account_type") == "gmail":
            from services.gmail_service import GmailIMAPService, GmailOAuthService

            refresh_token_encrypted = account.get("refresh_token_encrypted")
            if not refresh_token_encrypted:
                raise RuntimeError("gmail account needs re-auth (no refresh_token)")

            refresh_token = decrypt_password(
                settings.SECRET_KEY, user_uuid, refresh_token_encrypted
            )
            gmail_oauth = GmailOAuthService()
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                token_data = loop.run_until_complete(
                    gmail_oauth.refresh_access_token(refresh_token)
                )
            finally:
                loop.close()
            access_token = token_data["access_token"]

            # Persist the refreshed token (keeps client-triggered syncs cheap).
            try:
                encrypted_access = encrypt_password(
                    settings.SECRET_KEY, user_uuid, access_token
                )
                db_instance.execute_query(
                    sqloader.load_sql("mail_anchor.json", "gmail.update_access_token"),
                    {
                        "account_uuid": account_uuid,
                        "access_token_encrypted": encrypted_access,
                        "token_expires_in": token_data.get("expires_in", 3600),
                    },
                )
            except Exception as exc:  # noqa: BLE001
                logger.warn(f"[IDLE] {account_uuid[:8]} token persist failed: {exc}")

            imap = GmailIMAPService(account["email"], access_token)
        else:
            from services.imap_service import IMAPService

            imap_password = decrypt_password(
                settings.SECRET_KEY, user_uuid, account["imap_password_encrypted"]
            )
            imap = IMAPService(
                host=account["imap_host"],
                port=account["imap_port"],
                username=account["imap_username"],
                password=imap_password,
                use_ssl=account.get("imap_use_ssl", True),
            )

        result = imap.connect()
        if not result.get("success"):
            raise RuntimeError(f"IMAP connect failed: {result.get('message')}")
        return imap


def _supports_idle(conn) -> bool:
    from services import imap_idle

    return imap_idle.supports_idle(conn)


def _safe_logout(imap) -> None:
    if imap is None:
        return
    try:
        imap.disconnect()
    except Exception:  # noqa: BLE001
        pass


# Process-wide singleton used by the app startup/shutdown hooks.
manager = IdleManager()
