#!/usr/bin/env bash
#
# Run the Flutter client in Chrome for local development.
# Replaces the old run-app-chrome.bat / client/run-chrome-dev.bat.
#
# Usage:
#   scripts/run-client.sh                 # chrome, web port 3031, config/dev.json
#   WEB_PORT=4152 scripts/run-client.sh   # override web port
#   CONFIG=config/prod.json scripts/run-client.sh
#   scripts/run-client.sh --clean         # flutter clean before running
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/client"

WEB_PORT="${WEB_PORT:-3031}"
CONFIG="${CONFIG:-config/dev.json}"

if [ "${1:-}" = "--clean" ]; then
  echo "[run-client] flutter clean"
  flutter clean
  flutter pub get
fi

echo "[run-client] flutter run -d chrome --web-port ${WEB_PORT} (${CONFIG})"
exec flutter run -d chrome --web-port "$WEB_PORT" --dart-define-from-file="$CONFIG"
