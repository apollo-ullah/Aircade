#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
swiftc -parse-as-library -I .build/arm64-apple-macosx/release/Modules \
  Sources/Aircade/PlayerSession.swift Sources/Aircade/BadgeNameReader.swift scripts/checks/StationClientCheck.swift \
  .build/arm64-apple-macosx/release/MotionCore.build/*.o -o .local/station-client-check
cd server
AIRCADE_NATIVE_CHECK="$PWD/../.local/station-client-check" npm test
