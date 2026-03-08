# Deployment Guide — webred-services

## Architecture

```
Your laptop/phone (LAN)
        │
        │  HTTPS  tasks.home / wiki.home
        ▼
  ┌─────────────┐
  │  OPNsense   │  HAProxy on port 443 — SSL termination
  │  (router)   │  Unbound DNS — resolves local hostnames
  └──────┬──────┘
         │  plain HTTP  :3456 / :3000
         ▼
  ┌─────────────────────────────────┐
  │  Proxmox → Debian VM            │
  │  ┌──────────────────────────┐   │
  │  │  Docker Compose          │   │
  │  │  ├── vikunja  :3456      │   │
  │  │  ├── outline  :3000      │   │
  │  │  ├── postgres (internal) │   │
  │  │  ├── redis    (internal) │   │
  │  │  └── minio    (internal) │   │
  │  └──────────────────────────┘   │
  └─────────────────────────────────┘
```

Nothing is exposed to the internet. All traffic stays on your LAN.

---

## Part 1: Debian VM on Proxmox

### 1.1 Create the VM

In Proxmox:
- Download a Debian 12 (Bookworm) ISO
- Create VM: 2+ vCPUs, 4 GB RAM minimum (8 GB recommended), 40 GB disk
- Attach to your LAN bridge (e.g., `vmbr0`)
- Install Debian — minimal install, no desktop needed
- Note the VM's LAN IP (set it static, or assign a DHCP reservation in OPNsense)

### 1.2 Install Docker

```bash
# On the Debian VM
sudo apt update && sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Allow your user to run docker without sudo
sudo usermod -aG docker $USER && newgrp docker
```

### 1.3 Deploy the stack

```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/webred-services.git
cd webred-services

# Set up environment
cp .env.example .env
nano .env   # fill in all values (see notes below)

# Generate secrets (run once each, paste into .env)
openssl rand -hex 32   # → VIKUNJA_JWT_SECRET
openssl rand -hex 32   # → OUTLINE_SECRET_KEY
openssl rand -hex 32   # → OUTLINE_UTILS_SECRET

# Start the stack
docker compose up -d

# Run Outline database migrations (required on first start)
docker compose exec outline yarn db:migrate

# Verify everything is up
docker compose ps
```

### 1.4 Key .env values to set

| Variable | Notes |
|---|---|
| `VIKUNJA_DOMAIN` | e.g. `tasks.home.yourdomain.com` or `tasks.lan` |
| `OUTLINE_DOMAIN` | e.g. `wiki.home.yourdomain.com` or `wiki.lan` |
| `POSTGRES_PASSWORD` | Strong password |
| `MINIO_ROOT_PASSWORD` | Strong password |
| `VIKUNJA_JWT_SECRET` | `openssl rand -hex 32` |
| `OUTLINE_SECRET_KEY` | `openssl rand -hex 32` |
| `OUTLINE_UTILS_SECRET` | `openssl rand -hex 32` |
| `SMTP_*` | Needed for Outline login unless using OIDC |

> Outline **requires** an auth method. Easiest options:
> - **SMTP** — any email provider (Gmail app password, Fastmail, self-hosted)
> - **OIDC** — if you already run Authentik or Keycloak on your homelab

---

## Part 2: SSL Certificate

Pick one approach. Option A is easiest if you have a real domain.

### Option A — Let's Encrypt via Cloudflare DNS (recommended)

You don't need Cloudflare to proxy your traffic — just use it as your DNS
provider. The ACME DNS-01 challenge proves domain ownership via a DNS TXT
record, no port 80 exposure needed.

1. In Cloudflare dashboard: create a scoped API token
   - Permission: `Zone → DNS → Edit` for your zone only
2. In OPNsense: `System → Firmware → Plugins` → install `os-acme-client`
3. `Services → ACME Client → Accounts` → create Let's Encrypt account
4. `Services → ACME Client → Challenge Types` → add Cloudflare, paste token
5. `Services → ACME Client → Certificates` → add cert:
   - Alt names: `tasks.yourdomain.com`, `wiki.yourdomain.com`
   - Challenge: Cloudflare DNS-01
   - Action after renewal: Restart HAProxy
6. Issue the cert — OPNsense puts it in `/var/etc/acme-client/`
7. HAProxy will reference it automatically when you configure the frontend

### Option B — Local CA with mkcert (fully offline)

Use this if you don't have a real domain or don't want any cloud dependency.
Install the CA on every device you use and browsers will trust it natively.

```bash
# On your dev machine (or the Debian VM itself)
# Install mkcert: https://github.com/FiloSottile/mkcert

mkcert -install   # installs root CA into system/browser trust stores

# Generate cert for both services
mkcert tasks.lan wiki.lan
# → produces tasks.lan+1.pem and tasks.lan+1-key.pem
```

Copy the cert+key to OPNsense and reference in the HAProxy frontend.
Install the mkcert root CA on every device (phone, laptop, etc.) that
will access these services.

---

## Part 3: DNS — making hostnames resolve on your LAN

OPNsense's built-in DNS resolver (Unbound) can resolve your local hostnames
without touching the internet.

`Services → Unbound DNS → Host Overrides → Add`

| Host    | Domain              | IP (Type A)    |
|---------|---------------------|----------------|
| `tasks` | `yourdomain.com`    | OPNsense LAN IP (HAProxy listens here) |
| `wiki`  | `yourdomain.com`    | OPNsense LAN IP |

> Point DNS to OPNsense's IP, **not** the Debian VM IP. HAProxy on OPNsense
> does the routing. The Debian VM's ports (3000, 3456) are not accessed directly.

---

## Part 4: HAProxy on OPNsense

Follow `docs/haproxy-opnsense.md` for the GUI walkthrough.
The two placeholders to fill in `haproxy/haproxy.cfg`:

```
PLACEHOLDER_VM_IP    → Debian VM's LAN IP (e.g. 192.168.1.50)
PLACEHOLDER_DOMAIN   → your domain (e.g. yourdomain.com)
```

---

## Part 5: Verify end-to-end

```bash
# From any LAN device
curl -I https://tasks.yourdomain.com       # should return 200
curl -I https://wiki.yourdomain.com        # should return 200

# On the Debian VM — check all containers healthy
docker compose ps
docker compose logs vikunja --tail=20
docker compose logs outline --tail=20
```

---

## Maintenance

### Update containers
```bash
cd ~/webred-services
docker compose pull
docker compose up -d
docker compose exec outline yarn db:migrate   # after Outline updates
```

### Backup
The only stateful data is in Docker volumes. Back up:
```bash
# Quick backup of all volumes to a tarball
docker run --rm \
  -v webred-services_postgres_data:/data/postgres \
  -v webred-services_vikunja_files:/data/vikunja \
  -v webred-services_minio_data:/data/minio \
  -v $(pwd)/backup:/backup \
  alpine tar czf /backup/webred-$(date +%Y%m%d).tar.gz /data
```

### Restart a single service
```bash
docker compose restart vikunja
docker compose restart outline
```
