#!/usr/bin/env bash
# Ensure we are running under bash even if invoked via sh or a non-bash shell
if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi
set -Eeuo pipefail

# How to run (full orchestration):
# sudo /opt/frappe-v16-setup/setup-orchestrator.sh -u frappe -p 'root_pwd' -s 'apps.localhost' -a 'admin_pwd' -d true -k "ssh-ed25519 AAAA... user@example.com"

# Must run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "This script must be run as root. Try: sudo $0"
  exit 1
fi

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_SCRIPT="$SCRIPT_DIR/root-system-setup.sh"
USER_SCRIPT="$SCRIPT_DIR/setup-frappe-app.sh"

# Logging
SCRIPT_BASENAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_STEM="${SCRIPT_BASENAME%.*}"
LOG_FILE="/tmp/${SCRIPT_STEM}-$(date +%Y-%m-%d).log"
touch "$LOG_FILE"
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}
fail() {
  log "ERROR: $*"
  exit 1
}
trap 'fail "Script failed at line $LINENO"' ERR

# Usage and args
usage() {
  cat <<USAGE
Usage: $0 [options]
  -u  Frappe system user (e.g., frappe)
  -p  MariaDB root password
  -s  Frappe site name (e.g., apps.localhost)
  -a  Frappe Administrator password
  -k  SSH public key to add for root (optional, quote the whole key)
  -d  Enable developer mode (true/false, default: false)
  -h, --help              Show this help and exit

Example:
  sudo $0 -u frappe -p 'root_pwd' -s 'apps.localhost' -a 'admin_pwd' -d true -k "ssh-ed25519 AAAA... user@example.com"
USAGE
}
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u) FRAPPE_APP_USER="$2"; shift 2 ;;
      -p) FRAPPE_DB_PASSWORD="$2"; shift 2 ;;
      -s) SITE_NAME="$2"; shift 2 ;;
      -a) APP_ADMIN_PASSWORD="$2"; shift 2 ;;
      -k) SSH_PUBLIC_KEY="$2"; shift 2 ;;
      -d) DEV_MODE="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
  done
}
parse_args "$@"

# Validate required args
FRAPPE_APP_USER="${FRAPPE_APP_USER:-}"
FRAPPE_DB_PASSWORD="${FRAPPE_DB_PASSWORD:-}"
SITE_NAME="${SITE_NAME:-}"
APP_ADMIN_PASSWORD="${APP_ADMIN_PASSWORD:-}"
DEV_MODE="${DEV_MODE:-false}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
[[ -z "${FRAPPE_APP_USER}" ]] && fail "FRAPPE_APP_USER is required. Use -u|--user."
[[ -z "${FRAPPE_DB_PASSWORD}" ]] && fail "FRAPPE_DB_PASSWORD is required. Use -p|--db-password."
[[ -z "${SITE_NAME}" ]] && fail "SITE_NAME is required. Use -s|--site."
[[ -z "${APP_ADMIN_PASSWORD}" ]] && fail "APP_ADMIN_PASSWORD is required. Use -a|--admin-password."

log "Executor: script=${SCRIPT_BASENAME} user=$(id -un) uid=$(id -u)"

# 1) Root phase
log "Running root phase: $ROOT_SCRIPT"
ROOT_ARGS=(-u "$FRAPPE_APP_USER")
if [[ -n "$SSH_PUBLIC_KEY" ]]; then
  ROOT_ARGS+=(-k "$SSH_PUBLIC_KEY")
fi
bash "$ROOT_SCRIPT" "${ROOT_ARGS[@]}"
log "Completed root phase."

# 2) User phase
log "Running user phase as $FRAPPE_APP_USER: $USER_SCRIPT"
# Ensure the user-phase script is executable and accessible
if [[ ! -x "$USER_SCRIPT" ]]; then
  chmod +x "$USER_SCRIPT"
fi
chown "$FRAPPE_APP_USER":"$FRAPPE_APP_USER" "$USER_SCRIPT" || true

sudo -E -u "$FRAPPE_APP_USER" env \
  HOME="/home/$FRAPPE_APP_USER" \
  "$USER_SCRIPT" \
    -u "$FRAPPE_APP_USER" \
    -p "$FRAPPE_DB_PASSWORD" \
    -s "$SITE_NAME" \
    -a "$APP_ADMIN_PASSWORD" \
    --dev "$DEV_MODE"
log "Completed user phase."

log "✅ Orchestrated setup completed successfully."

