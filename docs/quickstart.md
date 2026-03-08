# Quickstart — run locally on Debian VM, port 7878

## What you'll have when done

```
http://tasks.lan:7878  →  Vikunja (task management)
http://wiki.lan:7878   →  Outline (wiki / notes)
```

Everything runs in Docker on your Debian VM. Port 7878 is the only
exposed port. Nginx routes by hostname internally.

---

## Step 1 — Install Docker on the Debian VM

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker
```

---

## Step 2 — Clone and configure

```bash
git clone https://github.com/YOUR_USERNAME/webred-services.git
cd webred-services

cp .env.example .env
```

Edit `.env` — the minimum you must change:

```bash
# Replace 192.168.1.50 with your Debian VM's actual LAN IP
VIKUNJA_PUBLIC_URL=http://tasks.lan:7878
OUTLINE_PUBLIC_URL=http://wiki.lan:7878

POSTGRES_PASSWORD=pick_a_strong_password
MINIO_ROOT_PASSWORD=pick_a_strong_password

# Generate these — run each command, paste output into .env
# openssl rand -hex 32
VIKUNJA_JWT_SECRET=<paste here>
OUTLINE_SECRET_KEY=<paste here>
OUTLINE_UTILS_SECRET=<paste here>
```

For Outline login you need **at least one auth method**. Easiest options:

**Option A — SMTP (any email provider):**
```bash
SMTP_ENABLED=true
SMTP_HOST=smtp.gmail.com          # or your provider
SMTP_PORT=587
SMTP_USER=you@gmail.com
SMTP_PASSWORD=your_app_password   # Gmail: use an App Password
SMTP_FROM=you@gmail.com
```

**Option B — skip for now, add OIDC later** (Vikunja works without SMTP).

---

## Step 3 — Start the stack

```bash
docker compose up -d

# Watch startup — wait until all containers show "healthy" or "running"
docker compose ps

# Required after first Outline start:
docker compose exec outline yarn db:migrate
```

---

## Step 4 — Add hostnames on every device you'll use

This tells your browser what IP `tasks.lan` and `wiki.lan` point to.
Do this on each computer/phone you want to use.

**Linux / Mac** — edit `/etc/hosts`:
```
192.168.1.50   tasks.lan wiki.lan
```
(replace `192.168.1.50` with your Debian VM's LAN IP)

**Windows** — edit `C:\Windows\System32\drivers\etc\hosts` as Administrator:
```
192.168.1.50   tasks.lan wiki.lan
```

**Router shortcut** — if your OPNsense Unbound is your DNS server for the LAN,
add host overrides there instead and every device gets it automatically:
`Services → Unbound DNS → Host Overrides → Add`
- Host: `tasks`, Domain: `lan`, IP: VM's LAN IP
- Host: `wiki`,  Domain: `lan`, IP: VM's LAN IP

---

## Step 5 — Open in browser

```
http://tasks.lan:7878   →  Vikunja
http://wiki.lan:7878    →  Outline
```

---

## Useful commands

```bash
# View logs
docker compose logs -f nginx
docker compose logs -f vikunja
docker compose logs -f outline

# Restart a service
docker compose restart vikunja

# Stop everything
docker compose down

# Update to latest images
docker compose pull && docker compose up -d
docker compose exec outline yarn db:migrate
```

---

## Later: add HAProxy + SSL

When you're ready to add SSL via OPNsense HAProxy (so you get
`https://tasks.yourdomain.com` instead of `http://tasks.lan:7878`),
see `docs/deployment.md` and `docs/haproxy-opnsense.md`.

The only change to this stack will be:
- Update `VIKUNJA_PUBLIC_URL` and `OUTLINE_PUBLIC_URL` to `https://`
- Remove the Nginx container (HAProxy takes its role)
- Expose Vikunja on 3456 and Outline on 3000 directly to OPNsense
