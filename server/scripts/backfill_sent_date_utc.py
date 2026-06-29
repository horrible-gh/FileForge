"""Backfill mail_messages.sent_date to the naive-UTC storage convention.

R0001 '그놈의 UTC' / 0025.0003-NR: legacy rows stored the sender's local
wall-clock with the Date-header offset DISCARDED (the driver dropped tzinfo on
insert). The code fix (sync.to_storage_utc) only affects NEW mail, so existing
rows must be recomputed from the stored .eml — whose ``Date:`` header still
carries the original offset.

This re-reads each message's .eml, parses ``Date:`` with parsedate_to_datetime,
normalizes to naive-UTC (to_storage_utc), and UPDATEs only rows whose stored
value actually differs. Idempotent: a second run finds stored == recomputed and
changes nothing. Rows with no .eml / no Date header are left untouched.

Run from the server/ directory:  python scripts/backfill_sent_date_utc.py [--apply]
Without --apply it is a dry run (reports what would change, writes nothing).
"""
import email
import os
import sys
from email.utils import parsedate_to_datetime

# Allow "from routers.mail..." when run as a script from server/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import db  # noqa: E402
from routers.mail.compat import _resolve_body_path  # noqa: E402
from util.mail_time import to_storage_utc  # noqa: E402

db_instance = db.db_instance

_FMT = "%Y-%m-%d %H:%M:%S"


def _stored_key(value) -> str:
    """Normalize a stored sent_date (datetime or str) to 'YYYY-MM-DD HH:MM:SS'."""
    if value is None:
        return ""
    try:
        return value.strftime(_FMT)  # datetime
    except AttributeError:
        s = str(value).strip().replace("T", " ")
        # drop any offset/fractional the column might carry, keep to seconds
        return s[:19]


def main(apply: bool) -> int:
    rows = db_instance.fetch_all(
        "SELECT message_uuid, sent_date, body_file_path FROM mail_messages"
    ) or []
    total = len(rows)
    changed = 0
    no_file = 0
    no_date = 0
    examined = 0
    for r in rows:
        bfp = _resolve_body_path(r.get("body_file_path"))
        if not bfp:
            no_file += 1
            continue
        try:
            with open(bfp, "rb") as fh:
                raw = fh.read()
        except OSError:
            no_file += 1
            continue
        examined += 1
        try:
            msg = email.message_from_bytes(raw)
            date_header = msg.get("Date")
            if not date_header:
                no_date += 1
                continue
            new_dt = to_storage_utc(parsedate_to_datetime(date_header))
        except Exception as exc:  # noqa: BLE001
            print(f"[skip] {r['message_uuid']}: date parse failed: {exc}")
            continue
        new_key = new_dt.strftime(_FMT)
        old_key = _stored_key(r.get("sent_date"))
        if new_key != old_key:
            changed += 1
            if changed <= 8:
                print(f"[{'apply' if apply else 'dry'}] {r['message_uuid']}  "
                      f"{old_key!r} -> {new_key!r}  (Date: {date_header.strip()[:40]!r})")
            if apply:
                db_instance.execute_query(
                    "UPDATE mail_messages SET sent_date = %s WHERE message_uuid = %s",
                    (new_dt, r["message_uuid"]),
                )
    if apply:
        db_instance.commit()
    print(f"\ntotal={total} examined={examined} no_file={no_file} no_date={no_date} "
          f"{'updated' if apply else 'would_update'}={changed}")
    return 0


if __name__ == "__main__":
    main(apply="--apply" in sys.argv)
