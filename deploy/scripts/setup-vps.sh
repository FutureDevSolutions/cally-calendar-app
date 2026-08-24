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
ufw allow 'Nginx Full'
ufw --force enable

echo "==> Installing nginx site config"
cp deploy/nginx/cally.bond.conf /etc/nginx/sites-available/cally.bond.conf
ln -sf /etc/nginx/sites-available/cally.bond.conf /etc/nginx/sites-enabled/cally.bond.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Setting up Let's Encrypt SSL (interactive)"
echo "Make sure DNS for $DOMAIN points to this server's IP first."
echo "Press Enter when ready, then follow the prompts."
read -r
certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --redirect --agree-tos --no-eff-email || \
  echo "Certbot failed — run manually: certbot --nginx -d $DOMAIN -d www.$DOMAIN"

echo "==> Enabling certbot auto-renewal"
systemctl enable --now certbot.timer

echo ""
echo "Setup complete. Next steps:"
echo "  1. Clone the repo into $APP_DIR"
echo "  2. Create $APP_DIR/.env.master  (see deploy/README.md for the required variables;"
echo "     DATABASE_URL must point at the host Postgres, e.g.:"
echo "     DATABASE_URL=\"postgresql://cally:<password>@host.docker.internal:5432/cally\")"
echo "  3. sudo bash deploy/scripts/deploy.sh   (or push to main to trigger the CI/CD pipeline)"
