"""Backfill mail_messages.preview with clean, charset-correct snippets.

B0001 / 0018: previews are generated once at sync time and stored in the DB.
Legacy rows hold either raw HTML markup (HTML-only mail, no text/plain part) or
charset mojibake / ESC sequences (EUC-KR / ISO-2022-JP decoded as utf-8). The
code fix in sync.parse_email_message only affects *new* mail, so existing rows
must be re-derived from the stored .eml.

This re-reads each message's .eml, re-extracts the body with the correct charset,
rebuilds the preview via the same make_preview() the sync path now uses, and
UPDATEs only the rows whose preview actually changes. Idempotent; safe to re-run.

Run from the server/ directory:  python scripts/backfill_previews.py [--apply]
Without --apply it is a dry run (reports what would change, writes nothing).
"""
import os
import sys

# Allow "from routers.mail..." when run as a script from server/.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import db  # noqa: E402
from routers.mail.sync import parse_email_message  # noqa: E402
from routers.mail.compat import _resolve_body_path  # noqa: E402

db_instance = db.db_instance


def looks_broken(preview: str) -> bool:
    """Heuristic: raw markup or ESC/control-byte mojibake in the stored preview."""
    if not preview:
        return False
    if "<" in preview and (">" in preview or "<!--" in preview):
        return True
    if "\x1b" in preview:  # ISO-2022-JP escape sequences
        return True
    return False


def main(apply: bool) -> int:
    rows = db_instance.fetch_all(
        "SELECT message_uuid, preview, body_file_path FROM mail_messages"
    ) or []
    total = len(rows)
    changed = 0
    no_file = 0
    examined = 0
    for r in rows:
        bfp = _resolve_body_path(r.get("body_file_path"))
        if not bfp:
            no_file += 1
            continue
        examined += 1
        try:
            with open(bfp, "rb") as fh:
                raw = fh.read()
        except OSError:
            no_file += 1
            continue
        try:
            new_preview = parse_email_message(raw).get("preview", "")
        except Exception as exc:  # noqa: BLE001
            print(f"[skip] {r['message_uuid']}: parse failed: {exc}")
            continue
        old_preview = r.get("preview") or ""
        # Update when the regenerated preview differs AND is either non-empty or is
        # replacing a recognisably broken (raw markup / ESC) legacy value. The
        # latter clears raw HTML out of image/CSS-only mail that has no body text
        # (an empty snippet beats a wall of markup); a normal empty regen never
        # blanks an already-clean preview.
        if new_preview != old_preview and (new_preview.strip() or looks_broken(old_preview)):
            changed += 1
            if changed <= 5:
                # ASCII-safe: the console may be cp932 and cannot print CJK.
                def _safe(s):
                    return s[:80].encode("ascii", "backslashreplace").decode("ascii")
                print(f"[{'apply' if apply else 'dry'}] {r['message_uuid']}")
                print(f"    OLD: {_safe(old_preview)!r}")
                print(f"    NEW: {_safe(new_preview)!r}")
            if apply:
                db_instance.execute_query(
                    "UPDATE mail_messages SET preview = %s WHERE message_uuid = %s",
                    (new_preview, r["message_uuid"]),
                )
    if apply:
        db_instance.commit()
    print(f"\ntotal={total} examined={examined} no_file={no_file} "
          f"changed={'updated' if apply else 'would_update'}={changed}")
    return 0


if __name__ == "__main__":
    main(apply="--apply" in sys.argv)
