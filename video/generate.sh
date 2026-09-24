#!/usr/bin/env bash
# Generates every Higgsfield asset for the teaser. Idempotent: skips any asset that already exists.
# Requires: higgsfield CLI (logged in), jq, curl.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p generated

# Extract the first media URL from a `--wait --json` result and download it.
# $1 = json file, $2 = destination
fetch() {
  local json="$1" dest="$2" url
  url=$(jq -r '
    [.. | objects | (.url? // empty), (.results? // empty | .. | objects | .url? // empty)]
    | flatten | map(select(type=="string" and (test("\\.(png|jpe?g|webp|mp4|mov)(\\?|$)")))) | first // empty
  ' "$json")
  if [ -z "$url" ]; then
    echo "!! no media url found in $json" >&2
    return 1
  fi
  curl -fsSL "$url" -o "$dest"
  echo "   -> $dest"
}

gen() {
  # gen <dest> <model> [args...]
  local dest="$1" model="$2"; shift 2
  if [ -s "$dest" ]; then echo "== $dest exists, skipping"; return; fi
  echo "== $dest  ($model)"
  local json="generated/$(basename "${dest%.*}").json"
  higgsfield generate create "$model" "$@" --wait --wait-timeout 25m --json > "$json"
  fetch "$json" "$dest"
}

# ---------- Stills (GPT Image 2.5) ----------

gen generated/intro-still.png gpt_image_2_5 \
  --aspect_ratio 16:9 --resolution 2k \
  --prompt "Photograph, 2006 family living room at golden hour. A boxy CRT television on a low wooden TV stand, screen dark. Beside it stands a small glossy white game console with a softly glowing blue slot. On the beige shag carpet in the foreground lies a glossy white motion-sensing remote with a wrist strap. Warm window light, dust motes in the air, slight film grain, camcorder home-video warmth, shallow depth of field, nostalgic."

gen generated/earbuds-still.png gpt_image_2_5 \
  --aspect_ratio 16:9 --resolution 2k \
  --prompt "Photograph, extreme close-up on the same beige shag carpet in warm golden-hour window light. A pair of white wireless earbuds sit in an open white glossy charging case, catching soft plastic highlights. Shallow depth of field, dust motes, slight film grain, nostalgic warmth, product-photography clarity."

gen generated/channel-grid.png gpt_image_2_5 \
  --aspect_ratio 16:9 --resolution 2k \
  --prompt "Flat clean UI illustration of a 2006-era game console home menu. A 4 by 3 grid of rounded glossy rectangular channel tiles on a soft white to light-grey gradient background. Tiles show simple colourful icons: a tennis ball, a bowling pin, a golf flag, a boxing glove, a weather sun, a news paper, a photo frame, a shopping bag; the rest are empty light-grey tiles. Subtle blue accent glow, glossy highlights, thin grey borders, small round hand cursor. No brand names, no text."

gen generated/endcard.png gpt_image_2_5 \
  --aspect_ratio 16:9 --resolution 2k \
  --prompt "Flat clean UI end card in the style of a 2006 game console channel tile. One large rounded glossy white rectangular tile centred on a soft light-grey gradient background with a faint blue glow. Inside the tile, the word AIRCADE in bold rounded sans-serif dark charcoal letters, centred, with a small white wireless earbud icon to the left of the text. Beneath it, smaller grey text: Your earbuds are the controller. Glossy highlight across the tile, thin grey border, minimal, crisp typography."

# ---------- Motion (Seedance 2.5, anchored to the approved stills) ----------

gen generated/intro.mp4 seedance_2_5 \
  --mode omni_reference --start-image generated/intro-still.png \
  --duration 4 --resolution 1080p --aspect_ratio 16:9 \
  --prompt "Slow steady dolly push-in toward the television. Dust motes drift through the warm window light. Halfway through, the CRT screen flickers and glows on with a soft white light that spills onto the carpet. Handheld camcorder feel, gentle, nostalgic."

gen generated/remote-to-earbuds.mp4 seedance_2_5 \
  --mode omni_reference --start-image generated/intro-still.png --end-image generated/earbuds-still.png \
  --duration 4 --resolution 1080p --aspect_ratio 16:9 \
  --prompt "The camera glides smoothly down and forward toward the white remote on the carpet. Its glossy plastic catches the light and blooms into a soft white glow, then the glow settles and resolves into a pair of white wireless earbuds in an open charging case on the same carpet. One continuous fluid move, warm light throughout."

gen generated/channel-wipe.mp4 seedance_2_5 \
  --mode omni_reference --start-image generated/channel-grid.png \
  --duration 4 --resolution 1080p --aspect_ratio 16:9 \
  --prompt "The small hand cursor glides across the grid and hovers over the tennis tile. The tile pulses once, then zooms rapidly toward the camera, filling the frame, and the picture washes out to pure white. Clean flat UI motion graphics, snappy easing."

echo "All assets present in generated/"
