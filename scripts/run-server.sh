#!/usr/bin/env bash
#
# Run the FileForge FastAPI backend (http://localhost:8000) for local development.
# Replaces the old run-server.bat / server/run.bat.
#
# Usage:
#   scripts/run-server.sh                 # host 0.0.0.0, port 8000, --reload
#   PORT=9000 scripts/run-server.sh       # override port
#   scripts/run-server.sh --no-reload     # disable autoreload
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/server"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
RELOAD="--reload"
[ "${1:-}" = "--no-reload" ] && RELOAD=""

# Prefer the project virtualenv created by setup.sh.
if [ -x .venv/bin/uvicorn ]; then
  UVICORN=(.venv/bin/uvicorn)
elif [ -x .venv/bin/python ]; then
  UVICORN=(.venv/bin/python -m uvicorn)
else
  echo "[run-server] .venv not found — run ./setup.sh first (falling back to system uvicorn)" >&2
  UVICORN=(uvicorn)
fi

echo "[run-server] starting uvicorn on ${HOST}:${PORT} ${RELOAD}"
exec "${UVICORN[@]}" app:app --host "$HOST" --port "$PORT" --workers 1 $RELOAD
