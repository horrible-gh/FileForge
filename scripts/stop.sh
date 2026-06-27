#!/usr/bin/env bash
#
# Stop locally running FileForge backends.
# The mail subsystem is now served by the FastAPI app (:8000); there is no
# separate mail process.
#
# Usage:
#   scripts/stop.sh            # stop server (:8000)
#   scripts/stop.sh 8000       # stop whatever listens on the given port(s)
set -euo pipefail

PORTS=("$@")
[ ${#PORTS[@]} -eq 0 ] && PORTS=(8000)

if ! command -v lsof >/dev/null 2>&1; then
  echo "[stop] lsof not available; cannot resolve listeners on this system." >&2
  exit 1
fi

for port in "${PORTS[@]}"; do
  pids="$(lsof -ti "tcp:${port}" -s tcp:LISTEN 2>/dev/null || true)"
  if [ -n "$pids" ]; then
    echo "[stop] port ${port}: stopping PID(s) ${pids}"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
  else
    echo "[stop] port ${port}: nothing listening"
  fi
done
