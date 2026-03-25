#!/usr/bin/env bash
# =============================================================================
# setup.sh — First-time setup for the ZeroTier self-hosted controller
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

info "Checking prerequisites..."
command -v docker >/dev/null 2>&1 || error "Docker not installed."
docker compose version >/dev/null 2>&1 || error "Docker Compose v2 not installed: apt-get install docker-compose-plugin"

if [ ! -e /dev/net/tun ]; then
  warn "/dev/net/tun not found — creating..."
  mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun
fi

if ! sysctl net.ipv4.ip_forward | grep -q "= 1"; then
  warn "Enabling IPv4 forwarding..."
  sysctl -w net.ipv4.ip_forward=1
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

if [ ! -f .env ]; then
  cp .env.example .env
  warn "Edit .env and set a strong ZU_DEFAULT_PASSWORD, then re-run."
  exit 0
fi

source .env
[[ "${ZU_DEFAULT_PASSWORD:-change_me_immediately}" == "change_me_immediately" ]] && \
  error "ZU_DEFAULT_PASSWORD is still the default. Edit .env first!"

info "Starting ZeroTier controller + ZeroUI..."
docker compose up -d

info "Waiting for web UI (up to 60s)..."
for i in $(seq 1 60); do
  curl -sf "http://localhost:4000/api/status" >/dev/null 2>&1 && break
  sleep 1
done

CONTROLLER_ID=$(docker compose exec -T zerotier zerotier-cli info 2>/dev/null | awk '{print $3}' || echo "unknown")

echo ""
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}  ZeroTier Controller is up!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "  Web UI:  http://$(hostname -I | awk '{print $1}'):4000"
echo -e "  User:    ${ZU_DEFAULT_USERNAME:-admin}"
echo -e "  Pass:    (ZU_DEFAULT_PASSWORD from .env)"
echo -e "  Node ID: ${CONTROLLER_ID}"
echo ""
