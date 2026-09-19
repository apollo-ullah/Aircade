# Wii-inspired sports interface

The native SwiftUI / SceneKit app now uses white panels with subtle corners, blue controls, clean system type, a bright outdoor sports court, and translucent score / energy displays. Launcher, gameplay HUD, pause, results, controller setup, calibration, and the training lab share the light palette. All court scenery is decorative; target positions, hitboxes, timing, scoring, difficulty, and tracking logic remain unchanged.

References: user-provided Wii Sports tennis, Resort archery, and Sports Club baseball screenshots; Nintendo's official Wii Sports imagery (https://www.nintendo.co.jp/wii/rspj/whatis/index.html); Wii Sports menu screenshot index (https://www.mobygames.com/game/25099/wii-sports/screenshots/). No Nintendo graphics or audio are bundled.

Run `./scripts/run.sh` on macOS. The existing demo and smoke-test modes work without AirPods. `AIRCADE_LOG_DIRECTORY` optionally redirects diagnostic and smoke output; normal launches retain the existing Application Support location.

## Refined Wii Sports direction

Replaced rounded display typography with standard system type and reduced panel/button radii. Gameplay now uses compact translucent scoreboards floating over the scene and a transparent footer. The environment uses procedural turf texture, soft sky imagery, smaller angular trees, spectator stands, and simpler court markings. HDR tone mapping is disabled to keep the outdoor palette bright. These are presentation-only changes; scoring and motion geometry are unchanged.

## Validation

Release build and `git diff --check` passed. Native demo play was inspected for scoring, results, replay, pause, and resume. XCTest was unavailable in the installed Command Line Tools, so the unit suite could not run. Physical AirPods and camera tracking were not revalidated.
