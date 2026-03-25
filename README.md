# ZeroTier Self-Hosted Controller

A self-hosted [ZeroTier](https://zerotier.com) network controller running in Docker Compose on Ubuntu/Debian. Includes the [ZeroUI](https://github.com/dec0dOS/zero-ui) web dashboard for managing networks and members.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Host (Ubuntu/Debian)                                   │
│                                                         │
│  ┌──────────────────────┐   ┌────────────────────────┐  │
│  │  zerotier-controller │   │  zero-ui (Web UI)      │  │
│  │  zyclonite/zerotier  │◄──│  dec0dos/zero-ui       │  │
│  │  network_mode: host  │   │  TCP :4000             │  │
│  │  UDP :9993           │   └────────────────────────┘  │
│  └──────────────────────┘                               │
│         ▲  zerotier-data volume (shared)                │
└─────────────────────────────────────────────────────────┘
         ▲
         │  Clients join via zerotier-cli join <network-id>
         │  (direct UDP, or relayed via PLANET root servers)
```

## Prerequisites

- Ubuntu 20.04+ / Debian 11+
- Docker Engine 24+
- Docker Compose v2 (`docker compose version`)
- Port **9993/UDP** open in your firewall (see Codespaces note below)
- Port **4000/TCP** open for the web UI

---

## Running in GitHub Codespaces

Codespaces is useful for development and testing, but has important limitations for production use. Read this section before starting.

### Quick start in Codespaces

```bash
# 1. Clone and enter the repo
git clone <your-repo-url>
cd <repo>

# 2. Copy and configure env
cp .env.example .env
nano .env   # set ZU_DEFAULT_PASSWORD to something strong

# 3. Start the stack
docker compose up -d

# 4. Verify both containers are running and healthy
docker compose ps
```

Expected output:
```
NAME                  IMAGE                       STATUS
zerotier-controller   zyclonite/zerotier:1.14.0   Up (healthy)
zerotier-ui           dec0dos/zero-ui:latest       Up
```

### Accessing the Web UI in Codespaces

Codespaces does not expose ports automatically with `network_mode: host`. Forward port 4000 manually:

1. Click the **Ports** tab in the VS Code bottom panel
2. Click **Add Port** → enter `4000` → press Enter
3. Right-click port 4000 → **Port Visibility → Public**
4. Click the 🌐 globe icon — your URL will look like:
   ```
   https://<codespace-name>-4000.app.github.dev/app/
   ```

Or get your URL directly from the terminal:
```bash
echo "https://${CODESPACE_NAME}-4000.app.github.dev/app/"
```

Log in with:
- **Username:** `admin` (or `ZU_DEFAULT_USERNAME` from `.env`)
- **Password:** value of `ZU_DEFAULT_PASSWORD` in `.env`

### Verifying your controller is connected

Run these commands to confirm the controller is live and talking to the ZeroTier network:

```bash
# Should show: 200 info <node-id> 1.14.0 ONLINE
docker exec zerotier-controller zerotier-cli status

# Should list PLANET root servers as peers
docker exec zerotier-controller zerotier-cli peers
```

Healthy output looks like:
```
200 info 1eecdf0666 1.14.0 ONLINE

<ztaddr>   <ver>  <role> <lat> <link>   <path>
778cde7190 -      PLANET  193  RELAY    103.195.103.66/9993
cafe04eba9 -      PLANET  262  RELAY    84.17.53.155/9993
cafefd6717 -      PLANET  100  RELAY    79.127.159.187/9993
```

> **Note:** Your controller's node ID is the first 10 characters of your network ID.
> When clients join network `1eecdf0666e7a6fa`, ZeroTier knows to contact node `1eecdf0666`
> for network configuration — this is by design.

### ⚠️ The Codespaces UDP limitation

You will see this warning from the controller when running in Codespaces:

```
NOTE: Currently tunneling through a TCP relay. Ensure that UDP is not blocked.
```

This is expected and unavoidable — Codespaces blocks all UDP traffic. Here is what it means in practice:

| Capability | Codespaces | VPS / bare metal |
|---|---|---|
| Controller ONLINE | ✅ | ✅ |
| Web UI accessible | ✅ (TCP 4000) | ✅ |
| Connected to PLANET roots | ✅ (via TCP relay) | ✅ (direct UDP) |
| Devices can join | ✅ (relayed) | ✅ (direct) |
| Direct peer-to-peer between clients | ❌ | ✅ |
| Suitable for production | ❌ Codespace sleeps | ✅ |

**Clients can still join your network via relay** — ZeroTier's PLANET root servers act as
intermediaries when direct UDP is blocked. This works for development and testing but adds
latency and is unreliable for production because Codespaces will shut down after inactivity.

### Testing a client join from within Codespaces

The easiest way to verify the full join cycle in Codespaces is to join from the Codespace host itself, since that bypasses the external UDP block:

```bash
# Install ZeroTier in the Codespace
curl -s https://install.zerotier.com | sudo bash

# Join your network
sudo zerotier-cli join <your-network-id>

# Watch for the device to appear as a LEAF peer
watch -n 2 'docker exec zerotier-controller zerotier-cli peers'
```

Then authorise the device in ZeroUI: **Networks → your network → Members → tick Authorized**.

---

## Production Deployment (VPS)

For a permanent deployment with direct UDP and reliable uptime, use a small VPS.
The same `docker-compose.yml` works without any changes.

Recommended providers:

| Provider | Spec | Cost |
|---|---|---|
| [Hetzner CAX11](https://hetzner.com) | 2 vCPU / 4GB RAM | ~€4/mo |
| [DigitalOcean](https://digitalocean.com) | 1 vCPU / 1GB RAM | $4/mo |
| [Oracle Cloud Free Tier](https://oracle.com/cloud/free/) | 1 vCPU / 1GB RAM | Free |

```bash
# On your VPS (Ubuntu 22.04)
git clone <your-repo-url>
cd <repo>
cp .env.example .env
nano .env   # set ZU_DEFAULT_PASSWORD

sudo bash scripts/setup.sh

# Open required ports
sudo ufw allow 9993/udp   # ZeroTier P2P — this is the critical one
sudo ufw allow 4000/tcp   # Web UI
sudo ufw enable
```

Once on a real server, verify peers show `DIRECT` instead of `RELAY`:

```bash
docker exec zerotier-controller zerotier-cli peers
# ✅ Good:  cafe04eba9 - PLANET 45  DIRECT  84.17.53.155/9993
# ⚠️  Bad:  cafe04eba9 - PLANET 262 RELAY   84.17.53.155/9993
```

`DIRECT` confirms UDP 9993 is open and clients will connect with full performance.

---

## Configuration

Copy `.env.example` to `.env` before first start:

| Variable | Default | Description |
|---|---|---|
| `ZU_DEFAULT_USERNAME` | `admin` | Web UI login username |
| `ZU_DEFAULT_PASSWORD` | *(must change)* | Web UI login password |

> **Important:** `.env` is listed in `.gitignore` and must never be committed to version control.

---

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

---

## Connecting Clients

On any Linux / macOS / Windows device:

```bash
# Install ZeroTier
curl -s https://install.zerotier.com | sudo bash

# Join your network
sudo zerotier-cli join <network-id>

# Check join status
sudo zerotier-cli listnetworks
```

Windows: download from [zerotier.com/download](https://www.zerotier.com/download/)

After joining, authorise the device from ZeroUI (Networks → Members) or via CLI:

```bash
./scripts/manage-network.sh authorize <network-id> <member-id>
```

---

## Docker Compose Operations

```bash
# Start all services
docker compose up -d

# View logs (all services)
docker compose logs -f

# View logs for one service
docker compose logs -f zerotier
docker compose logs -f zero-ui

# Restart all services
docker compose restart

# Stop without removing data
docker compose stop

# Full teardown — preserves volumes
docker compose down

# Full teardown including all data — DESTRUCTIVE
docker compose down -v
```

---

## Backup & Restore

All persistent state (networks, members, keys) lives in the `zerotier-data` Docker volume.

```bash
# Backup
docker run --rm \
  -v zerotier_selfhost_zerotier-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/zerotier-backup-$(date +%F).tar.gz -C /data .

# Restore
docker run --rm \
  -v zerotier_selfhost_zerotier-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd /data && tar xzf /backup/zerotier-backup-<date>.tar.gz"
```

> Always back up before migrating to a new server or running `docker compose down -v`.

---

## Troubleshooting

**`pull access denied for key-networks/ztncui`**
That image no longer exists on Docker Hub. This repo uses `dec0dos/zero-ui` instead. Make sure you have the latest `docker-compose.yml` from this repo.

**Port 4000 not appearing in Codespaces Ports panel**
With `network_mode: host`, Codespaces does not auto-detect ports. Add it manually:
Ports tab → Add Port → `4000` → set visibility to Public.

**Web UI shows "cannot connect to controller"**
ZeroUI reads the auth token directly from the shared `zerotier-data` volume — no manual token setup needed. If it fails to connect:
```bash
docker compose restart zero-ui
docker compose logs zero-ui
```

**Controller shows `RELAY` for all peers**
UDP 9993 is blocked. This is normal in Codespaces and some corporate networks. Clients can still connect via TCP relay, but for production open UDP 9993 on your host firewall and cloud security group. Verify with:
```bash
ss -ulnp | grep 9993
# Should show 0.0.0.0:9993, not a specific interface like 10.0.1.152:9993
```

**Check overall controller health**
```bash
docker exec zerotier-controller zerotier-cli status
docker exec zerotier-controller zerotier-cli peers
docker exec zerotier-controller zerotier-cli listnetworks
```

---

## Project Structure

```
.
├── docker-compose.yml          # ZeroTier controller + ZeroUI
├── .env.example                # Config template — copy to .env
├── .gitignore                  # Keeps .env out of git
├── scripts/
│   ├── setup.sh                # First-time bootstrap
│   ├── get-token.sh            # Retrieve controller auth token
│   └── manage-network.sh       # Network & member management CLI
└── README.md
```
