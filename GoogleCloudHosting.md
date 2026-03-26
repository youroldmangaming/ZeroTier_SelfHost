# Google Cloud Setup Guide — ZeroTier Self-Hosted Controller

This guide documents the full process of deploying a permanent, self-hosted ZeroTier
controller on a Google Cloud free tier VM with direct UDP connectivity.

---

## Prerequisites

- A Google account with a GCP project that has billing enabled
- Access to [Google Cloud Shell](https://shell.cloud.google.com)
- This repository cloned or available on GitHub

---

## Step 1 — Prepare your GCP Project

Open **Google Cloud Shell** from the GCP console and find your project ID:

```bash
gcloud projects list
```

You will see output like:
```
PROJECT_ID             NAME               PROJECT_NUMBER
zeroteir               ZeroTeir           848085549122
ace-well-316005        My First Project   840884627191
```

Set your project:
```bash
gcloud config set project YOUR_PROJECT_ID
PROJECT=YOUR_PROJECT_ID
```

Verify billing is enabled on the project (required for Compute Engine):
```bash
gcloud beta billing projects describe $PROJECT
```

You should see `billingEnabled: true`. If not, go to:
**https://console.cloud.google.com/billing/linkedaccount?project=YOUR_PROJECT_ID**
and link a billing account before continuing.

---

## Step 2 — Create the VM

Use the **e2-micro** machine type in one of these three free tier regions:
- `us-central1-a`
- `us-east1-b`
- `us-west1-a`

> **Note:** `--boot-disk-size=10GB` is more than sufficient for this workload
> (~4GB used). The `pd-standard` disk type is required for free tier eligibility.
> Ignore GCP's warning about disk performance — it does not apply here.

```bash
gcloud compute instances create zerotier-controller \
  --machine-type=e2-micro \
  --zone=us-central1-a \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=10GB \
  --boot-disk-type=pd-standard \
  --tags=zerotier \
  --project=$PROJECT
```

Note the **EXTERNAL_IP** in the output — this is your permanent controller address:
```
NAME: zerotier-controller
ZONE: us-central1-a
MACHINE_TYPE: e2-micro
INTERNAL_IP: 10.128.0.2
EXTERNAL_IP: 34.31.246.239     ← save this
STATUS: RUNNING
```

---

## Step 3 — Open Firewall Ports

ZeroTier requires **UDP 9993** to be open for direct peer connections. Without this
the controller falls back to TCP relay which is slower and less reliable.

```bash
# ZeroTier P2P traffic — critical for DIRECT (not RELAY) connections
gcloud compute firewall-rules create allow-zerotier \
  --allow=udp:9993 \
  --target-tags=zerotier \
  --description="ZeroTier P2P" \
  --project=$PROJECT

# ZeroUI web dashboard
gcloud compute firewall-rules create allow-zerotier-ui \
  --allow=tcp:4000 \
  --target-tags=zerotier \
  --description="ZeroTier UI" \
  --project=$PROJECT
```

> **Security note:** In production, restrict port 4000 to your own IP:
> `--source-ranges=YOUR.IP.ADDRESS/32`

---

## Step 4 — SSH into the VM

```bash
gcloud compute ssh zerotier-controller \
  --zone=us-central1-a \
  --project=$PROJECT
```

On first run this will:
- Create `~/.ssh/` directory
- Generate an SSH keypair for gcloud
- Propagate the public key to the VM

When prompted for a passphrase you can leave it empty for convenience,
or set one for extra security.

---

## Step 5 — Install Docker

All commands from here run **inside the VM**.

```bash
# Install Docker CE (official installer — not the older apt docker.io package)
curl -fsSL https://get.docker.com | sh

# Add your user to the docker group
sudo usermod -aG docker $USER

# Apply group change without logging out
newgrp docker

# Verify
docker --version
# Expected: Docker version 29.x.x
```

---

## Step 6 — Deploy ZeroTier

```bash
# Clone the repo
git clone https://github.com/youroldmangaming/ZeroTier_SelfHost.git
cd ZeroTier_SelfHost

# Create and configure environment file
cp .env.example .env
nano .env
```

Set a strong password in `.env`:
```
ZU_DEFAULT_USERNAME=admin
ZU_DEFAULT_PASSWORD=your_strong_password_here
```

Save with `Ctrl+X` → `Y` → Enter.

> **Important:** Also ensure `ZU_SECURE_HEADERS=false` is set in `docker-compose.yml`
> unless you have HTTPS configured. See the SSL section below.

```bash
# Start the stack
docker compose up -d
```

Expected output:
```
✔ Volume zerotier_selfhost_zerotier-data  Created
✔ Volume zerotier_selfhost_zero-ui-data   Created
✔ Container zerotier-controller           Healthy
✔ Container zerotier-ui                   Started
```

---

## Step 7 — Verify Direct UDP Connectivity

This is the critical check. After deployment, restart the controller once to
ensure ZeroTier binds correctly, then check peer connectivity:

```bash
docker compose restart zerotier
sleep 15

# Check controller status
docker exec zerotier-controller zerotier-cli status
# Expected: 200 info <node-id> 1.14.0 ONLINE

# Check peer connections — you want DIRECT not RELAY
docker exec zerotier-controller zerotier-cli peers
```

Healthy output:
```
<ztaddr>   <ver>  <role> <lat> <link>   <path>
778cde7190 -      PLANET   50  DIRECT   103.195.103.66/9993
cafe04eba9 -      PLANET  118  DIRECT   84.17.53.155/9993
cafe80ed74 -      PLANET   48  DIRECT   185.152.67.145/9993
cafefd6717 -      PLANET  146  DIRECT   79.127.159.187/9993
```

`DIRECT` on all PLANET peers confirms UDP 9993 is open and working.

If you still see `RELAY` and the message `Currently tunneling through a TCP relay`:
```bash
# Verify the firewall tag is applied to the instance
gcloud compute instances describe zerotier-controller \
  --zone=us-central1-a \
  --project=$PROJECT \
  --format="value(tags.items)"

# If the tag is missing, add it
gcloud compute instances add-tags zerotier-controller \
  --tags=zerotier \
  --zone=us-central1-a \
  --project=$PROJECT

# Then restart and recheck
docker compose restart zerotier && sleep 15
docker exec zerotier-controller zerotier-cli peers
```

---

## Step 8 — Access the Web UI

Open in your browser:
```
http://YOUR_EXTERNAL_IP:4000/app/
```

Login with:
- **Username:** `admin` (or `ZU_DEFAULT_USERNAME` from `.env`)
- **Password:** value of `ZU_DEFAULT_PASSWORD` from `.env`

### Blank page / SSL error in Chrome?

If Chrome shows a blank page and the console shows `ERR_SSL_PROTOCOL_ERROR`,
`ZU_SECURE_HEADERS` is forcing HTTPS on a plain HTTP connection. Fix:

```bash
# Edit docker-compose.yml
nano docker-compose.yml

# Find and change:
#   - ZU_SECURE_HEADERS=true
# To:
#   - ZU_SECURE_HEADERS=false

docker compose up -d --force-recreate zero-ui
```

If Chrome still redirects to HTTPS due to a cached HSTS rule, open the URL
in an **Incognito window** which ignores cached security policies.

---

## Step 9 — Create a Network and Connect Clients

### Create a network

In ZeroUI: click **Add Network** → give it a name → note the network ID.

Or via CLI on the VM:
```bash
./scripts/manage-network.sh create "MyNetwork" 10.10.0.0/24
```

### Join a client device

On any Linux/macOS device:
```bash
# Install ZeroTier
curl -s https://install.zerotier.com | sudo bash

# Join your network
sudo zerotier-cli join <network-id>

# Check status
sudo zerotier-cli listnetworks
# Will show ACCESS_DENIED until you authorise in ZeroUI
```

Windows: download from [zerotier.com/download](https://www.zerotier.com/download/)

### Authorise the device

In ZeroUI → click your network → **Members** → tick **Authorized**.

The device status will change from `ACCESS_DENIED` to `OK` and receive an IP.

---

## Step 10 — Enable Docker on Boot

Ensure ZeroTier restarts automatically if the VM reboots:

```bash
sudo systemctl enable docker

# Verify docker-compose also restarts (handled by restart: unless-stopped in compose file)
grep restart docker-compose.yml
```

---

## Understanding the Network Topology

Your node ID is the first 10 characters of your network ID:

```
Controller node:  7b616f169e
Network ID:       7b616f169edfffd3
                  ^^^^^^^^^^  — same prefix
```

When a client runs `zerotier-cli join 7b616f169edfffd3`, the ZeroTier network
knows to contact node `7b616f169e` for network configuration. This is how
self-hosted controllers work — the network ID encodes the controller address.

---

## Known Limitations vs Production Setup

| Feature | This setup | Production hardened |
|---|---|---|
| UDP direct connectivity | ✅ | ✅ |
| Free tier | ✅ e2-micro | ✅ |
| Persistent storage | ✅ Docker volumes | ✅ |
| HTTPS for web UI | ❌ HTTP only | ✅ Nginx + Let's Encrypt |
| Web UI exposed publicly | ⚠️ Port 4000 open | ✅ Restricted by IP or VPN |
| Automated backups | ❌ | ✅ cron + GCS bucket |
| Monitoring | ❌ | ✅ |

---

## Useful Commands Reference

### From Cloud Shell (not the VM)

```bash
# SSH into VM
gcloud compute ssh zerotier-controller --zone=us-central1-a --project=$PROJECT

# Check VM status
gcloud compute instances list --project=$PROJECT

# Stop VM (stops billing for compute, disk still billed)
gcloud compute instances stop zerotier-controller --zone=us-central1-a --project=$PROJECT

# Start VM
gcloud compute instances start zerotier-controller --zone=us-central1-a --project=$PROJECT

# List firewall rules
gcloud compute firewall-rules list --project=$PROJECT
```

### From inside the VM

```bash
# Controller status
docker exec zerotier-controller zerotier-cli status

# Peer connections (check for DIRECT vs RELAY)
docker exec zerotier-controller zerotier-cli peers

# List all networks
docker exec zerotier-controller zerotier-cli listnetworks

# View all logs
docker compose logs -f

# Restart everything
docker compose restart

# Backup ZeroTier data
docker run --rm \
  -v zerotier_selfhost_zerotier-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/zerotier-backup-$(date +%F).tar.gz -C /data .
```

---

## Troubleshooting

**`Request had insufficient authentication scopes`**
You are running `gcloud` commands from inside the VM. These must be run from
Cloud Shell, not from the VM terminal.

**`The project property is set to the empty string`**
The `$PROJECT` variable is not set. Run `PROJECT=your-project-id` first.

**`Billing account for project is not found`**
Link a billing account at:
https://console.cloud.google.com/billing/linkedaccount?project=YOUR_PROJECT_ID

**Controller shows `TUNNELED` or `RELAY` after deployment**
Restart the ZeroTier container — it sometimes binds to a specific interface
on first start. A restart forces it to rebind correctly:
```bash
docker compose restart zerotier && sleep 15
docker exec zerotier-controller zerotier-cli peers
```

**Web UI blank page with SSL errors in Chrome**
Set `ZU_SECURE_HEADERS=false` in `docker-compose.yml` and recreate the
zero-ui container. See Step 8 above.

**Client shows `ACCESS_DENIED` after joining**
The device needs to be authorised in ZeroUI. Go to Networks → your network →
Members and tick Authorized next to the device.
