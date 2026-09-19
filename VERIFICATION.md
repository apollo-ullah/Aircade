# Verification — 2026-09-19

## Saber Duel and iPhone controller — latest

Implemented a two-player duel using one existing Mac AirPod stream and one independent iPhone motion stream. Added a native iOS companion project, local Bonjour/TCP pairing, fixed-position dual sabers, swept target strikes and crossed-blade parries, five health each, countdown, 60-second results, reconnect/pause, rematch, and iPhone haptic cues. Existing simple AirPod calibration is unchanged.

- **All 71 automated checks passed in the final full suite:** 48 MotionCore, two transport, and 21 app integration tests. New coverage includes independent controller identity, old/duplicate/wrong-session packets, stale sender age, phone portrait axes, stationary/slow contact, parries, full five-hit wins at 30/60 Hz, timeout draw, reconnect without phantom damage, and replay reset.
- A real TCP loopback test exercises the shared framing protocol. An app integration test pairs a synthetic phone with the production Mac host, rejects wrong-session samples, verifies separate player orientations, and proves that stale phone input does not invalidate fresh player 1 input. These are synthetic controllers, not physical devices.
- The native `--duel-smoke` run passed: **Blue won 5–0 after 6.37 seconds of match time** through ordinary pose-driven collision. Inspected lobby/results UI images and the independent SceneKit court capture. Cached native UI bitmaps omit Metal content, which was checked separately. Outputs: `build/duel-smoke/` (ignored by git).
- Mac release build and signature verification passed. The iPhone project compiled and linked successfully for the physical-device iOS SDK with signing disabled.
- **Physical AirPod + iPhone multiplayer is not yet verified.** The connected iPhone 15 Pro Max now has Developer Mode enabled. A Personal Team signing identity and device provisioning profile were created through Xcode, the signed build succeeded, and `devicectl` installed `com.adyan.aircade.controller`. Local signature checks passed and the profile includes this device. First launch was refused by iOS with a profile-trust error. After the user confirmed the developer profile on the phone, `devicectl` successfully launched the installed app. Phone UI inspection, motion feel, haptics, Wi-Fi pairing, and a real two-controller match remain physical checks; see `iOS/README.md`.
- Current scope is two simultaneous controllers. A pair exposes one AirPod motion stream; `sensorLocation` is reporting-only. Turn-based games could share the active earbud, or adopt the other earbud after a verified system handover. Forced left/right selection, bowling/golf, and eight players are not implemented.

