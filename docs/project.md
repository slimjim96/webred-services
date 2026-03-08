## Project: webred-services

Goal: Self-hosted productivity stack on Proxmox homelab

Infrastructure:
- Proxmox host with LXC containers
- OPNsense router/firewall
- HAProxy for SSL termination + reverse proxy
- ACME certs via Let's Encrypt
- Personal domain proxied through Cloudflare

Current task: Dockerized self-hosted notes/tasks stack
- Vikunja (task management)
- Outline (wiki/notes)
- Targeting deployment on Proxmox LXC
- Services repo: webred-services

OS: Debian (desktop for dev/testing), Proxmox target for prod