#!/usr/bin/env python3
"""Migrate mail artifacts into the storage that is DESIGNATED IN THE DB
(`storages` row with storage_type='mail', e.g. `C:\\storage\\mailanchor`) and
rewrite the stored DB paths to the resulting absolute location.
(fileforge.mailanchorpython.0021 / R0001, rev1)

Background
----------
The absorbed mail subsystem historically persisted every .eml body and attachment
under a hardcoded `./data/mails` directory. A first remediation moved them to a
config-only `./storage/mail` subtree — but that is STILL not the storage the
operator designated in the DB (`storages.storage_path`), so files never appeared
under e.g. `C:\\storage\\mailanchor` (review reject). config.mail_storage_base() now
resolves that DB-designated path per owning user, so newly-synced mail already lands
in the right place; this script relocates the pre-existing files (from `./data/mails`
or the interim `./storage/mail`) and rewrites `body_file_path` / `file_path` to the
new absolute location.

Resolution is data-driven: for every row we take the per-account suffix
(`{account}/messages/…` or `{account}/attachments/…`), resolve the destination base
via mail_storage_base(account_uuid=…) (= the DB-designated storage), and move the
physical file there.

Safety
------
* DRY-RUN by default: prints what *would* happen, touches nothing. Pass --apply.
* Idempotent: a row already pointing at an existing file under the designated base is
  skipped. Re-running after a completed migration is a no-op.
* Non-destructive move: copy2 then remove the source only after the copy verifies.
* The runtime read path (compat._resolve_body_path) re-anchors across the historical
  bases, so the app keeps working before, during, and after this run.

Usage
-----
    python scripts/migrate_mail_storage.py            # dry-run report
    python scripts/migrate_mail_storage.py --apply    # perform migration
"""
import os
import sys
import shutil
import argparse

# Allow running from the server package root (where config.py lives).
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from config import mail_storage_base, get_db_instance, adapt_query  # noqa: E402

SERVER_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Historical mail subtree roots, as they appear (normalized to '/') in stored paths.
KNOWN_BASES = ("data/mails", "storage/mail")


def _norm(p: str) -> str:
    return (p or "").replace("\\", "/")


def _suffix_after_known_base(stored: str):
    """Return (account, suffix_parts) if `stored` sits under a known historical base,
    else (None, None). suffix is `{account}/messages|attachments/.../file`."""
    norm = _norm(stored).lstrip("./")
    for base in KNOWN_BASES:
        if norm.startswith(base + "/"):
            suffix = norm[len(base) + 1:]
            parts = [s for s in suffix.split("/") if s]
            if parts:
                return parts[0], parts
    return None, None


def _resolve_existing(stored: str):
    """Resolve a stored path to an existing file: as-is, or anchored at server root."""
    cands = [stored]
    if not os.path.isabs(stored):
        cands.append(os.path.join(SERVER_ROOT, stored))
    for c in cands:
        if os.path.exists(c):
            return c
    return None


def _destination(account: str, suffix_parts: list) -> str:
    """Absolute destination for a row, under the DB-designated mail storage."""
    base = mail_storage_base(account_uuid=account)
    dest = os.path.join(base, *suffix_parts)
    if not os.path.isabs(dest):
        dest = os.path.join(SERVER_ROOT, dest)
    return os.path.normpath(dest)


def _migrate_table(table: str, col: str, key: str, apply: bool, report: list) -> tuple:
    db = get_db_instance()
    moved = 0
    rewritten = 0
    try:
        rows = db.fetch_all(
            adapt_query(f"SELECT {key}, {col} FROM {table} WHERE {col} IS NOT NULL"),
            (),
        )
    except Exception as exc:  # table may not exist on a given deployment
        report.append(f"[db] {table}: skipped ({exc})")
        return 0, 0

    for row in rows or []:
        stored = row[col] if isinstance(row, dict) else row[1]
        ident = row[key] if isinstance(row, dict) else row[0]
        if not stored:
            continue

        account, suffix_parts = _suffix_after_known_base(stored)
        if not account:
            # Already absolute / under the designated base — verify & skip.
            if _resolve_existing(stored):
                continue
            report.append(f"[db] {table}.{col}: UNRESOLVED (no known base) {stored}")
            continue

        dest = _destination(account, suffix_parts)
        src = _resolve_existing(stored)

        # Physical move (if needed).
        if os.path.exists(dest):
            if apply and src and os.path.abspath(src) != os.path.abspath(dest):
                os.remove(src)  # drop duplicate leftover at the old location
        elif src:
            report.append(f"  MOVE  {src}  ->  {dest}")
            moved += 1
            if apply:
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(src, dest)
                if os.path.exists(dest):
                    os.remove(src)
        else:
            report.append(f"  MISS  (no source)  {stored}")

        # DB rewrite to the absolute designated location.
        if _norm(dest) != _norm(stored):
            report.append(f"[db] {table}.{col}: {stored} -> {dest}")
            rewritten += 1
            if apply:
                db.execute_query(
                    adapt_query(f"UPDATE {table} SET {col} = ? WHERE {key} = ?"),
                    (dest, ident),
                )
    return moved, rewritten


def _cleanup_empty(report: list, apply: bool) -> None:
    for legacy in ("data/mails", "storage/mail"):
        d = os.path.join(SERVER_ROOT, *legacy.split("/"))
        if os.path.isdir(d):
            # remove empty leaf dirs bottom-up
            for root, dirs, files in os.walk(d, topdown=False):
                if not os.listdir(root):
                    if apply:
                        try:
                            os.rmdir(root)
                        except OSError:
                            pass
            if os.path.isdir(d) and not os.listdir(d):
                report.append(f"[fs] legacy tree now empty: {d}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="perform the migration (default: dry-run)")
    args = ap.parse_args()

    report: list = []
    report.append(f"designated mail base (no-account) = {mail_storage_base()!r}")
    report.append("--- mail_messages ---")
    m1, r1 = _migrate_table("mail_messages", "body_file_path", "message_uuid", args.apply, report)
    report.append("--- mail_attachments ---")
    m2, r2 = _migrate_table("mail_attachments", "file_path", "attachment_uuid", args.apply, report)
    _cleanup_empty(report, args.apply)

    mode = "APPLY" if args.apply else "DRY-RUN"
    print("\n".join(report))
    print(f"\n[{mode}] files moved: {m1 + m2}, db paths rewritten: {r1 + r2}")
    if not args.apply:
        print("(dry-run; re-run with --apply to perform the migration)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
