#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
swift build -c release
build_path="$(swift build -c release --show-bin-path)"
if [ -f "$build_path/MotionCore.o" ]; then
  module_path="$build_path"
  core_objects=("$build_path/MotionCore.o")
else
  module_path="$build_path/Modules"
  core_objects=("$build_path/MotionCore.build/"*.o)
fi
swiftc -parse-as-library -I "$module_path" \
  Sources/Aircade/PlayerSession.swift Sources/Aircade/RunContext.swift Sources/Aircade/Leaderboard.swift \
  Sources/Aircade/BadgeNameReader.swift Sources/Aircade/BadgeScanner.swift scripts/checks/StationClientCheck.swift \
  "${core_objects[@]}" -o .local/station-client-check
cd server
AIRCADE_NATIVE_CHECK="$PWD/../.local/station-client-check" npm test
