#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
if [[ -f "${AIRCADE_STATION_CONFIG:-.local/station.json}" ]]; then
  node scripts/prepare-launch.mjs
fi
open build/Aircade.app
