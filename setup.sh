#!/usr/bin/env bash
#
# FileForge — one-time setup (Linux / macOS).
#
# Prepares all three components for local development:
#   server/       FastAPI backend  (Python venv + dependencies + .env)
#   mail-server/  MailAnchor (Go)  (modules + .env + build)
#   client/       Flutter client   (packages + config/prod.json)
#
# Usage:
#   ./setup.sh                      # set up everything (interactive)
#   ./setup.sh server               # set up a single component (server|mail-server|client)
#   ./setup.sh --force              # reconfigure even if .env / config already exist (backs up the old file)
#   ./setup.sh --non-interactive    # accept all defaults, never prompt (CI / unmanned)
#   ./setup.sh --launchers-only     # only (re)generate the root run-server.sh / run-client.sh launchers
#   GOOGLE_CLIENT_ID=... ./setup.sh -y    # pre-seed any value via environment, skip its prompt
#
# This script COLLECTS the values needed to write each .env (SECRET_KEY, DB,
# Redis, Gmail OAuth, MailAnchor SecretStore, SMTP relay) by prompting for them, instead of copying a
# placeholder template.
#
# It also GENERATES the root run launchers — run-server.sh (FastAPI + MailAnchor)
# and run-client.sh (Flutter web) — so the project can be started straight from
# the repository root without opening scripts/. They are regenerated every run;
# set FILEFORGE_LAUNCHERS_ONLY=1 to (re)generate only the launchers and exit.
#
# When a .env / config already exists, an interactive run ASKS whether to
# reconfigure it (default: keep). Answer yes — or pass --force — and the old
# file is backed up under backups/<timestamp>/<relative-path> before the prompts
# run. A non-interactive run keeps existing files untouched (idempotent / CI-safe).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

info()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()   { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; }
have()  { command -v "$1" >/dev/null 2>&1; }

# --- argument parsing -------------------------------------------------------
INTERACTIVE=1
FORCE=0
target="all"
for arg in "$@"; do
  case "$arg" in
    -y|--yes|--non-interactive|--no-input)   INTERACTIVE=0 ;;
    -f|--force|--reconfigure)                FORCE=1 ;;
    --launchers-only|--launchers)            FILEFORGE_LAUNCHERS_ONLY=1 ;;
    all|server|mail-server|client)           target="$arg" ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) err "unknown argument '$arg'"; exit 2 ;;
  esac
done
# A non-tty stdin (piped/CI) can never answer prompts — fall back to defaults.
if [ ! -t 0 ]; then INTERACTIVE=0; fi
[ "$INTERACTIVE" -eq 1 ] || info "non-interactive mode — using defaults / pre-set environment values for every .env field."

# --- prompt helpers ---------------------------------------------------------
# ask  VAR "Question" "default"  -> sets VAR. Honors a pre-set env var of the
#                                   same name (skips the prompt) and the default
#                                   when non-interactive or the answer is blank.
ask() {
  local __var="$1" __q="$2" __def="${3:-}" __cur __ans
  eval "__cur=\${$__var:-__UNSET__}"
  if [ "$__cur" != "__UNSET__" ] && [ -n "$__cur" ]; then
    info "$__q -> using pre-set \$$__var"; return 0
  fi
  if [ "$INTERACTIVE" -eq 0 ]; then eval "$__var=\$__def"; return 0; fi
  if [ -n "$__def" ]; then
    read -r -p "  $__q [$__def]: " __ans || __ans=""
  else
    read -r -p "  $__q: " __ans || __ans=""
  fi
  eval "$__var=\${__ans:-\$__def}"
}
# ask_secret VAR "Question"  -> like ask, no echo, no default shown.
ask_secret() {
  local __var="$1" __q="$2" __cur __ans
  eval "__cur=\${$__var:-__UNSET__}"
  if [ "$__cur" != "__UNSET__" ] && [ -n "$__cur" ]; then
    info "$__q -> using pre-set \$$__var"; return 0
  fi
  if [ "$INTERACTIVE" -eq 0 ]; then eval "$__var=\"\""; return 0; fi
  read -r -s -p "  $__q (input hidden, blank = none): " __ans || __ans=""
  echo
  eval "$__var=\$__ans"
}
gen_secret() {
  if have openssl; then openssl rand -hex 32
  elif have python3; then python3 -c 'import secrets;print(secrets.token_hex(32))'
  else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}

