#!/usr/bin/env bash
#
# Build and run the MailAnchor Go backend (mailanchord, http://localhost:8090).
# Replaces the old mail-server/run.bat.
#
# Loads mail-server/.env (falls back to mail-server/.env.sample), frees the
# listen port if a stale instance is holding it, rebuilds from source, and runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAIL_DIR="$ROOT_DIR/mail-server"
cd "$MAIL_DIR"

# Load environment (KEY=VALUE lines). Prefer .env, else the tracked sample.
ENV_FILE="$MAIL_DIR/.env"
[ -f "$ENV_FILE" ] || ENV_FILE="$MAIL_DIR/.env.sample"
if [ -f "$ENV_FILE" ]; then
  echo "[run-mail-server] loading env from $(basename "$ENV_FILE")"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

ADDR="${MAILANCHOR_ADDR:-:8090}"
PORT="${ADDR##*:}"; PORT="${PORT:-8090}"

# Free the port if a previous mailanchord (or anything else) is still listening.
if command -v lsof >/dev/null 2>&1; then
  PIDS="$(lsof -ti "tcp:${PORT}" -s tcp:LISTEN 2>/dev/null || true)"
  if [ -n "$PIDS" ]; then
    echo "[run-mail-server] port ${PORT} busy — stopping PID(s): ${PIDS}"
    # shellcheck disable=SC2086
    kill $PIDS 2>/dev/null || true
    sleep 1
  fi
fi

if [ -z "${GOOGLE_CLIENT_ID:-}${MAILANCHOR_OAUTH_GMAIL_CLIENT_ID:-}" ]; then
  echo "[run-mail-server] Gmail OAuth not configured — /accounts/oauth/authorize will return 503 (server still starts)."
fi
if [ -z "${MAILANCHOR_SMTP_HOST:-}" ]; then
  echo "[run-mail-server] SMTP relay not configured - Gmail OAuth send can still use XOAUTH2; non-OAuth/password send needs MAILANCHOR_SMTP_HOST."
fi

echo "[run-mail-server] building mailanchord ..."
go build -o mailanchord ./cmd/mailanchord

echo "[run-mail-server] starting mailanchord on ${ADDR} ..."
exec ./mailanchord
