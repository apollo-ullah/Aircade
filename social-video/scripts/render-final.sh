#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
mezzanine="$project_dir/out/aircade-social-mezzanine.mp4"
final="$project_dir/out/aircade-social-final.mp4"

mkdir -p "$project_dir/out"
"$project_dir/scripts/prepare-audio.sh"

cd "$project_dir"
npx remotion render src/index.ts AircadeOverview "$mezzanine" \
  --codec=h264 \
  --crf=14 \
  --pixel-format=yuv420p \
  --color-space=bt709 \
  --audio-bitrate=320k

# Preserve the rendered picture bit-for-bit while applying a social-platform
# loudness target and true-peak ceiling to the mixed audio.
ffmpeg -hide_banner -loglevel warning -y \
  -i "$mezzanine" \
  -map 0:v:0 -map 0:a:0 \
  -c:v copy \
  -af "loudnorm=I=-14:LRA=7:TP=-1.0" \
  -c:a aac -b:a 256k -ar 48000 \
  -shortest \
  -movflags +faststart \
  "$final"

printf '%s\n' "$final"