# backup_file PATH -> copies PATH to backups/<timestamp>/<relative-path> so
# reconfiguration never destroys the previous values or scatters .bak files.
backup_file() {
  local __p="$1" __ts __abs __rel __b __d
  __ts="$(date +%Y%m%d%H%M%S 2>/dev/null || echo bak)"
  __abs="$(cd "$(dirname "$__p")" && pwd -P)/$(basename "$__p")"
  case "$__abs" in
    "$ROOT_DIR"/*) __rel="${__abs#"$ROOT_DIR"/}" ;;
    *) err "Refusing to back up a file outside the repository root: $__abs"; return 1 ;;
  esac
  __b="$ROOT_DIR/backups/$__ts/$__rel"
  __d="$(dirname "$__b")"
  mkdir -p "$__d"
  cp "$__p" "$__b" && info "backed up existing file -> $__b"
}
# maybe_configure PATH LABEL -> returns 0 if we should (re)collect & write.
#   - missing file                  -> collect (return 0)
#   - --force                       -> back up, then collect (return 0)
#   - non-interactive + exists      -> keep, skip prompts (return 1)
#   - interactive + exists          -> ASK; yes backs up & collects, no keeps
# This is what guarantees an interactive run still PROMPTS when a .env/config
# already exists instead of silently skipping every question.
maybe_configure() {
  local __path="$1" __label="${2:-$1}" __ans
  if [ ! -e "$__path" ]; then return 0; fi
  if [ "$FORCE" -eq 1 ]; then
    info "$__label exists — reconfiguring (--force)"; backup_file "$__path"; return 0
  fi
  if [ "$INTERACTIVE" -eq 0 ]; then
    info "$__label already exists — keeping it (non-interactive)"; return 1
  fi
  read -r -p "  $__label already exists. Reconfigure it (re-enter all values)? [y/N]: " __ans || __ans=""
  case "$__ans" in
    y|Y|yes|YES) backup_file "$__path"; return 0 ;;
    *) info "keeping existing $__label"; return 1 ;;
  esac
}

# Gmail OAuth is shared by both server/ and mail-server/. Collect once.
GMAIL_COLLECTED=0
collect_gmail() {
  [ "$GMAIL_COLLECTED" -eq 0 ] || return 0
  GMAIL_COLLECTED=1
  if [ "$INTERACTIVE" -eq 1 ]; then
    echo
    info "Gmail OAuth (optional — leave blank to skip; /accounts/oauth/authorize then returns 503)."
  fi
  ask        GOOGLE_CLIENT_ID     "Gmail OAuth client ID"     ""
  ask_secret GOOGLE_CLIENT_SECRET "Gmail OAuth client secret"
  ask        GOOGLE_REDIRECT_URI  "Gmail OAuth redirect URI"  "http://localhost:8090/api/v1/accounts/oauth/callback"
}

collect_smtp() {
  if [ "$INTERACTIVE" -eq 1 ]; then
    echo
    info "Outbound SMTP relay (optional for Gmail OAuth; required for non-OAuth/password account sending)."
  fi
  ask        MAILANCHOR_SMTP_HOST     "SMTP relay host"     ""
  ask        MAILANCHOR_SMTP_PORT     "SMTP relay port"     "587"
  ask        MAILANCHOR_SMTP_USER     "SMTP relay username" ""
  ask_secret MAILANCHOR_SMTP_PASSWORD "SMTP relay password"
}

collect_mail_secret_key() {
  : "${MAILANCHOR_SECRET_ENCRYPTION_KEY:=}"
  if [ -z "$MAILANCHOR_SECRET_ENCRYPTION_KEY" ]; then MAILANCHOR_SECRET_ENCRYPTION_KEY="$(gen_secret)"; fi
  [ "$INTERACTIVE" -eq 1 ] && ask MAILANCHOR_SECRET_ENCRYPTION_KEY "MailAnchor OAuth SecretStore encryption key" "$MAILANCHOR_SECRET_ENCRYPTION_KEY"
}

setup_server() {
  info "server/ — FastAPI backend"
  cd "$ROOT_DIR/server"

  local py=""
  if have python3; then py=python3; elif have python; then py=python; else
    err "Python 3.10+ not found on PATH. Install it and re-run."; return 1
  fi

  if [ ! -d .venv ]; then
    info "creating virtualenv (.venv)"
    "$py" -m venv .venv
  fi
  info "installing Python dependencies"
  ./.venv/bin/python -m pip install --upgrade pip >/dev/null
  ./.venv/bin/python -m pip install -r requirements.txt

  if maybe_configure ".env" "server/.env"; then
    info "collecting values for server/.env"
    # SECRET_KEY: default is a freshly generated random key (never the placeholder).
    : "${SECRET_KEY:=}"
    if [ -z "$SECRET_KEY" ]; then SECRET_KEY="$(gen_secret)"; fi
    [ "$INTERACTIVE" -eq 1 ] && ask SECRET_KEY "App SECRET_KEY" "$SECRET_KEY"

    ask DB_TYPE "Database type (sqlite|mysql|postgresql)" "sqlite"
    case "$DB_TYPE" in
      mysql|postgresql)
        ask        DB_HOST     "DB host"     "localhost"
        ask        DB_PORT     "DB port"     "$([ "$DB_TYPE" = mysql ] && echo 3306 || echo 5432)"
        ask        DB_USER     "DB user"     "fileforge"
        ask_secret DB_PASSWORD "DB password"
        ask        DB_DATABASE "DB name"     "fileforge"
        DB_PATH="" ;;
      *) DB_TYPE="sqlite"; DB_PATH="./fileforge.db"
         DB_HOST="localhost"; DB_PORT=0; DB_USER=""; DB_PASSWORD=""; DB_DATABASE="fileforge" ;;
    esac

    ask        REDIS_HOST     "Redis host" "localhost"
    ask        REDIS_PORT     "Redis port" "6379"
    ask_secret REDIS_PASSWORD "Redis password"

    collect_gmail

    info "writing server/.env"
    {
      echo "ALLOWED_ORIGIN=*"
      echo "SECRET_KEY=${SECRET_KEY}"
      echo "ACCESS_TOKEN_EXPIRE_MINUTES=30"
      echo "CONTEXT=/fileforge"
      echo "JWT_KEYS_DIR=./keys"
      echo "JWT_ISSUER=fileforge"
      echo "JWT_AUDIENCE=mailanchor"
      echo "DB_TYPE=${DB_TYPE}"
      echo "DB_PATH=${DB_PATH:-}"
      echo "DB_HOST=${DB_HOST:-}"
      echo "DB_PORT=${DB_PORT:-0}"
      echo "DB_USER=${DB_USER:-}"
      echo "DB_PASSWORD=${DB_PASSWORD:-}"
      echo "DB_DATABASE=${DB_DATABASE:-fileforge}"
      echo "DB_SCHEMA="
      echo "RATE_LIMIT_DEFAULT=1000/hour"
      echo "RATE_LIMIT_LOGIN=50/minute"
      echo "RATE_LIMIT_UPLOAD=1200/minute"
      echo "RATE_LIMIT_DOWNLOAD=1200/minute"
      echo "REDIS_HOST=${REDIS_HOST:-localhost}"
      echo "REDIS_PORT=${REDIS_PORT:-6379}"
      echo "REDIS_DB=0"
      echo "REDIS_PASSWORD=${REDIS_PASSWORD:-}"
      echo "REDIS_SSL=false"
      echo "GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}"
      echo "GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}"
      echo "GOOGLE_REDIRECT_URI=${GOOGLE_REDIRECT_URI:-}"
    } > .env
  fi
  cd "$ROOT_DIR"
}

setup_mail_server() {
  info "mail-server/ — MailAnchor (Go)"
  if ! have go; then warn "Go toolchain not found — skipping mail-server. Install Go and re-run."; return 0; fi
  cd "$ROOT_DIR/mail-server"

  if maybe_configure ".env" "mail-server/.env"; then
    info "collecting values for mail-server/.env"
    ask MAILANCHOR_ADDR "MailAnchor listen address" ":8090"
    collect_mail_secret_key
    collect_smtp
    collect_gmail
    info "writing mail-server/.env"
    {
      echo "MAILANCHOR_ENV=development"
      echo "MAILANCHOR_ADDR=${MAILANCHOR_ADDR:-:8090}"
      echo "MAILANCHOR_DB_PATH=./mailanchor.db"
      echo "MAILANCHOR_SECRET_ENCRYPTION_KEY=${MAILANCHOR_SECRET_ENCRYPTION_KEY:-}"
      echo "ALLOWED_ORIGIN=http://localhost:3031,http://127.0.0.1:3031,http://localhost:4152,http://127.0.0.1:4152"
      echo "MAILANCHOR_SMTP_HOST=${MAILANCHOR_SMTP_HOST:-}"
      echo "MAILANCHOR_SMTP_PORT=${MAILANCHOR_SMTP_PORT:-587}"
      echo "MAILANCHOR_SMTP_USER=${MAILANCHOR_SMTP_USER:-}"
      echo "MAILANCHOR_SMTP_PASSWORD=${MAILANCHOR_SMTP_PASSWORD:-}"
      echo "MAILANCHOR_FILEFORGE_JWT_PUBKEY_FILE=../server/keys/jwt_public.pem"
      echo "MAILANCHOR_FILEFORGE_ISSUER=fileforge"
      echo "MAILANCHOR_FILEFORGE_AUDIENCE=mailanchor"
      echo "GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}"
      echo "GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}"
      echo "GOOGLE_REDIRECT_URI=${GOOGLE_REDIRECT_URI:-}"
    } > .env
  fi

  info "downloading Go modules"
  go mod download
  info "building mailanchord"
  go build -o mailanchord ./cmd/mailanchord
  cd "$ROOT_DIR"
}

setup_client() {
  info "client/ — Flutter client"
  if ! have flutter; then warn "Flutter SDK not found — skipping client. Install Flutter and re-run."; return 0; fi
  cd "$ROOT_DIR/client"

  if maybe_configure "config/prod.json" "client/config/prod.json"; then
    info "collecting values for client/config/prod.json"
    ask SERVER_URL      "FileForge server URL"   "http://localhost:8000/fileforge"
    ask MAIL_SERVER_URL "MailAnchor server URL"  "http://localhost:8090/api/v1"
    ask SHARE_BASE_URL  "Public share base URL"  "http://localhost:3000"
    info "writing client/config/prod.json"
    cat > config/prod.json <<JSON
{
  "SERVER_URL": "${SERVER_URL}",
  "MAIL_SERVER_URL": "${MAIL_SERVER_URL}",
  "SHARE_BASE_URL": "${SHARE_BASE_URL}",
  "LOG_LEVEL": "warn",
  "LOG_CONSOLE": "false",
  "LOG_FILE": "true"
}
JSON
  fi

  info "fetching Flutter packages"
  flutter pub get
  cd "$ROOT_DIR"
}

# write_run_launchers -> generate the root-level run launchers so the user can
# start each stack straight from the repo root after setup, without opening
# scripts/ to decide what to run. Server and client get separate launchers
# (R0001: keep the server/client split). Regenerated on every setup run; these
# files are git-ignored (build artifacts).
write_run_launchers() {
  info "generating root run launchers (run-server.sh, run-client.sh)"

  cat > "$ROOT_DIR/run-server.sh" <<'EOF'
#!/usr/bin/env bash
# === GENERATED BY setup.sh - DO NOT EDIT (regenerated on every setup run) ===
# Start the FileForge server stack: FastAPI (:8000) + MailAnchor Go (:8090).
# Ctrl+C stops both child processes.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
pids=()
cleanup() {
  trap - INT TERM EXIT
  for pid in "${pids[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT
echo "[run-server] starting FileForge FastAPI backend ..."
"$ROOT_DIR/scripts/run-server.sh" &
pids+=("$!")
echo "[run-server] starting MailAnchor Go backend ..."
"$ROOT_DIR/scripts/run-mail-server.sh" &
pids+=("$!")
echo "[run-server] server stack is running. Press Ctrl+C to stop both services."
while true; do
  running="$(jobs -pr | wc -l | tr -d ' ')"
  if [ "$running" -lt "${#pids[@]}" ]; then
    status=0
    for pid in "${pids[@]}"; do
      if ! jobs -pr | grep -qx "$pid"; then
        wait "$pid" || status="$?"
        echo "[run-server] child process $pid exited with status $status"
        exit "$status"
      fi
    done
  fi
  sleep 1
done
EOF
  chmod +x "$ROOT_DIR/run-server.sh"

  cat > "$ROOT_DIR/run-client.sh" <<'EOF'
#!/usr/bin/env bash
# === GENERATED BY setup.sh - DO NOT EDIT (regenerated on every setup run) ===
# Start the FileForge Flutter client (delegates to scripts/run-client.sh).
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT_DIR/scripts/run-client.sh" "$@"
EOF
  chmod +x "$ROOT_DIR/run-client.sh"

  info "wrote run-server.sh and run-client.sh to the repository root."
}

# Launchers are generated first so they exist even if a later component step fails.
# Set FILEFORGE_LAUNCHERS_ONLY=1 to regenerate just the launchers and stop here.
write_run_launchers
if [ "${FILEFORGE_LAUNCHERS_ONLY:-0}" = "1" ]; then
  info "root run launchers generated; skipping component setup (FILEFORGE_LAUNCHERS_ONLY=1)."
  exit 0
fi

case "$target" in
  all)         setup_server; setup_mail_server; setup_client ;;
  server)      setup_server ;;
  mail-server) setup_mail_server ;;
  client)      setup_client ;;
  *) err "unknown target '$target' (expected: all | server | mail-server | client)"; exit 2 ;;
esac

info "done."
info "Next: start the stacks from the repo root: ./run-server.sh (FastAPI + MailAnchor) and ./run-client.sh (Flutter web)."
info "Note: the server needs a reachable Redis instance (see server/.env REDIS_HOST)."
