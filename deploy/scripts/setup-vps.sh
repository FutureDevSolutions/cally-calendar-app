#!/usr/bin/env bash
# One-time setup for an Ubuntu 22.04/24.04 VPS hosting cally.bond.
# The runner server IS the application server. Postgres is installed NATIVELY
# on the host (not in a container); its credentials go in .env.master.
# Run as: sudo bash deploy/scripts/setup-vps.sh
set -euo pipefail

DOMAIN="cally.bond"
APP_DIR="/var/www/public/cally"

echo "==> Installing system packages (docker, nginx, certbot, postgres, git)"
apt-get update
apt-get install -y docker.io docker-compose-v2 nginx certbot python3-certbot-nginx ufw git postgresql

echo "==> Setting up Docker"
systemctl enable --now docker
usermod -aG docker "$USER"

echo "==> Creating app directory"
mkdir -p "$APP_DIR"
chown "$USER":"$USER" "$APP_DIR"
echo "Clone the repo into $APP_DIR (e.g. git clone <repo> $APP_DIR)."

echo "==> Creating the host Postgres database + user"
# Creates a dedicated DB and user for cally. Adjust the name/password, then
# write the same values into $APP_DIR/.env.master as DATABASE_URL.
sudo -u postgres psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cally') THEN
      CREATE ROLE cally LOGIN PASSWORD 'cally';
   END IF;
END
$$;
SELECT 'CREATE DATABASE cally OWNER cally'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cally')\gexec
SQL
echo "Postgres role 'cally' / db 'cally' created (default password 'cally' — change it)."

echo "==> Configuring UFW firewall"
ufw allow OpenSSH
# App is reached via FDS-DnS edge nginx -> this host :3001 (not local public TLS)
ufw allow 3001/tcp comment 'cally.bond via FDS-DnS'
# Optional: if you also terminate TLS on this host
ufw allow 'Nginx Full' || true
ufw --force enable

echo "==> Skipping local nginx site install (TLS/proxy owned by FDS-DnS -> :3001)"
echo "    Canonical nginx: FDS-DnS/ServerDNS/sites-available/cally.bond.conf"
# Keep a local copy for reference only
mkdir -p /etc/nginx/sites-available
cp deploy/nginx/cally.bond.conf /etc/nginx/sites-available/cally.bond.conf.fds-dns-reference || true

echo ""
echo "Setup complete. Next steps:"
echo "  1. Clone the repo into $APP_DIR"
echo "  2. Create $APP_DIR/.env.master from .env.prod.example"
echo "     DATABASE_URL=\"postgresql://cally:<password>@host.docker.internal:5432/cally\""
echo "  3. bash deploy/scripts/deploy.sh"
echo "  4. Confirm FDS-DnS proxies https://cally.bond -> http://192.168.194.35:3001"
echo "  5. Push FDS-DnS if you changed cally.bond.conf"
