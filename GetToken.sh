#!/usr/bin/env bash
# get-token.sh — Print the current ZeroTier controller auth token
set -euo pipefail

TOKEN=$(docker compose exec zerotier cat /var/lib/zerotier-one/authtoken.secret 2>/dev/null)

if [ -z "$TOKEN" ]; then
  echo "ERROR: Could not read token. Is the ZeroTier container running?" >&2
  echo "  docker compose ps" >&2
  exit 1
fi

echo "ZeroTier Auth Token: ${TOKEN}"
echo ""
echo "Add this to your .env:"
echo "  ZEROTIER_API_SECRET=${TOKEN}"
