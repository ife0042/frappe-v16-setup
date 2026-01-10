#!/usr/bin/env bash
# Ensure we are running under bash even if invoked via sh or a non-bash shell
if [ -z "${BASH_VERSION:-}" ]; then
  exec /bin/bash "$0" "$@"
fi
set -Eeuo pipefail

# Must not run as root
if [[ "$EUID" -eq 0 ]]; then
  echo "Do not run this script as root. Switch to the target user first (e.g., sudo su - frappe)."
  exit 1
fi

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
  -d  Enable developer mode (true/false, default: false)
  -h, --help              Show this help and exit

Example:
  ./setup-user.sh -u frappe -p 'root_pwd' -s 'apps.localhost' -a 'admin_pwd' -d true
USAGE
}
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u) FRAPPE_APP_USER="$2"; shift 2 ;;
      -p) FRAPPE_DB_PASSWORD="$2"; shift 2 ;;
      -s) SITE_NAME="$2"; shift 2 ;;
      -a) APP_ADMIN_PASSWORD="$2"; shift 2 ;;
      -d) DEV_MODE="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $1"; echo; usage; exit 1 ;;
    esac
  done
}
parse_args "$@"

# Resolve and validate
FRAPPE_APP_USER="${FRAPPE_APP_USER:-}"
FRAPPE_DB_PASSWORD="${FRAPPE_DB_PASSWORD:-}"
SITE_NAME="${SITE_NAME:-}"
APP_ADMIN_PASSWORD="${APP_ADMIN_PASSWORD:-}"
DEV_MODE="${DEV_MODE:-false}"
[[ -z "${FRAPPE_APP_USER}" ]] && fail "FRAPPE_APP_USER is required. Use -u|--user."
[[ -z "${FRAPPE_DB_PASSWORD}" ]] && fail "FRAPPE_DB_PASSWORD is required. Use -p|--db-password."
[[ -z "${SITE_NAME}" ]] && fail "SITE_NAME is required. Use -s|--site."
[[ -z "${APP_ADMIN_PASSWORD}" ]] && fail "APP_ADMIN_PASSWORD is required. Use -a|--admin-password."

# Must run as the specified user
if [[ "$(id -un)" != "$FRAPPE_APP_USER" ]]; then
  fail "This script must be run as $FRAPPE_APP_USER. Try: sudo su - $FRAPPE_APP_USER"
fi

log "Executor: script=${SCRIPT_BASENAME} user=$(id -un) uid=$(id -u)"

cd ~

#############################################
# MYSQL SECURE INSTALL & WKHTMLTOPDF
#############################################
log "Initializing the MySQL server setup (mariadb-secure-installation)"
sudo mariadb-secure-installation <<MARIADB_EOF

y
y
$FRAPPE_DB_PASSWORD
$FRAPPE_DB_PASSWORD
y
y
y
y
MARIADB_EOF

log "Installing wkhtmltopdf and dependencies"
sudo apt install -y xvfb libfontconfig
# Detect Ubuntu codename and download a matching wkhtmltopdf build, with Jammy fallback
OS_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
ARCH="amd64"
PRIMARY_VER="0.12.6.1-3"
FALLBACK_VER="0.12.6.1-2"
declare -a CANDIDATE_URLS=()

if [[ -n "$OS_CODENAME" ]]; then
  CANDIDATE_URLS+=("https://github.com/wkhtmltopdf/packaging/releases/download/${PRIMARY_VER}/wkhtmltox_${PRIMARY_VER}.${OS_CODENAME}_${ARCH}.deb")
  CANDIDATE_URLS+=("https://github.com/wkhtmltopdf/packaging/releases/download/${FALLBACK_VER}/wkhtmltox_${FALLBACK_VER}.${OS_CODENAME}_${ARCH}.deb")
fi
# Always add Jammy fallback
CANDIDATE_URLS+=("https://github.com/wkhtmltopdf/packaging/releases/download/${FALLBACK_VER}/wkhtmltox_${FALLBACK_VER}.jammy_${ARCH}.deb")

WK_DEB_URL=""
for url in "${CANDIDATE_URLS[@]}"; do
  if wget -q --spider "$url"; then
    WK_DEB_URL="$url"
    break
  fi
done

if [[ -z "$WK_DEB_URL" ]]; then
  log "Could not find a matching wkhtmltopdf build, defaulting to Jammy fallback"
  WK_DEB_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${FALLBACK_VER}/wkhtmltox_${FALLBACK_VER}.jammy_${ARCH}.deb"
fi

WK_DEB_FILE="$(basename "$WK_DEB_URL")"
wget -q "$WK_DEB_URL"
sudo dpkg -i "$WK_DEB_FILE" || sudo apt install -y -f

#############################################
# NVM / NODE / YARN
#############################################
log "Installing NVM & Node"
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash

export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"

nvm install 24
npm install -g yarn

#############################################
# UV + PYTHON
#############################################
log "Installing uv & Python"
curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.local/bin/env"
uv python install 3.14 --default

#############################################
# BENCH
#############################################
log "Installing Bench CLI"
uv tool install frappe-bench==5.28

log "Initializing Bench"
bench init frappe-bench --frappe-branch version-16-beta

#############################################
# SITE CREATION
#############################################
cd ~/frappe-bench
log "Installing honcho in bench virtualenv"
( source env/bin/activate && uv pip install honcho )
log "Creating site: $SITE_NAME"
bench new-site "$SITE_NAME" \
  --db-root-username=root \
  --db-root-password="$FRAPPE_DB_PASSWORD" \
  --admin-password="$APP_ADMIN_PASSWORD"

if [[ "${DEV_MODE,,}" == "true" ]]; then
  log "Enabling developer mode"
  bench set-config -g developer_mode true
else
  log "Developer mode not enabled (use --dev true to enable)"
fi

log "Setup (user phase) completed successfully"

