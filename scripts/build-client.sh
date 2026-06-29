#!/usr/bin/env bash
#
# Build a release Flutter client artifact.
# Replaces the old client/build-android.bat.
#
# Usage:
#   scripts/build-client.sh                    # android apk, config/prod.json
#   scripts/build-client.sh web                # web release build
#   CONFIG=config/dev.json scripts/build-client.sh apk
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/client"

TARGET="${1:-apk}"
CONFIG="${CONFIG:-config/prod.json}"
[ -f "$CONFIG" ] || CONFIG="config/dev.json"

# B0001 / NR0003: a web release compiles SERVER_URL straight from $CONFIG into the
# bundle. If that base is localhost/loopback or plaintext http, the deployed https
# page blocks it via CSP "connect-src 'self' https: wss:" and login fails silently
# (status=null). Warn at the exact moment the trap would be baked in.
if [ "$TARGET" = "web" ] && [ -f "$CONFIG" ]; then
  server_url="$(grep -Eo '"SERVER_URL"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG" | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"
  if printf '%s' "$server_url" | grep -Eiq '://(localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2)([:/]|$)|^http://'; then
    printf '\033[1;33m[build-client]\033[0m WARNING: %s SERVER_URL=%s is localhost/plaintext-http. A deployed web build will be blocked by CSP (connect-src '\''self'\'' https: wss:) and login will fail (B0001). Set a public https origin (re-run setup or edit %s) before building for deploy.\n' "$CONFIG" "$server_url" "$CONFIG" >&2
  fi
fi

echo "[build-client] flutter build ${TARGET} --release (${CONFIG})"
exec flutter build "$TARGET" --release --dart-define-from-file="$CONFIG"