Apple references: [headphone motion API](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [one-earbud-at-a-time explanation](https://developer.apple.com/videos/play/wwdc2023/10179/), [local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

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

## Connection recovery — September 19, morning

Bluetooth and Motion & Fitness permission were available, but the old app received zero motion samples even after a normal restart with the earbuds worn. Moved Core Motion callbacks off the main operation queue, added a thread-safe latest-reading buffer consumed on the main run loop, and made each reconnect create a fresh manager. Session tokens reject late callbacks from a previous connection. Setup now shows permission, sample count, update rate, a Reconnect button, and recovery instructions after five seconds without data.

- All **25 unit tests passed**, including new buffer coalescing and stopped-session isolation tests; release build succeeded.
- Reopened the updated app and observed **491 real Right AirPod samples**, approximately **33.5 Hz** consumed at the time of inspection, fresh sample age **33 ms**, active motion service, calibration reference set, and no motion error. This confirms recovery of the real input path in this session; it does not isolate whether queue delivery, recreating the connection, or the physical reconnection was the sole cause.
- Calibration mappings remain per earbud. A Right source does not reuse a saved Left grip mapping.

## Calibration feedback and active-earbud mismatch

The user reported an unresponsive final capture while holding the Right AirPod; live logs showed the motion source was Left. The guide now identifies the active earbud, displays measured tilt and capture readiness, explains insufficient/excessive tilt and repeated-axis rejection prominently, and counts rejected attempts. Missing/stale poses no longer return silently. Added Start over and Use saved grip controls, source consistency checks, and calibration diagnostics/events. Save controls remain visible while instructional content can scroll.

All **27 tests passed**, including explicit reasons for too-small/too-large/nonfinite tilts and for repeating the left axis in either direction. Valid independent tilts still produce a mapping. Release build succeeded. Inspected the rendered native final-step preview with the active-earbud banner, invalid-pose feedback, and visible finish/restart buttons; preview values are synthetic. Physical pose completion still depends on moving the active sensor and holding a consistent grip.

## Calibration audit and transactional setup — September 19

Reviewed the Core Motion API and SDK headers: `CMDeviceMotion.sensorLocation` identifies the source of each sample. `CMHeadphoneMotionManager` has no public setter to choose the left or right sensor. Aircade now pins the first known source, displays selected and reported sources separately, and requires an explicit handover when macOS changes the source. It does not claim to force macOS to stream a particular earbud.

Evidence from the pre-fix session: `airpods-2026-09-19T13-24-55Z-F29891.csv` records a Right neutral capture followed by a Right-to-Left switch. The old source-load path also assigned `grip`, whose observer could recenter against the previous source's raw sample. Removed that side effect. Comparing adjacent raw quaternion changes with integrated gyro speed in the recent same-source CSV segments gave median ratios around 0.996–0.999; this supports checking source identity and reference capture rather than applying an arbitrary angle multiplier. There was no independent measurement of the user's physical forearm/earbud angle, so this does not establish physical angle accuracy or fully isolate the reported 30° versus 6° discrepancy.

The replacement flow captures an averaged neutral pose, a steady left tilt, an explicit return within 10° of the same neutral, a steady forward tilt, and a live two-view blade preview. Each capture needs at least six distinct samples spanning 0.30 seconds in a 0.40-second window, maximum 3° spread from the hemisphere-aligned quaternion mean, and angular speed ≤0.45 rad/s. Existing tilt amplitude/axis-separation acceptance limits remain unchanged. New poses never overwrite the saved grip until the user confirms the preview while upright. Cancel preserves the old mapping; using a saved mapping selects it without treating a tilted pose as upright. Source changes, gaps, and disconnects invalidate the trial and explain how to restart without silently closing the guide.

Callbacks carry their receipt time through the input buffer; a queued sample older than 0.25 seconds cannot become fresh just because the main thread consumed it. Repeated sensor timestamps cannot fill a steady-pose window. Forearm, wrist, or elbow movement is explicitly allowed when it changes the earbud's orientation. Example animations are labelled separately from live sensor readings; the angle label now describes orientation change from the saved start.

- **45 checks passed:** 38 MotionCore tests and seven app-model integration tests. New cases include arbitrary neutral/mount 30° rotations, quaternion sign and Euler wrap, moving/drifting poses, repeated/stale samples, explicit neutral return, complete mapping/preview/commit, cancellation preserving storage, source handover without accidental recentering, saved-grip selection, and source switches interrupting hardware trials. App-model tests use synthetic input, isolated preferences/log directories, and no physical Core Motion connection.
- Release bundle rebuilt; ad-hoc code signature and `git diff --check` passed. The updated bundled training smoke passed with 158 simulated samples and three geometric cuts; this does not verify physical tracking.
- Native guide previews were rendered for all five stages plus source mismatch. Inspected the source label, source-adoption button, live preview, explanatory copy, and always-visible footer actions. Preview data is synthetic, not physical tracking evidence.
- The old running app's modal setup sheet refused a normal quit (`User canceled`, -128). Requested that the user close the old setup windows before restarting; no forced termination was used. Updated physical calibration still needs a user trial in the new build.

References: [headphone motion manager](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager), [sample sensor location](https://developer.apple.com/documentation/coremotion/cmdevicemotion/sensorlocation-swift.property), [attitude representations](https://developer.apple.com/documentation/coremotion/cmattitude).

## Simple calibration fallback — September 19

At the user's request, bypassed the newer calibration with `MotionModel.useSimpleCalibration = true`; its implementation remains available for comparison. Restored the earliest recorded three-snapshot structure (commit `de883fd`, 06:40; no distinct 05:45 revision exists), removing angle-quality gates as well as the newer steady-window, neutral-return, and preview requirements. The current pose saves on each click. Only nonfinite/zero motion and collinear directions are rejected by the mapping math. Source identity and actual packet freshness still apply. The screen is visibly labelled **SIMPLE CALIBRATION**.

- **47 tests passed**, including app-model tests that complete all three captures immediately with a 4° left and 6° forward tilt, and prevent a mapping from mixing earbuds. The disabled newer flow's regression suite remains covered separately.
- Release build, signature verification, and diff checks passed. Native simple calibration preview rendered and inspected.
- Normal quit still failed because of the obsolete app's modal sheet. Closed that specific old Aircade process with SIGTERM as part of the requested restart, then launched the rebuilt bundle with `--simple-calibration`. No saved grips were cleared.
- Verified the replacement process and `calibrationMode: simple-three-pose-v1` in its live status. Observed 169 real Left samples at approximately 32.7 Hz with an 11 ms receipt age. The user had already captured upright and left successfully and reached step 3. This confirms the old left-capture blocker was passed in the running replacement; it does not independently measure the user's physical angle or gameplay accuracy.
- Subsequent live status confirmed **completion**: `calibrationStep: 0`, no calibration error, and `Simple grip saved for Left. Return upright and press R.` after 1,237 real samples. Physical gameplay feel remains for the user to assess.

## Controller identity clarity — September 19

After the user confirmed the simple calibration works well, added a shared controller badge with a large L/R marker and full LEFT AIRPOD / RIGHT AIRPOD name on the home screen, game footer, setup, and test lab. Calibration pins a matching identity card above its instructions, says to hold the earbud marked L/R in either hand, and names that earbud in capture/finish buttons. Step labels now say Lean left / Lean forward to separate motion direction from earbud identity. Source mismatch and the explicit source-switch action stay visible above the scrolling instructions. Calibration success and intermediate messages name the earbud as well.

This change affects presentation and wording; the working three-snapshot algorithm and its acceptance rules were not modified. Release build, code signature verification, and diff checks passed. Native previews covered left, right (including a right-earbud left-tilt step), and source mismatch; inspected the right and mismatch captures for readability and clipping. Reopened the updated app after a normal quit. At the post-launch check it was waiting for motion, so the UI correctly showed no active earbud rather than displaying a guessed source. Saved grip data was not cleared.

## Scripted gameplay and pause-on-contact fix — September 19

The user clarified that touching blocks paused/froze the game. The real-session CSV `airpods-2026-09-19T14-26-11Z-68AEFC.csv` recorded misses followed immediately by the generic interruption pause. Reproduced independently with a pose-only scripted controller and sound enabled: the first miss spent **505.7 ms** inside feedback, producing a **518.9 ms** frame and triggering the old 300 ms pause rule. The baseline is preserved as `scripted-repro-before-fix.json` in the log directory.

Moved sound lookup/device startup onto a serial audio queue with cached sounds and stale-cue suppression, including the training lab. Fresh input is consumed before the game tick checks tracking. Slow frames now clear collision history and advance at most 100 ms instead of opening a generic pause overlay; actual stale input, explicit pauses, setup, and focus loss still pause. The working simple calibration is unchanged.

- **53 tests passed:** 38 MotionCore and 15 app integration tests. Six new app tests drive actual `ArcadeGame.update` geometric sweeps: stationary/slow/thrust contacts, correct/incorrect arrow cuts, hazards, single scoring, exact multipliers, complete victory on both difficulties with two seeds/frame rates, defeat, replay with reused target IDs, slow-frame recovery, stale-input pause, and explicit pause.
- Rendered native full-win check, sound/effects enabled: **60 seconds, 43 perfect cuts, 21,300 points, five lives, zero mistakes, no slow frames**, and unchanged high score. Maximum feedback time **1.56 ms**, maximum frame **41.4 ms**. Report: `scripted-win-result.json`.
- Rendered native reproduction after the fix: **five misses, zero lives, proper defeat results**, no pause, unchanged high score. Maximum feedback time **0.45 ms**, maximum frame **51.7 ms**. Report: `scripted-repro-result.json`.
- Seven scenarios are selectable from **Scripted saber tests** on the launcher. Inputs and results are labelled scripted; scores do not persist. Scripts generate poses only and cannot call the game's judgment API. Unattended command-line checks bypass focus pausing explicitly; interactive use retains normal focus behavior.
- Release build, code signature, and diff checks passed. Inspected native victory/defeat screens and the seven-scenario selector for readable labels and visible actions. The automated full-win test and separate defeat check ran with real native rendering and sound enabled; physical audio output was not independently measured.
- These checks validate software physics, feedback, and win/lose logic independently of hardware. They do not measure physical AirPod tracking, tactile output, or hand-to-blade accuracy.

## Post-hit AirPod packet gap — September 19

The user's next screenshot showed **Controller tracking paused**, a separate trigger from the previous render/audio-frame pause. The real Right-AirPod log `airpods-2026-09-19T14-52-55Z-6B741B.csv` recorded a cut at uptime 287312.076, last motion at 287312.392, a pause at 287312.659, and fresh motion at 287312.672. The **280.1 ms** receipt gap exceeded the old **250 ms** instant-pause threshold; the stream returned **13.3 ms** after the pause. Feedback remained around 1 ms and no slow render frame occurred. Continuously generated scripted poses did not exercise this missing-packet path.

Separated collision freshness from confirmed tracking loss. At 250 ms the game holds time and clears collision history; fresh same-source input resumes automatically, without a countdown or modal pause. The first returning pose establishes a new baseline and smoothing does not interpolate through unobserved motion. Under-one-second gameplay gaps preserve the neutral/grip reference. A full second without input, an explicit disconnect, recenter action, or earbud switch retains the explicit pause path. Existing calibration capture and 500 ms hardware-trial continuity requirements remain separate. Added wait/recovery events, gap counts, and pause reason to diagnostics.

- **58 tests passed** (38 MotionCore + 20 app integration). The new model integration tests feed real-shaped quaternion packets through `MotionModel.receive`, orientation mapping, and production geometric collisions. They first produce a hit, then inject the recorded **0.280104375 s** gap and repeated **0.65 s / 0.32 s** gaps. They verify automatic recovery, honest stale/fresh status, preserved calibration, frozen game time, unchanged score/health, and continued play.
- Additional checks prove no connecting slash across missing samples, countdown recovery, explicit pauses staying paused, a 1.05 s loss requiring recentering, and an earbud change during recovery requiring manual intervention. Existing full-win/defeat/replay tests still pass.
- Release build, ad-hoc signature verification, and diff checks passed. Closed the previous app normally and reopened with `--live-test`. The rebuilt process received **152 real Right-AirPod samples**, a **25 ms** sample age, and a calibrated ready state; it was on the menu awaiting a physical gameplay trial. Saved grip data was retained.
- Subsequent **live gameplay** in `airpods-2026-09-19T15-00-21Z-5781A5.csv` verified the repaired path: target 1 scored, `RUSH_INPUT_WAIT age=0.2531` was followed by `RUSH_INPUT_RECOVERED gap=0.3199`, and targets 2, 4, 5, 6, 7, and 10 subsequently scored. There was no `RUSH_PAUSE` in this observed sequence. This is real Right-AirPod input with sound enabled, not a scripted run.
- These are deterministic regressions of the real input-processing path. They establish handling of the observed timing; they do not independently establish why Bluetooth/Core Motion briefly stopped producing packets or guarantee the next physical trial's outcome.


## Integrated arcade release candidate — September 19

Source: `codex/arcade-integration` in `../Aircade-integration`. See `docs/INTEGRATION-EXECUTION.md` for agent ownership and commits. The original working checkout and fallback app were preserved. The UI handoff was merged at `5e6027a`; only implemented channels are public.

**162 automated tests pass**: 79 MotionCore, 3 ControllerLink, 80 app-model tests. This includes the original simple calibration suite, phone-only production gameplay, real loopback TCP pairing/role updates, session continuity across games, collision timestamp regression, finite racket-face/ball sweeps, complete 30/60 Hz Tennis rounds, guest/local/profile result eligibility, permanent simulation disqualification, and stale-input recovery. Haptic events follow the selected device after reassignment or reconnection without reattributing the score; obsolete feedback UUIDs cannot affect the resumed session. Log: `/tmp/aircade-final-tests.log`.

Native rendered checks (all synthetic inputs; no physical performance claim):

| Check | Outcome | Evidence under `build/` |
| --- | --- | --- |
| Wii shell | 13 route transitions pass, pairing code persists, only current game enabled, script setup and exit work | `release-shell/shell-smoke-result.json` and screenshots |
| Tennis | 60 seconds, 24 returns, 0 misses, 10,040 points, results; zero queued scores | `release-tennis/tennis-smoke-result.json` |
| Neon Rush win | 60 seconds, 43 perfect cuts, 21,300 points, 5 lives; high score unchanged | `release-win/scripted-win-result.json` |
| Neon Rush defeat | Five misses, zero lives, correct defeat; no pause modal; high score unchanged | `release-defeat/scripted-repro-result.json` |
| Saber Duel | Blue wins, health [5, 0], results | `release-duel/duel-smoke-result.txt` |
| Final-build stop/reconnect/resume | Tracking loss held game time; after resume, 13 cuts, 2,200 points, results; high score unchanged | `release-recovery/game-smoke-result.txt` |

Sound/effects were enabled for the Neon Rush win/defeat checks. The win's maximum feedback callback was 0.59 ms and maximum frame was 98.1 ms, with no frame over the game's slow-frame threshold. These figures measure this scripted software run, not Bluetooth delay or motion-to-photon latency. Native UI snapshots were inspected for home, controller setup, Tennis, Duel, profile, settings and results; SceneKit scene snapshots separately cover the Metal-rendered content omitted by bitmap view capture. A light-theme contrast issue in the earbud identity card was corrected.

The Mac release and signed generic iPhone device builds succeed; both signatures verify. The current iPhone companion must be installed to support role/feedback protocol changes. `devicectl` reports the previously trusted phone unavailable, so no updated installation or physical multi-game play-through is claimed. The old hardware success reported by the user remains evidence only for the previous build. Reconnect/unlock the iPhone to install `build/iOS/Build/Products/Debug-iphoneos/AircadeController.app`, then follow the acceptance sequence in the execution record.

Guest play does not contact the badge service. MongoDB-backed integration was not exercised against a running database; isolated profile policy/transport tests do pass. The opponent remains deterministic, not trained/model-backed. Avatars, additional phones, external haptic motors, and physical grip/lag tuning remain deferred. The full plan's physical release gate is still open.
