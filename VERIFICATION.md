# Verification — 2026-09-19

## Software checks

- Release app bundle built successfully and ad-hoc signature verified.
- Six unit tests passed: relative rotation/recentering, axis basis, quaternion sign, time-based smoothing, continuity resets, swing hysteresis/cooldown.
- Bundled simulation smoke test passed with 179 synthetic samples. SceneKit saber snapshot inspected.
- Launch via `open build/Aircade.app`. A direct executable launch encountered macOS TCC attribution failure; the supported launch path is the app bundle. Simulation was subsequently isolated from Core Motion calls.

## Real device observations

The running app received real **left AirPod** motion at approximately **50 Hz**, with permission allowed. More than 1,400 real samples were observed. The live CSV includes nonzero angular velocity and disconnect/reconnect events; after a gap the saber requires explicit recentering.

This confirms the real sensor/API path, not the physical handheld condition. The user must report the worn/held state and complete a labelled two-minute trial. At the time of this note no two-minute handheld trial had completed. Do not claim milestone 1 hardware proof or real grip-axis mapping is fully verified yet.

Logs live outside the repository in `~/Library/Application Support/Aircade/Logs/`. Simulation logs and real logs have distinct filenames and mode columns. Test JSON reports record the physical condition as user-reported.

## Prototype 02 — training arena

The user subsequently confirmed handheld input works with Automatic Ear Detection disabled. A repeatable physical grip is still needed; the new three-pose calibration measures the sensor-to-game rotation basis and saves it per source earbud.

- Release build and signature verification passed.
- All 15 unit tests passed. New coverage includes between-sample rotational cuts, translational cuts without rotation, stationary contact, distant misses, stale-pose rejection, guard position/angle, arbitrary grip calibration, and invalid calibration motions.
- The updated bundled smoke test passed with 182 simulated samples and 3 scored geometric cuts. Inspected both the rendered saber scene (including split target/trail) and the native UI capture. The native UI bitmap does not include SceneKit's Metal surface; that surface was verified via the separate scene snapshot.
- Real AirPods, learned grip mapping, and camera input remain separate from synthetic smoke evidence. The updated live app was reopened for user verification; camera permission and closed-hand detection have not yet been verified with the Kiyo.
- Camera landmarks map to a 2D play plane. This is not full 6DoF or metric 3D tracking. Glove/grip occlusion, fast blur, and multiple visible hands may reduce reliability.
- There is no physical haptic output or trained boss in this build. CUT/GLANCE/PARRY/DAMAGE events are available for the next integration.

## Animated calibration guide

Added a large three-step calibration sheet with a looping wrist/handle illustration, target outlines, direction arrows, step progress, replay, and explicit pose-save buttons (Return shortcut). Left tilt uses the user's point of view; forward tilt uses a labelled side view with the user and Mac. Capture remains manual and unavailable without fresh real motion. Release build passed; native rendered calibration panels were inspected for layout, direction, contrast, and clipping. No sensor-mapping algorithm changed.

## Prototype 03 — Neon Rush

The user confirmed the existing calibration and block hitting work well with their controller. Built one complete local arcade game on that working input/collision path: launcher, controller setup, instructions, two difficulties, countdown, three escalating rounds, score/combo multipliers, directional cuts, avoidable hazards, energy, pause/reconnect, results/rank, replay, and per-difficulty local high scores.

- All **23 unit tests passed**. Eight new game tests cover countdown and pause timing, invalid time, early/slow/glancing contacts, duplicate scoring, misses, directional errors, stationary hazard contact, seeded targets, multiplier progression, zero-energy termination, and complete 60-second runs/replays on both difficulties.
- Release build and ad-hoc signature checks passed.
- Native game integration smoke passed with **13 geometric cuts, 2,500 points, and 1,825 simulated samples after reconnect**. Stopping the stream froze the game; restarting resumed through a countdown and reached results. Demo high score remained unchanged.
- Final test-lab regression smoke also passed: **180 simulated samples and three geometric cuts**.
- Inspected native menu, HUD, pause, and result bitmaps plus separate SceneKit captures. Fixed truncated menu copy at the smaller window size and reduced the arena lighting so it does not compete with targets. Native cached UI images omit the Metal scene, which is checked separately.
- The first revised screenshot check failed because rendering delayed fixed-time reconnect callbacks. The check now schedules each action after the previous capture completes and allows fresh motion samples before resume. The subsequent check passed.
- Full-game motion here was **simulated**; these checks do not establish physical gameplay feel, camera accuracy, or haptic operation. Physical motor output, multiplayer, and an AI boss are not implemented.
- Run `--game-smoke-test` with other Aircade instances closed. Its report and `game-*-ui.png` / `game-*-scene.png` captures are written to the existing local log directory.
