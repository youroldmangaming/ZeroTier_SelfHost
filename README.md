# ZeroTier Self-Hosted Controller

A self-hosted [ZeroTier](https://zerotier.com) network controller running in Docker Compose on Ubuntu/Debian. Includes the [ztncui](https://github.com/key-networks/ztncui) web UI for managing networks and members.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Host (Ubuntu/Debian)                                   │
│                                                         │
│  ┌──────────────────────┐   ┌────────────────────────┐  │
│  │  zerotier-controller │   │  ztncui (Web UI)       │  │
│  │  zyclonite/zerotier  │◄──│  key-networks/ztncui   │  │
│  │  network_mode: host  │   │  :3000                 │  │
│  │  UDP :9993           │   └────────────────────────┘  │
│  └──────────────────────┘                               │
│         ▲                                               │
│         │  zerotier-data (Docker volume)                │
└─────────────────────────────────────────────────────────┘
         ▲
         │  Clients join via zerotier-cli join <network-id>
```

## Prerequisites

- Ubuntu 20.04+ / Debian 11+
- Docker Engine 24+
- Docker Compose v2 (`docker compose version`)
- Port **9993/UDP** open in your firewall
- Port **3000/TCP** open for the web UI (or set `ZTNCUI_PORT`)

## Quick Start

```bash
# 1. Clone the repo
git clone <your-repo-url>
cd <repo>

# 2. Run setup (creates .env, starts services, retrieves token)
sudo bash scripts/setup.sh

# 3. Open the Web UI
open http://<server-ip>:3000
# Login: admin / <ZTNCUI_PASSWD from .env>
```

## Configuration

Copy `.env.example` to `.env` and edit:

| Variable | Default | Description |
|---|---|---|
| `ZEROTIER_API_SECRET` | *(auto-generated)* | Controller auth token |
| `ZTNCUI_PORT` | `3000` | Web UI port |
| `ZTNCUI_PASSWD` | *(must set)* | Web UI admin password |

> **Important:** Never commit `.env` to version control. It's in `.gitignore`.

## Managing Networks via CLI

```bash
# List all networks
./scripts/manage-network.sh list

# Create a network with a custom subnet
./scripts/manage-network.sh create "My VPN" 10.10.0.0/24

# View network details
./scripts/manage-network.sh info <network-id>

# List members pending authorisation
./scripts/manage-network.sh members <network-id>

# Authorise a member
./scripts/manage-network.sh authorize <network-id> <member-id>

# Deauthorise a member
./scripts/manage-network.sh deauthorize <network-id> <member-id>

# Delete a network
./scripts/manage-network.sh delete <network-id>
```

## Connecting Clients

On any Linux/macOS/Windows machine:

```bash
# Install ZeroTier
curl -s https://install.zerotier.com | sudo bash

# Join your self-hosted network
sudo zerotier-cli join <network-id>

# Check status
sudo zerotier-cli listnetworks
```

Then **authorise** the new member from the web UI or:

```bash
./scripts/manage-network.sh authorize <network-id> <member-id>
```

## Docker Compose Operations

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop without removing data
docker compose stop

# Full teardown (preserves volumes)
docker compose down

# Full teardown including all data (destructive!)
docker compose down -v
```

## Firewall

```bash
# Allow ZeroTier (required)
sudo ufw allow 9993/udp

# Allow Web UI (restrict to your IP in production)
sudo ufw allow 3000/tcp
# or: sudo ufw allow from <your-ip> to any port 3000
```

## Backup & Restore

All persistent data lives in the `zerotier-data` Docker volume.

```bash
# Backup
docker run --rm \
  -v zerotier_zerotier-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/zerotier-backup-$(date +%F).tar.gz -C /data .

# Restore
docker run --rm \
  -v zerotier_zerotier-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/zerotier-backup-<date>.tar.gz"
```

## Troubleshooting

**Controller not reachable from clients:**
- Ensure UDP 9993 is open on your host firewall and cloud security groups.
- The controller uses `network_mode: host`, so no port mapping is needed.

**ztncui shows "cannot connect to ZeroTier":**
- Wait ~30s after first start for the token to be written.
- Run `scripts/get-token.sh` and make sure `ZEROTIER_API_SECRET` in `.env` matches.
- Restart the UI: `docker compose restart ztncui`

**Check ZeroTier status:**
```bash
docker compose exec zerotier zerotier-cli status
docker compose exec zerotier zerotier-cli listnetworks
```

## Project Structure

```
.
├── docker-compose.yml          # Main service definition
├── .env.example                # Config template (copy to .env)
├── .gitignore
├── scripts/
│   ├── setup.sh                # First-time setup
│   ├── get-token.sh            # Retrieve auth token
│   └── manage-network.sh       # Network & member management
└── README.md
```
