# Deploying https://cally.bond (FDS-DnS + app host)

## Architecture

```
Internet
   |
   v
FDS-DnS nginx  :443  (TLS at /etc/nginx/certs/cally.bond.*)
   |  proxy_pass http://192.168.194.35:3001
   v
App host 192.168.194.35
   |
   +-- host :3001  -->  cally_web  (Next.js, container :3000)
   +-- cally_api   (NestJS API v2, container :5555, internal / rewritten)
   +-- cally_redis (Redis 7)
   +-- Postgres    (native on host :5432)
```

- **Domain / TLS / edge proxy:** [FDS-DnS](https://github.com/) `ServerDNS/sites-available/cally.bond.conf` (already listed in FDS-DnS deploy workflow).
- **App port:** `3001` on host `192.168.194.35` (must match FDS-DnS `proxy_pass`).
- Secrets live in `/var/www/public/cally/.env.master` (copied to `.env.prod` on deploy).

## Files

| File | Purpose |
|---|---|
| `docker-compose.prod.yml` | Production stack; publishes `3001:3000` for FDS-DnS |
| `.env.prod.example` | Template for production env |
| `deploy/nginx/cally.bond.conf` | Mirror of FDS-DnS config (edit FDS-DnS as source of truth) |
| `deploy/scripts/setup-vps.sh` | One-time app-host setup |
| `deploy/scripts/deploy.sh` | Build + migrate + up |
| `.github/workflows/deploy.yml` | CI/CD to the app host |

## One-time: FDS-DnS

1. Ensure `cally.bond` DNS A record points at the FDS-DnS / public edge IP.
2. Certs exist: `/etc/nginx/certs/cally.bond.pem` + `.key`.
3. Push FDS-DnS so `cally.bond.conf` is enabled (already in the domains list).
4. Confirm proxy target is `http://192.168.194.35:3001`.

## One-time: app host (192.168.194.35)

```bash
sudo bash deploy/scripts/setup-vps.sh
# Clone repo to /var/www/public/cally
cp .env.prod.example /var/www/public/cally/.env.master
# Edit .env.master — set DATABASE_URL, NEXTAUTH_SECRET, CALENDSO_ENCRYPTION_KEY, email
bash deploy/scripts/deploy.sh
```

Open firewall for the edge nginx (if UFW is on):

```bash
sudo ufw allow from 192.168.194.0/24 to any port 3001 proto tcp
# or: sudo ufw allow 3001/tcp
```

## Deploy

```bash
cd /var/www/public/cally && bash deploy/scripts/deploy.sh
```

Or push to `main` if GitHub Actions secrets (`VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`) are set.

## Required `.env.master` keys

See `.env.prod.example`. Minimum:

```env
DATABASE_URL="postgresql://cally:<password>@host.docker.internal:5432/cally"
DATABASE_DIRECT_URL="postgresql://cally:<password>@host.docker.internal:5432/cally"
NEXT_PUBLIC_WEBAPP_URL="https://cally.bond"
NEXT_PUBLIC_API_V2_URL="https://cally.bond/api/v2"
NEXTAUTH_URL="https://cally.bond"
NEXTAUTH_SECRET="<openssl rand -base64 32>"
CALENDSO_ENCRYPTION_KEY="<openssl rand -base64 24>"
ALLOWED_HOSTNAMES='"cally.bond","www.cally.bond","*.cally.bond"'
NEXT_PUBLIC_APP_NAME="Cally"
CALCOM_TELEMETRY_DISABLED=1
```

## Ops

```bash
cd /var/www/public/cally
alias dc="docker compose -f docker-compose.prod.yml --env-file .env.prod"

$dc ps
$dc logs -f calcom
curl -I http://127.0.0.1:3001   # app host health
# Then check https://cally.bond via FDS-DnS
```

## Notes

- Changing the published port means updating **both** `docker-compose.prod.yml` and FDS-DnS `cally.bond.conf`.
- `NEXT_PUBLIC_WEBAPP_URL` is baked at Docker build time as `https://cally.bond`.
- Local `yarn dev` still uses `.env` with `http://localhost:3000` — do not point local `.env` at production unless you intend to.
