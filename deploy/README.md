# Deploying cally.bond to the VPS

Docker Compose deployment for the cally.bond SaaS. The **runner server is the application server**, and **Postgres runs natively on the host** (no DB container). All credentials and secrets live in `/var/www/public/cally/.env.master`.

## Architecture

```
Internet
   |
   v
nginx (host)  :80/:443 (Let's Encrypt TLS)
   |
   +-- /api/v2  --> cally_api   (NestJS API v2, :5555, container)
   +-- /        --> cally_web   (Next.js, :3000, container)
                       |
                       +-- cally_redis (Redis 7, container)
                       +-- Postgres 17  (NATIVE on host, e.g. :5432)
```

- No container ports are exposed to the host. nginx is the only public entry point.
- The web/api containers reach the host Postgres via `host.docker.internal` (mapped in `docker-compose.prod.yml`).

## Files

| File | Purpose |
|---|---|
| `docker-compose.prod.yml` | Production stack (redis, web, api) — no DB container |
| `nginx/cally.bond.conf` | nginx reverse proxy + TLS config |
| `scripts/setup-vps.sh` | One-time VPS setup (docker, nginx, certbot, ufw, host Postgres db/user) |
| `scripts/deploy.sh` | Build + migrate + deploy (manual run on the VPS) |
| `.github/workflows/deploy.yml` | CI/CD: on push to `main`, SSH into the VPS and deploy |

## `.env.master`

Lives at `/var/www/public/cally/.env.master`. It is the single source of truth for secrets and is copied to `.env.prod` at deploy time. Required variables:

```env
# Host Postgres (native). Containers reach the host via host.docker.internal.
DATABASE_URL="postgresql://cally:<password>@host.docker.internal:5432/cally"

# App URLs
NEXT_PUBLIC_WEBAPP_URL="https://cally.bond"
NEXT_PUBLIC_API_V2_URL="https://cally.bond/api/v2"
NEXTAUTH_URL="https://cally.bond"
NEXTAUTH_SECRET="<openssl rand -base64 32>"
CALENDSO_ENCRYPTION_KEY="<openssl rand -base64 24>"
ALLOWED_HOSTNAMES='"cally.bond","www.cally.bond"'
CALCOM_TELEMETRY_DISABLED=1

# Email (SMTP) — e.g. Resend / SES / Postmark
EMAIL_FROM="notifications@cally.bond"
EMAIL_SERVER_HOST="smtp.resend.com"
EMAIL_SERVER_PORT=465
EMAIL_SERVER_USER="resend"
EMAIL_SERVER_PASSWORD="<resend_key>"

# Cron (used by /api/cron/* routes)
CRON_API_KEY="<openssl rand -hex 16>"

# Billing (only when enabling Stripe)
STRIPE_API_KEY=
STRIPE_WEBHOOK_SECRET=
STRIPE_PRICE_ID_STARTER=
STRIPE_PRICE_ID_ESSENTIALS=
STRIPE_PRICE_ID_ENTERPRISE=
```

> Keep `.env.master` out of git (it is under the app dir, not the repo). Its `DATABASE_URL` must match the native Postgres credentials you set in `setup-vps.sh`.

## One-time setup

1. Point `cally.bond` and `www.cally.bond` DNS A records at the VPS IP.
2. Clone the repo to `/var/www/public/cally`.
3. Run:
   ```bash
   sudo bash deploy/scripts/setup-vps.sh
   ```
   Installs Docker, nginx, certbot, UFW, creates the host Postgres db/user, installs the nginx site, and issues the TLS cert.
4. Create `/var/www/public/cally/.env.master` with the values above.

## Deploy

**Automatic (CI/CD):** push to `main` → `.github/workflows/deploy.yml` SSHes into the VPS (using the repo secrets `VPS_HOST`, `VPS_USER`, `VPS_SSH_KEY`), pulls the code, copies `.env.master` → `.env.prod`, builds the images, runs migrations, and restarts the stack.

**Manual:** on the VPS,
```bash
cd /var/www/public/cally && bash deploy/scripts/deploy.sh
```

## Operations

```bash
cd /var/www/public/cally
alias dc="docker compose -f docker-compose.prod.yml --env-file .env.prod"

# Logs
$dc logs -f calcom
$dc logs -f calcom-api

# Migrations only
$dc run --rm calcom npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma

# Shell into the web container
$dc exec calcom sh

# Backup the host Postgres database (native)
sudo -u postgres pg_dump cally | gzip > backup-$(date +%F).sql.gz
```

## Cron jobs

Cron jobs are HTTP routes under `/api/cron/*` (guarded by `CRON_API_KEY`). Add to the VPS crontab (as the app user):

```cron
# Booking reminders (hourly)
0 * * * * curl -s -H "Authorization: $CRON_API_KEY" https://cally.bond/api/cron/bookingReminder >/dev/null
# Timezone change checks (hourly)
15 * * * * curl -s -H "Authorization: $CRON_API_KEY" https://cally.bond/api/cron/changeTimeZone >/dev/null
# Calendar subscription sync (every 30 min)
*/30 * * * * curl -s -H "Authorization: $CRON_API_KEY" https://cally.bond/api/cron/calendar-subscriptions >/dev/null
```

Available routes: `ls apps/web/app/api/cron/`. The route compares the raw `Authorization` header (or `?apiKey=` query param) against `CRON_API_KEY`.

## GitHub Actions secrets

Set these in the repo settings for the CI/CD pipeline:

| Secret | Value |
|---|---|
| `VPS_HOST` | The VPS public IP |
| `VPS_USER` | SSH username on the VPS |
| `VPS_SSH_KEY` | Private SSH key (add the public key to the VPS `~/.ssh/authorized_keys`) |

## Notes

- `NEXT_PUBLIC_WEBAPP_URL` is baked into the image at build time as `https://cally.bond` (the Dockerfile also supports runtime replacement if it ever changes).
- The `calcom-api` (NestJS) service powers the public API v2 and Stripe webhooks. Keep it running if you enable billing or the public API.
- UFW allows only SSH + Nginx Full (set by `setup-vps.sh`).
