#!/usr/bin/env bash
# Build and deploy the cally.bond stack on the VPS (manual run).
# The runner server IS the application server. Postgres runs natively on the host;
# its credentials live in /var/www/public/cally/.env.master.
#
# Run from the repo root (/var/www/public/cally):
#   bash deploy/scripts/deploy.sh
set -euo pipefail

APP_DIR="/var/www/public/cally"
ENV_MASTER="$APP_DIR/.env.master"
ENV_PROD="$APP_DIR/.env.prod"

cd "$APP_DIR"

if [ ! -f "$ENV_MASTER" ]; then
  echo "ERROR: $ENV_MASTER not found. Create it with the host Postgres credentials (DATABASE_URL) and app secrets."
  exit 1
fi

echo "==> Pulling latest code"
git pull origin main

echo "==> Building production env from $ENV_MASTER"
# .env.master holds the native Postgres credentials and all app secrets.
# DATABASE_URL must point at the host Postgres, e.g.
#   postgresql://user:pass@host.docker.internal:5432/cally
# (containers reach the host via host.docker.internal, mapped in docker-compose.prod.yml)
cp "$ENV_MASTER" "$ENV_PROD"

echo "==> Building Docker images (takes several minutes)"
docker compose -f docker-compose.prod.yml --env-file "$ENV_PROD" build

echo "==> Applying database migrations (host Postgres)"
docker compose -f docker-compose.prod.yml --env-file "$ENV_PROD" run --rm calcom \
  npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma

echo "==> Starting stack"
docker compose -f docker-compose.prod.yml --env-file "$ENV_PROD" up -d

echo "==> Pruning old images"
docker image prune -f >/dev/null || true

echo "==> Status"
docker compose -f docker-compose.prod.yml --env-file "$ENV_PROD" ps

echo ""
echo "Deployment complete. https://cally.bond (via nginx)"
echo "Logs: docker compose -f docker-compose.prod.yml --env-file $ENV_PROD logs -f"
