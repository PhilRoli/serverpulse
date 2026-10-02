#!/bin/bash
set -euo pipefail

TARGET="${1:?Usage: deploy.sh user@host}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DIR=/opt/apps/metrics-agent

echo "Syncing agent to $TARGET:$DIR ..."
rsync -az --delete \
    --exclude .env --exclude .env.example --exclude .git \
    --exclude test_agent.py --exclude __pycache__ \
    "$HERE/" "$TARGET:$DIR/"

ssh "$TARGET" bash -s <<'REMOTE'
set -euo pipefail
cd /opt/apps/metrics-agent
grep -q '^METRICS_TOKEN=.' .env || { echo "METRICS_TOKEN missing in .env" >&2; exit 1; }
grep -q '^METRICS_TOKEN=change-me$' .env && { echo "METRICS_TOKEN is still the placeholder" >&2; exit 1; }
chmod 600 .env
[ -n "$(tail -c1 .env)" ] && echo >> .env
GID="$(stat -c %g /var/run/docker.sock)"
if grep -q '^DOCKER_GID=' .env; then
    sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$GID/" .env
else
    echo "DOCKER_GID=$GID" >> .env
fi
docker compose up -d --build
for _ in 1 2 3 4 5; do
    if curl -fsS localhost:4099/health; then echo; exit 0; fi
    sleep 2
done
echo "health check failed" >&2
docker compose logs --tail 30
exit 1
REMOTE

echo "Deployed to $TARGET"
