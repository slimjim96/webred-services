# HAProxy Setup on OPNsense

## Overview

Traffic path:
```
LAN device
         → OPNsense LAN:443 (HAProxy, SSL termination)
         → Debian VM (Docker services)
             ├── :3456  Vikunja
             └── :3000  Outline
```

HAProxy terminates TLS. Backends receive plain HTTP. Fully self-hosted,
no internet exposure required.

---

## Prerequisites

- OPNsense with **os-haproxy** plugin installed
  (`System → Firmware → Plugins → os-haproxy`)
- OPNsense **ACME client** plugin installed (if using Let's Encrypt)
  (`System → Firmware → Plugins → os-acme-client`)
- Unbound DNS host overrides configured (see `docs/deployment.md` Part 3)
- SSL cert issued (see `docs/deployment.md` Part 2)

---

## 1. SSL Certificate

See `docs/deployment.md` Part 2 for cert options (Let's Encrypt DNS-01
or local CA via mkcert). Once issued, OPNsense references it automatically
in the HAProxy frontend SSL binding.

---

## 2. HAProxy — Real Servers (backends)

`Services → HAProxy → Real Servers → Add`

| Field       | Vikunja              | Outline              |
|-------------|----------------------|----------------------|
| Name        | `vikunja`            | `outline`            |
| Address     | `<Debian VM IP>`     | `<Debian VM IP>`     |
| Port        | `3456`               | `3000`               |
| Mode        | Active               | Active               |
| Health check | HTTP                | HTTP                 |
| Health URI  | `/api/v1/info`       | `/_health`           |
| Health expect | Status 200         | Status 200           |

---

## 3. HAProxy — Backend Pools

`Services → HAProxy → Backend Pools → Add`

| Field              | Vikunja                | Outline                |
|--------------------|------------------------|------------------------|
| Name               | `pool_vikunja`         | `pool_outline`         |
| Mode               | HTTP                   | HTTP                   |
| Servers            | `vikunja`              | `outline`              |
| Balance            | Round Robin            | Round Robin            |

---

## 4. HAProxy — Conditions (ACLs)

`Services → HAProxy → Rules & Checks → Conditions → Add`

| Name              | Test type          | Value                    |
|-------------------|--------------------|--------------------------|
| `is_vikunja`      | Host matches       | `tasks.yourdomain.com`   |
| `is_outline`      | Host matches       | `wiki.yourdomain.com`    |

---

## 5. HAProxy — Rules (use_backend)

`Services → HAProxy → Rules & Checks → Rules → Add`

| Name               | Condition     | Execute function | Backend pool   |
|--------------------|---------------|------------------|----------------|
| `route_vikunja`    | `is_vikunja`  | Use backend      | `pool_vikunja` |
| `route_outline`    | `is_outline`  | Use backend      | `pool_outline` |

---

## 6. HAProxy — Frontend (HTTPS)

`Services → HAProxy → Virtual Services → Public Services → Add`

| Field                  | Value                                         |
|------------------------|-----------------------------------------------|
| Name                   | `ft_https`                                    |
| Listen addr            | WAN (or `0.0.0.0`)                            |
| Port                   | `443`                                         |
| SSL offloading         | Enabled                                       |
| Certificate            | (select your ACME cert)                       |
| Default backend        | (leave empty or set a deny backend)           |
| Rules                  | `route_vikunja`, `route_outline`              |

**Advanced settings (paste into "Custom options"):**
```
http-request set-header X-Forwarded-Proto https
http-request set-header X-Real-IP %[src]
```

---

## 7. HAProxy — Frontend (HTTP redirect)

`Services → HAProxy → Virtual Services → Public Services → Add`

| Field       | Value           |
|-------------|-----------------|
| Name        | `ft_http`       |
| Port        | `80`            |
| SSL         | Disabled        |
| Default backend | (none)      |

**Custom options:**
```
redirect scheme https code 301
```

---

## 8. Enable & verify

```bash
# On OPNsense shell or via SSH
haproxy -c -f /usr/local/etc/haproxy.conf   # config check

# From external machine
curl -I https://tasks.yourdomain.com
curl -I https://wiki.yourdomain.com
```

---

## Security hardening (post-setup)

### Firewall — restrict port 3000/3456 on Debian VM
The Docker containers only need to be reachable from OPNsense (HAProxy).
On the Debian VM, optionally use ufw or iptables to only allow those ports
from OPNsense's LAN IP:
```bash
sudo ufw allow from <OPNsense_LAN_IP> to any port 3456
sudo ufw allow from <OPNsense_LAN_IP> to any port 3000
sudo ufw allow ssh
sudo ufw enable
```

### OPNsense — block direct VM access from LAN (optional)
If you want to force all traffic through HAProxy (so hostnames and SSL are
always used), add a LAN firewall rule that blocks direct access to the VM's
port 3000 and 3456 from LAN clients.
