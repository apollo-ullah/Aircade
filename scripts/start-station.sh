#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Local secrets stay in the ignored repository-root .env file. Export them for
# the Node station without ever copying the Baseten key into app configuration.
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

mkdir -p .local/mongo
if ! curl -fsS http://127.0.0.1:8787/api/health >/dev/null 2>&1; then
  if ! lsof -iTCP:27017 -sTCP:LISTEN >/dev/null 2>&1; then
    command -v mongod >/dev/null || { echo 'Install MongoDB Community, then run this script again.'; exit 1; }
    mongod --dbpath "$PWD/.local/mongo" --bind_ip 127.0.0.1 --port 27017 --logpath "$PWD/.local/mongo.log" --fork
  fi
  cd server
  npm ci --cache ../.local/npm-cache
  exec npm start
fi
echo 'Station already running: http://127.0.0.1:8787'
