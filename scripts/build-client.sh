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

echo "[build-client] flutter build ${TARGET} --release (${CONFIG})"
exec flutter build "$TARGET" --release --dart-define-from-file="$CONFIG"
