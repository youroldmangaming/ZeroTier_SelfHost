#!/usr/bin/env bash
# =============================================================================
# setup.sh — First-time setup for the ZeroTier self-hosted controller
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---- Prerequisites check ----------------------------------------------------

info "Checking prerequisites..."

command -v docker  >/dev/null 2>&1 || error "Docker is not installed. See https://docs.docker.com/engine/install/"
command -v docker  >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 || \
  error "Docker Compose v2 is not installed. Run: apt-get install docker-compose-plugin"

# ---- TUN device -------------------------------------------------------------

if [ ! -e /dev/net/tun ]; then
  warn "/dev/net/tun not found — creating it..."
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
  info "/dev/net/tun created."
fi

# ---- IP forwarding ----------------------------------------------------------

if ! sysctl net.ipv4.ip_forward | grep -q "= 1"; then
  warn "Enabling IPv4 forwarding..."
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# ---- .env file --------------------------------------------------------------

if [ ! -f .env ]; then
  info "Creating .env from .env.example..."
  cp .env.example .env
  warn "Please edit .env and set a strong ZTNCUI_PASSWD before continuing."
  warn "Re-run this script after editing .env."
  exit 0
fi

# shellcheck disable=SC1091
source .env

if [[ "${ZTNCUI_PASSWD:-change_me_immediately}" == "change_me_immediately" ]]; then
  error "ZTNCUI_PASSWD is still the default. Edit .env first!"
fi

# ---- Start ZeroTier (controller only, first pass) ---------------------------

info "Starting ZeroTier controller to generate auth token..."
docker compose up -d zerotier

info "Waiting for ZeroTier to initialise (up to 30s)..."
for i in $(seq 1 30); do
  if docker compose exec zerotier zerotier-cli status >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# ---- Retrieve auth token ----------------------------------------------------

TOKEN_FILE="$(docker volume inspect zerotier_zerotier-data --format '{{.Mountpoint}}')/authtoken.secret" 2>/dev/null || true

if [ -z "${ZEROTIER_API_SECRET:-}" ]; then
  info "Extracting auth token from controller..."
  TOKEN=$(docker compose exec zerotier cat /var/lib/zerotier-one/authtoken.secret 2>/dev/null || true)
  if [ -z "$TOKEN" ]; then
    error "Could not read authtoken.secret. Check container logs: docker compose logs zerotier"
  fi

  # Write token back to .env
  sed -i "s|^ZEROTIER_API_SECRET=.*|ZEROTIER_API_SECRET=${TOKEN}|" .env
  info "Token saved to .env: ${TOKEN:0:8}..."
fi

# ---- Start full stack -------------------------------------------------------

info "Starting full stack (ZeroTier + ztncui web UI)..."
docker compose up -d

info "Waiting for web UI to become available..."
PORT="${ZTNCUI_PORT:-3000}"
for i in $(seq 1 30); do
  if curl -sf "http://localhost:${PORT}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo ""
echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN}  ZeroTier Controller is up!${NC}"
echo -e "${GREEN}======================================================${NC}"
echo ""
echo -e "  Web UI:      http://$(hostname -I | awk '{print $1}'):${PORT}"
echo -e "  Username:    admin"
echo -e "  Password:    (from ZTNCUI_PASSWD in .env)"
echo ""
echo -e "  Controller address: $(docker compose exec zerotier zerotier-cli info | awk '{print $3}')"
echo ""
echo -e "  Next steps:"
echo -e "    1. Open the Web UI and create a network"
echo -e "    2. Authorise joining nodes from the Members tab"
echo -e "    3. Join from any client: zerotier-cli join <network-id>"
echo ""
