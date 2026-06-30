"""Mail timestamp timezone normalization (R0001 'that damn UTC' / 0025.0003-NR).

Storage convention: ``mail_messages.sent_date`` is a tz-NAIVE datetime whose
wall-clock IS UTC. The DB column (MySQL ``DATETIME`` / SQLite ``TEXT``) carries
no offset, so the timezone is fixed by THIS convention, not by the column. All
writers normalize to UTC before insert; all readers serialize with an explicit
``+00:00`` offset so the client can convert to the viewer's local zone.

Root cause this closes (see 0025.0003-NR): ``parsedate_to_datetime()`` yields a
tz-AWARE datetime, but the DB driver silently dropped the offset on insert
(storing the sender's local wall-clock) and the old ``_iso`` emitted an
offset-less string, so the Flutter client (``DateTime.parse(...).toLocal()``)
rendered the sender's wall-clock verbatim — UTC/GMT-stamped mail looked like
"UTC", ``-0700`` mail was off by its own amount. The error was non-uniform
because the offset was *discarded*, not converted.
"""
from datetime import datetime, timezone
import re

# ISO-8601 "date[ T]time" WITHOUT a trailing tz designator (no Z, no ±HH:MM).
_NAIVE_ISO_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?$")


def to_storage_utc(dt: datetime) -> datetime:
    """Normalize a parsed mail date to the storage convention (naive-UTC).

    aware -> converted to UTC, then tzinfo dropped.
    naive -> assumed to ALREADY be UTC (``parsedate_to_datetime`` returns naive
             for a ``-0000`` Date, whose RFC 5322 meaning is "UTC, local time
             unknown"; and our own fallbacks below are UTC).
    """
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc)
    return dt.replace(tzinfo=None)


def now_utc_naive() -> datetime:
    """UTC 'now' in storage convention (naive-UTC) — the missing/invalid-Date fallback.

    Replaces the old ``datetime.now()`` (server-local) fallback, which made the
    stored wall-clock depend on the host timezone.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)


def iso_utc(value) -> str:
    """Serialize a stored sent_date to ISO-8601 WITH an explicit UTC offset.

    Accepts a ``datetime`` (naive=UTC by convention, or aware) or a ``str`` (the
    form SQLite returns for a DATETIME column). ``None``/empty -> ``""``. A naive
    ISO string gains ``+00:00``; a string already bearing ``Z`` or an offset is
    returned unchanged. This is what lets the client's ``toLocal()`` actually work.
    """
    if value is None:
        return ""
    if isinstance(value, datetime):
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        else:
            value = value.astimezone(timezone.utc)
        return value.isoformat()
    s = str(value).strip()
    if not s:
        return ""
    if _NAIVE_ISO_RE.match(s):
        return s.replace(" ", "T") + "+00:00"
    return s
