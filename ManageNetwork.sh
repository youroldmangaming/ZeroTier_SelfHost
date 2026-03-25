#!/usr/bin/env bash
# =============================================================================
# manage-network.sh — Manage ZeroTier networks via the local controller API
# =============================================================================
# Usage:
#   ./scripts/manage-network.sh list
#   ./scripts/manage-network.sh create "My Network" 10.147.20.0/24
#   ./scripts/manage-network.sh info   <network-id>
#   ./scripts/manage-network.sh members <network-id>
#   ./scripts/manage-network.sh authorize <network-id> <member-id>
#   ./scripts/manage-network.sh deauthorize <network-id> <member-id>
#   ./scripts/manage-network.sh delete <network-id>
# =============================================================================
set -euo pipefail

# ---- Load config ------------------------------------------------------------

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run scripts/setup.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

ZT_TOKEN="${ZEROTIER_API_SECRET:?ZEROTIER_API_SECRET not set in .env}"
ZT_ADDR="http://localhost:9993"
CONTROLLER_ID=$(docker compose exec -T zerotier zerotier-cli info | awk '{print $3}')

# ---- Helpers ----------------------------------------------------------------

zt_api() {
  local method=$1 path=$2
  shift 2
  curl -sf -X "$method" \
    -H "X-ZT1-AUTH: ${ZT_TOKEN}" \
    -H "Content-Type: application/json" \
    "${ZT_ADDR}${path}" "$@"
}

usage() {
  grep '^# Usage:' -A 10 "$0" | sed 's/^# //' | sed 's/^#//'
  exit 1
}

# ---- Commands ---------------------------------------------------------------

CMD="${1:-help}"

case "$CMD" in

  list)
    echo "Networks on controller ${CONTROLLER_ID}:"
    zt_api GET "/controller/network" | python3 -m json.tool
    ;;

  create)
    NAME="${2:-My Network}"
    SUBNET="${3:-10.147.20.0/24}"
    GATEWAY=$(echo "$SUBNET" | awk -F'[./]' '{print $1"."$2"."$3".1"}')
    POOL_START=$(echo "$SUBNET" | awk -F'[./]' '{print $1"."$2"."$3".10"}')
    POOL_END=$(echo "$SUBNET" | awk -F'[./]' '{print $1"."$2"."$3".250"}')

    PAYLOAD=$(cat <<EOF
{
  "name": "${NAME}",
  "private": true,
  "v4AssignMode": {"zt": true},
  "routes": [{"target": "${SUBNET}"}],
  "ipAssignmentPools": [{"ipRangeStart": "${POOL_START}", "ipRangeEnd": "${POOL_END}"}]
}
EOF
)
    echo "Creating network '${NAME}' (${SUBNET})..."
    RESULT=$(zt_api POST "/controller/network/${CONTROLLER_ID}______" -d "$PAYLOAD")
    echo "$RESULT" | python3 -m json.tool
    NETWORK_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
    echo ""
    echo "Network ID: ${NETWORK_ID}"
    echo "Clients join with: zerotier-cli join ${NETWORK_ID}"
    ;;

  info)
    NETWORK_ID="${2:?Usage: manage-network.sh info <network-id>}"
    zt_api GET "/controller/network/${NETWORK_ID}" | python3 -m json.tool
    ;;

  members)
    NETWORK_ID="${2:?Usage: manage-network.sh members <network-id>}"
    echo "Members of network ${NETWORK_ID}:"
    zt_api GET "/controller/network/${NETWORK_ID}/member" | python3 -m json.tool
    ;;

  authorize)
    NETWORK_ID="${2:?Usage: manage-network.sh authorize <network-id> <member-id>}"
    MEMBER_ID="${3:?Usage: manage-network.sh authorize <network-id> <member-id>}"
    echo "Authorising member ${MEMBER_ID} on network ${NETWORK_ID}..."
    zt_api POST "/controller/network/${NETWORK_ID}/member/${MEMBER_ID}" \
      -d '{"authorized": true}' | python3 -m json.tool
    ;;

  deauthorize)
    NETWORK_ID="${2:?Usage: manage-network.sh deauthorize <network-id> <member-id>}"
    MEMBER_ID="${3:?Usage: manage-network.sh deauthorize <network-id> <member-id>}"
    echo "Deauthorising member ${MEMBER_ID}..."
    zt_api POST "/controller/network/${NETWORK_ID}/member/${MEMBER_ID}" \
      -d '{"authorized": false}' | python3 -m json.tool
    ;;

  delete)
    NETWORK_ID="${2:?Usage: manage-network.sh delete <network-id>}"
    read -rp "Delete network ${NETWORK_ID}? This cannot be undone. [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
    zt_api DELETE "/controller/network/${NETWORK_ID}"
    echo "Network ${NETWORK_ID} deleted."
    ;;

  *)
    usage
    ;;
esac
