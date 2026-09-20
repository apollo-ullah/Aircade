#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# A deliberate command-line override takes precedence over .env defaults.
station_requested_port="${PORT-}"
station_requested_host="${HOST-}"
station_requested_config="${AIRCADE_STATION_CONFIG-}"

# Local secrets stay in the ignored repository-root .env file. Export them for
# the Node station without ever copying the Baseten key into app configuration.
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi
[[ -z "$station_requested_port" ]] || export PORT="$station_requested_port"
[[ -z "$station_requested_host" ]] || export HOST="$station_requested_host"
[[ -z "$station_requested_config" ]] || export AIRCADE_STATION_CONFIG="$station_requested_config"

station_launch="$(node server/station-config.mjs)"
IFS=$'\t' read -r HOST PORT station_url AIRCADE_STATION_CONFIG <<< "$station_launch"
export HOST PORT AIRCADE_STATION_CONFIG

if station_health="$(curl -fsS --max-time 3 "$station_url/api/health" 2>/dev/null)"; then
  if printf '%s' "$station_health" | node --input-type=module -e 'let input=""; for await (const chunk of process.stdin) input+=chunk; try { const health=JSON.parse(input); process.exit(health.ok===true && health.contractVersion==="tactical-v1" ? 0 : 1); } catch { process.exit(1); }'; then
    echo "Station already running: $station_url (tactical-v1)"
    exit 0
  fi
  echo "A station is listening at $station_url but does not advertise tactical-v1. Restart that station before continuing."
  exit 1
fi
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $PORT is occupied but its station health check failed. Resolve that process or choose another PORT."
  exit 1
fi

mkdir -p .local/mongo
if ! lsof -iTCP:27017 -sTCP:LISTEN >/dev/null 2>&1; then
    if command -v mongod >/dev/null; then
      mongod --dbpath "$PWD/.local/mongo" --bind_ip 127.0.0.1 --port 27017 --logpath "$PWD/.local/mongo.log" --fork
    elif command -v docker >/dev/null && docker info >/dev/null 2>&1; then
      if docker container inspect aircade-mongo >/dev/null 2>&1; then
        docker start aircade-mongo >/dev/null
      else
        docker run -d --name aircade-mongo -p 127.0.0.1:27017:27017 -v aircade-mongo-data:/data/db mongo:8.0 >/dev/null
      fi
    else
      echo 'Start Docker Desktop or install MongoDB Community, then run this script again.'; exit 1
    fi
fi
cd server
if ! npm ls --omit=dev --all >/dev/null 2>&1; then
  npm ci --cache ../.local/npm-cache
fi
exec npm start
