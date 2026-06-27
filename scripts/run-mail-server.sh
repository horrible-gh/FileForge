#!/usr/bin/env bash
#
# [ABSORBED] The standalone MailAnchor server no longer exists.
#
# The mail server has been absorbed into the FileForge FastAPI backend as the
# "mail subsystem" (routes under /fileforge/mail/*, /fileforge/oauth/gmail).
# There is no separate Go backend (mailanchord) and no separate :8090 process
# anymore - mail-server/ is now pure Python and ships no .go sources or cmd/.
#
# This script is kept only so existing automation that still invokes
# scripts/run-mail-server.sh keeps working: it simply forwards to
# scripts/run-server.sh, which starts the single uvicorn app (default
# http://localhost:8000) that already includes the mail subsystem.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[run-mail-server] The MailAnchor backend was absorbed into the FileForge server." >&2
echo "[run-mail-server] There is no separate Go (mailanchord) build or :8090 process anymore." >&2
echo "[run-mail-server] Forwarding to run-server.sh - mail routes live at /fileforge/mail/* on the main app." >&2

exec "$SCRIPT_DIR/run-server.sh" "$@"
