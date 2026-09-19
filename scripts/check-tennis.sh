#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
swiftc -parse-as-library -I .build/arm64-apple-macosx/release/Modules \
  scripts/checks/TennisMatchCheck.swift \
  .build/arm64-apple-macosx/release/MotionCore.build/*.o -o .local/tennis-match-check
.local/tennis-match-check
