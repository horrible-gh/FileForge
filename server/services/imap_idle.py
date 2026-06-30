"""IMAP IDLE (RFC 2177) low-level helpers over a stdlib ``imaplib`` connection.

R0001 / 0033 — D0004: the absorbed mail subsystem only ever *pulls* (the client
polls ``POST /mail/sync`` every ~10s). This module adds the missing primitive: it
puts an already-connected ``imaplib`` link into IDLE, waits for the server to
*push* a mailbox change (``* n EXISTS`` / ``* n RECENT`` / ``* n EXPUNGE``), and
leaves IDLE cleanly. The higher layer (``idle_manager``) turns that push into a
call to the existing incremental sync engine.

Why raw imaplib instead of a library: every existing IMAP path
(``services.imap_service`` / ``services.gmail_service``) is built on stdlib
``imaplib`` and is synchronous + thread-based (NR0003 §2.3). imaplib has no IDLE
helper, but it exposes the low-level pieces (``send`` / ``readline`` /
``_new_tag`` / ``socket()``) needed to drive IDLE by hand, so we add no new
dependency. aioimaplib/imapclient remain the documented scale path (NR0003 G2).

These helpers are deliberately small and connection-agnostic: they take the
``imaplib.IMAP4`` object that both ``IMAPService`` and ``GmailIMAPService`` keep
in ``.connection``.
"""

from __future__ import annotations

import socket
from typing import Optional

import imaplib

import LogAssist.log as logger


# RFC 2177: a server may drop an idle connection that idles "too long"; the spec
# advises clients to re-issue IDLE at least every 29 minutes. We never idle a
# single stretch beyond this — the manager re-enters IDLE before it elapses.
IDLE_MAX_SECONDS = 29 * 60


def supports_idle(connection: imaplib.IMAP4) -> bool:
    """Return True iff the server advertised the IDLE capability.

    imaplib caches CAPABILITY in ``.capabilities`` (an upper-cased set) after
    login; fall back to issuing CAPABILITY if it is somehow empty.
    """
    try:
        caps = getattr(connection, "capabilities", None)
        if not caps:
            typ, data = connection.capability()
            if typ == "OK" and data and data[0]:
                caps = tuple(data[0].upper().split())
        return any("IDLE" == c.upper() for c in (caps or ()))
    except Exception as exc:  # noqa: BLE001
        logger.warn(f"[IDLE] capability check failed: {exc}")
        return False


def idle_start(connection: imaplib.IMAP4) -> Optional[bytes]:
    """Enter IDLE. Returns the tag used (to match the closing tagged response).

    Sends ``<tag> IDLE`` and waits for the server's continuation line
    (``+ idling``). Raises on protocol/socket error so the caller can reconnect.
    """
    tag = connection._new_tag()  # noqa: SLF001 — imaplib's documented tag source
    connection.send(b"%s IDLE\r\n" % tag)
    # Server must answer with a continuation request ("+ ...") before it starts
    # pushing untagged updates. Anything else means IDLE was refused.
    resp = connection.readline()
    if not resp.startswith(b"+"):
        raise imaplib.IMAP4.error(
            f"IDLE not accepted: {resp!r}"
        )
    return tag


def idle_wait(connection: imaplib.IMAP4, timeout: float) -> bool:
    """Block up to ``timeout`` seconds for a mailbox-change push.

    Returns True as soon as the server pushes an untagged line that signals new
    activity (EXISTS / RECENT), False if ``timeout`` elapses with no such push
    (the caller should then DONE + re-IDLE for keepalive). EXPUNGE alone is
    treated as activity too, so a delete elsewhere still reconciles.

    The underlying socket's timeout is set so a quiet server does not block
    forever; the previous timeout is restored before returning.
    """
    sock = connection.socket()
    prev_timeout = sock.gettimeout()
    sock.settimeout(timeout)
    try:
        while True:
            try:
                line = connection.readline()
            except socket.timeout:
                return False
            if not line:
                # Connection closed by peer mid-IDLE.
                raise imaplib.IMAP4.abort("connection closed during IDLE")
            upper = line.upper()
            # Untagged mailbox-status pushes that mean "something changed".
            if b"EXISTS" in upper or b"RECENT" in upper or b"EXPUNGE" in upper:
                return True
            # Any other untagged line (e.g. "* OK Still here") is keepalive
            # chatter — keep waiting until timeout or a real change.
    finally:
        try:
            sock.settimeout(prev_timeout)
        except Exception:  # noqa: BLE001
            pass


def idle_done(connection: imaplib.IMAP4, tag: Optional[bytes]) -> None:
    """Leave IDLE: send DONE and drain until the matching tagged completion.

    Best-effort — a failure here is surfaced to the caller (via raise) only if
    the socket is dead, in which case a reconnect is warranted.
    """
    connection.send(b"DONE\r\n")
    if not tag:
        return
    # Read until the tagged response for our IDLE command arrives. Bound the
    # drain so a misbehaving server cannot wedge us forever.
    sock = connection.socket()
    prev_timeout = sock.gettimeout()
    sock.settimeout(IDLE_MAX_SECONDS)
    try:
        for _ in range(1000):
            line = connection.readline()
            if not line:
                raise imaplib.IMAP4.abort("connection closed awaiting DONE ack")
            if line.startswith(tag):
                return
    finally:
        try:
            sock.settimeout(prev_timeout)
        except Exception:  # noqa: BLE001
            pass
