# Aircade

Native macOS arcade: **hold an AirPod or iPhone and play motion-controlled games**. Includes Neon Rush, a 60-second Tennis rally challenge, two-player Saber Duel (AirPod + iPhone), and the original training lab.
SwiftUI + SceneKit + Core Motion. No third-party native dependencies; the optional badge station uses Node.js and MongoDB. macOS 14+, Xcode / Swift 5.9+.

## Connect once, switch games

Open **Controllers** from the Wii-style home menu. Choose the solo controller, then start and calibrate the active AirPod or pair the iPhone using the six-digit code. **Tennis** and **Neon Rush** both accept either device. **Saber Duel** uses both. Moving between home, games, and setup does not disconnect or recenter either controller.

After the initial connection/grip setup, use the AirPod to navigate the main menus: **lean left/right**, **tip toward the screen for up / away for down**, and **hold over a highlighted button for one second** until the ring fills. Move off a selected button before selecting it again. The same controls open channels, start games, replay, go back and change settings. They are disabled during active gameplay so swings cannot trigger menu actions. Fresh input and a small deliberate movement are required after entering a new menu or recovering tracking.

A normal launch reconnects AirPods automatically when a saved left/right grip exists. First-time pairing, OS permission prompts, calibration and text-entry sheets still use the mouse/keyboard. Menu pointing uses the chosen controller (**air → Settings**), with a ready alternate device as fallback if the selected one is unavailable. Deliberate mouse movement temporarily takes over. **Space** selects the pointed-to button at home and pauses/resumes a game; **R** recenters the appropriate controller. **Escape / Back to menu** leaves a channel.

Tennis is a 60-second arcade rally against an automatic returner. Actual racket-face contact, face direction, and swing speed affect returns. The current opponent is deterministic logic, not a trained AI service. Avatars, more than one phone, and external haptic motors are deferred.

## Audio output

Open **air → Settings → Sound → Audio output**. **Mac speakers** is the default and is remembered across launches. Menu music, menu cues and game effects route directly to the built-in speakers while the AirPods remain connected for motion. **System default** follows the Mac's selected output instead. Use **Test sound** to check the route; the Mac's speaker volume/mute still applies.

This setting only changes Aircade playback, not system-wide audio. Device changes refresh the route automatically. If built-in speakers are unavailable, speaker mode pauses audio instead of silently switching to AirPods. The existing menu music still plays on the home screen; routing does not add background music to other games.

## Badge profiles and local MongoDB

Run `./scripts/start-station.sh` in a separate Terminal, then launch the app. **Guest play works immediately without the server.** Optionally open **Leaderboard → Scan hacker badge** to create or retrieve a profile. Results are stored in local MongoDB; opted-in players appear at http://127.0.0.1:8787. Each game has its own board, personal bests, next-rival score targets, and post-round rank-climb feedback. Demo/scripted results are excluded. The station supports a local MongoDB installation or Docker Desktop. See [BADGE-STATION.md](BADGE-STATION.md) for setup, privacy, offline retries, tests, and LAN sharing.

## Launch

```sh
./scripts/run.sh
```

This builds and ad-hoc signs `build/Aircade.app` with the required motion permission description.
Open that app bundle rather than running `swift run`: permission prompts need the bundled identity.
For editing in Xcode, open `Package.swift`; use the script to launch the correctly bundled app.

## Saber Duel · two controllers

Choose **Saber Duel** in the Wii-style channel menu. Use one active AirPod and one iPhone; either can be Player 1. The other becomes Player 2. Pair in **Controllers** once and keep the connection across games. Install and pair it using [the iPhone setup guide](iOS/README.md). You must select your development team in Xcode before installing the companion on a physical phone; no signing identity is included.

The Mac hosts a six-digit-code lobby, two independently colored sabers, swept blade/target and blade/blade collision, five health points each, a 60-second limit, countdown, pause/reconnect, winner/draw, and rematch. The phone supplies distinct hit/clash/damage/result haptic cues. Hilt positions are fixed; tilt to aim and swing. Camera translation is not used in this duel. The existing AirPod calibration stays unchanged.

**Watch scripted duel** runs the actual physics through a full winning match without controllers; it is labelled simulated and does not verify physical hardware. For reproducible native UI/scene capture, close other Aircade instances and launch `open build/Aircade.app --args --duel-smoke`.

One AirPods pair supplies **one** public Core Motion stream at a time. Left/right sensor location is reported, not selectable by the app. A future turn-based bowling/golf mode could share the active earbud or wait for a verified system handover. This build does not implement two simultaneous earbuds from one pair, turn-based games, or more than two player slots.

## Play Neon Rush

1. Open **Neon Rush → Connect your controller**, or **Controllers** from home. Choose **AirPod** or **iPhone** under **Play with**. For AirPods: Turn off **Automatic Ear Detection**, hold the earbud in your calibrated grip, and click **Start AirPods**.
2. The controller label identifies the selected earbud. Its saved grip loads automatically. Use grip setup if the grip has changed. Hold upright and press **R** to recenter, then close setup.
3. Select **Chill** (seven energy, generous windows, free-direction cuts) or **Arcade** (five energy, tighter windows, directional cuts from round two). Click **Let's play**.
4. After the countdown, wait for blocks to reach your blade. Slice green ✦ blocks in any direction; cut cyan arrows in the indicated direction. Avoid touching red × hazards with the blade. Keep clear of hazards until they disappear.
5. Every five consecutive cuts raises the score multiplier, up to ×4. Clean fast cuts score 150 base points; other valid cuts score 100. A miss, incorrect arrow cut, or hazard costs one energy and resets the combo.
6. Survive three 20-second rounds: **Ignite → Flow → Overdrive**. Results show score, rank for completed runs, cuts, best combo, and accuracy. High scores save locally for each difficulty. Replay or return to the launcher.

**Space** pauses/resumes. **R** recenters and pauses an active game; resume when ready. Tracking loss, opening setup, and moving the app to the background pause the game without advancing targets. Resume includes a two-second countdown. A slow render/audio frame with fresh input recovers automatically with a bounded time step; it does not open the pause screen or skip through targets.

Brief AirPod packet gaps recover automatically: after 250 ms without motion, the game holds its clock and clears collision history while waiting for a new pose. Same-earbud gaps under one second keep the grip reference and resume without the pause overlay. The first returning pose cannot score a connecting slash. One second without input, an explicit disconnect, or a source change still requires a manual resume; sustained motion loss also requires recentering. Calibration and labelled hardware continuity trials keep their separate stricter continuity rules.

**Watch demo** uses visibly labelled simulated motion and never saves a high score. It is a motion demonstration, not an automated perfect player. To return to physical play, start AirPods again in Controller setup. The game works with AirPod rotation alone; camera tracking adds handle translation.

## Test without AirPods

Choose **air (Settings) → Scripted game tests**, select a scenario, then **Run scripted test**. The script supplies blade poses through the real collision, scoring, effects, and round code. It never injects scores or successful hits. **Change test** during play (or **Change scripted test** on results) opens the selector; **Use AirPods instead** reconnects real motion with your saved grip.

| Scenario | Expected behavior |
| --- | --- |
| Win the full game | Cut blocks, follow arrows, avoid hazards, finish all three rounds. |
| Stationary contact | Passing blocks do not shatter on a motionless blade. |
| Slow touch | Contact below cutting speed does not score. |
| Thrust along blade | A thrust does not count as a slash. |
| Wrong-way cuts | Reversed arrow cuts cost energy and break the combo. |
| Hit red hazards | Touching a red block costs energy once. |
| Miss every block | Five Arcade misses reach the defeat screen. |

Scripted sessions are labelled and do not save high scores or replace grip calibration. **One more run** replays the selected scenario. `open build/Aircade.app --args --scripted-demo` starts an interactive scripted win demo immediately.

## Calibrate and use the test lab

1. Choose **Practice** from the channel menu. Disable **Automatic Ear Detection** for your AirPods (the user confirmed this enables handheld streaming on their setup), and click **Start AirPods**.
2. Check the large **L / LEFT AIRPOD** or **R / RIGHT AIRPOD** badge in **SIMPLE CALIBRATION**. This names the earbud being calibrated, not the hand holding it or the tilt direction. Hold the earbud marked L/R in either hand. The same controller badge appears on the home screen, during play, in setup, and in the lab. The app currently uses the early three-capture flow:
   - Hold your imaginary handle upright and click **Save upright**.
   - Lean it left and click **Save left tilt**. A small tilt is accepted.
   - Return upright, then tip toward the screen and click **Save forward & finish**.
3. Each click captures the latest live pose immediately. There is no 30° target, steady-hold timer, explicit return gate, or preview stage. Wrist or forearm movement is fine; keep the AirPod fixed in your fingers. Only stale/mismatched sensor data, zero rotation, or indistinguishable tilt axes prevent a usable mapping. Return upright and press **R** after saving. Cancelling leaves the previous mapping saved.

The newer five-step flow is retained but disabled by `MotionModel.useSimpleCalibration = true`. The simple version uses the original three-pose structure from the earliest available commit (`de883fd`, 06:40) with its angle acceptance gates removed; there is no separate 05:45 commit. Launch `open build/Aircade.app --args --simple-calibration` to open the test lab and automatically show simple setup when live motion arrives.

macOS chooses which earbud supplies this Core Motion stream. Aircade pins the first known source and shows **selected** and **reported** earbuds separately if they differ. In setup, the lab, or the calibration sheet, **Use [earbud] instead** explicitly adopts the reported source and restarts calibration. This button does not command macOS to select a hardware sensor. Moving the other connected earbud cannot calibrate the selected one.

4. In **Slash lab**, sweep the blade through the block. Choose Any/Left/Right/Down cuts. Cuts split the block, create sparks and a short trail, play sound, and score. Blocks respawn after 0.85 seconds. Sound can be muted.
5. In **Parry drill**, press **Space** (or Launch attack). Place your blade along the green ghost. An orange attack arrives after 1.8 seconds; matching position and blade angle within ±180 ms of impact parries it. Wrong position/angle/timing counts as a miss. Tracking loss cancels the attack without penalizing you.

### Webcam movement

The initial prototype had a fixed handle: a sideways hand translation could not move it. The gyro describes rotation, not hand position. Camera input fills that gap without double-integrating acceleration.

- Enable **hand position**, select the Kiyo or another camera, and click **Start camera**. Grant camera permission. No microphone is requested.
- Camera frames are processed locally with Apple's Vision hand-pose detection. Frames are neither saved nor uploaded.
- Keep your controller hand visible in the preview; the cyan marker should follow the palm/wrist region. The tracker needs at least three confident wrist/knuckle landmarks. A tightly closed fist, occlusion, or blur can cause loss.
- Default **Mirror** maps the preview like a mirror; toggle if the physical horizontal direction is reversed for your setup. The same mirroring is applied to preview and control coordinates.
- If two hands are visible, choose which side of the preview to acquire. Once acquired, the nearest hand stays selected; this is proximity tracking, not persistent person/hand identity. Keep the other hand out of frame for the reliable demo.
- Centre your controller hand and press **R**. Move left/right and up/down to translate the saber handle. Adjust **Travel** as needed.
- This is a **2D screen-plane mapping**, not metric 3D hand position or depth tracking. AirPods still supply blade orientation. The game does not infer true absolute position from acceleration.
- Lost/stale hands suspend collisions. Reacquisition establishes a new hand centre and clears collision history, preventing jump hits. Press R again if you need to centre the blade.

## First real hardware test

1. Pair/connect AirPods to this Mac. Initially wear them to establish a baseline.
2. Click **Start AirPods**, and accept the macOS Motion & Fitness prompt.
3. Confirm the **source**, nonzero **update rate**, and changing yaw/pitch/roll.
4. Take one earbud out and hold it securely. Try disabling Automatic Ear Detection in the AirPods settings if samples stop. This is an experiment, not a guarantee of out-of-ear streaming.
5. Move the left and right earbuds separately. The **source** tells you which currently supplies motion. This app does not select a source or assume that a pair exposes two independent streams.
6. Hold your grip upright to match the saber. Click **Recenter** or press **R**. Try the other **Grip axes** presets if movements map to the wrong axes. Recenter after changing grip or source.
7. In the test lab, open **Diagnostics** and select the matching **test condition**, then **Begin test**. Keep holding the earbud and slowly rotate through several angles for at least two minutes.
8. A pass requires 120 seconds of fresh samples from one source with no gap over 500 ms and at least 30° of orientation change during that interval. Gaps/source changes reset the interval. The physical condition is user-reported: software cannot prove that an earbud is in a hand rather than an ear.
9. Repeat for the other earbud, both worn, one worn/one held, and the other earbud in its case. Note which combinations work. Check whether Auto Ear Detection changes the result.

## Saber controls

- Orientation uses reference-relative quaternions, not Euler-angle subtraction.
- **Smoothing** is a time constant, not a measured end-to-end latency. Zero disables it.
- **Swing trigger** is angular speed in radians/second, with hysteresis and a cooldown.
- A swing threshold only controls the blade flash. Scoring requires a swept geometric blade/block intersection and minimum contact speed. Strokes aligned along the blade are glancing contacts; optional directional targets check screen-space travel direction.
- The handle stays at a fixed pivot when the camera is off. With the camera on, Vision supplies screen-plane position. Acceleration is shown/logged, never integrated into position.
- Source changes and sample interruptions dim the blade and require explicit recentering. Learned mappings are stored separately for Left/Right; only one motion source is streamed.
- **Run simulated motion** tests the scene without AirPods. It cannot pass a hardware test.

## Logs and evidence

**Open logs in Finder** opens `~/Library/Application Support/Aircade/Logs/`.

- Every tracking session produces a CSV of timestamp, source, condition label, quaternion, Euler angles, rotation rate (rad/s), user acceleration (g), and events.
- Completed/cancelled/interrupted tests produce JSON reports with continuity and rotation evidence.
- `latest-status.json` exposes current diagnostics for debugging. No network upload.
- The last-sample age measures time since this app received fresh data; it is not Bluetooth or motion-to-photon latency.
- Samples with duplicate/backward sensor timestamps from the same source are ignored.

## Troubleshooting

- No data: verify Mac Bluetooth connection, try wearing the earbuds first, then restart tracking. Check Motion & Fitness permission in System Settings → Privacy & Security.
- Controller setup shows permission, sample count, and update rate. **Reconnect AirPods** creates a fresh motion connection. If Bluetooth is connected but samples stay at zero, disconnect/reconnect the AirPods in Mac Bluetooth settings, briefly wear them, then retry. The app distinguishes a motion-ready controller from Bluetooth availability.
- Motion available is false: macOS does not currently report a compatible available stream. Reconnect the AirPods; don't mistake simulation for hardware success.
- Stream stops when removed: test Automatic Ear Detection off and the other earbud's worn/case state. Record results rather than assuming a workaround works.
- Blade jumps/reversed axes: recenter in the intended grip and choose a grip-axis preset. Switching presets recenters.
- Rebuilding an ad-hoc-signed app may require granting permission again. A stable development signing identity can be added later.

Motion callbacks run on a dedicated serial queue. A bounded buffer passes the newest reading to the main run loop; readings from stopped sessions are discarded. This prevents the UI queue from holding a backlog of controller input. `latest-status.json` includes motion-service activity, cached sample availability, and errors for connection troubleshooting.

## Verification

```sh
swift test
./scripts/build.sh
open -n build/Aircade.app --args --smoke-test
open -n build/Aircade.app --args --game-smoke-test
open -n build/Aircade.app --args --scripted-game-test
open -n build/Aircade.app --args --scripted-repro
```

Run smoke checks separately with other Aircade instances closed. The lab check animates synthetic data, captures `scene-smoke.png` in the log directory, writes `smoke-result.txt`, and exits. The game check captures launcher, gameplay, pause, and results, exercises real geometric cuts with simulated motion, verifies demo scores are not saved, writes `game-smoke-result.txt`, and exits. Native UI bitmaps and SceneKit snapshots are captured separately. Neither check verifies real hardware.

The two scripted checks keep sound and visual effects enabled, verify full victory or defeat respectively, write `scripted-win-result.json` / `scripted-repro-result.json`, capture results, and exit. These unattended checks bypass background-focus pausing only for those two command-line flags. Normal interactive play still pauses when the app loses focus. `swift test` also exercises light contacts, wrong-direction cuts, hazards, replay, slow-frame recovery, and genuine tracking loss through the production game wrapper.

Hardware verification remains pending until an actual labelled handheld trial succeeds. Build and unit tests cannot establish that the user's AirPods stream while held.

## Scope and next milestone

This build implements one complete local arcade game, controller setup, motion mapping, optional optical translation, geometric cuts, and a timing/angle-based parry drill. It does not implement a learned boss, multiplayer, or physical haptic output. Game judgments and lab events are logged for the next USB haptic integration.

## Why this approach

- [Nintendo on Wii MotionPlus](https://www.nintendo.com/en-gb/News/2008/Wii-MotionPlus-to-be-detailed-at-E3-250916.html): the gyro worked alongside the accelerometer and sensor bar, rather than providing absolute hand position by itself.
- [Nintendo on the sensor bar](https://en-americas-support.nintendo.com/app/answers/detail/a_id/2954/p/604/c/947): it contains infrared light sources. Aircade's ordinary webcam is a different optical reference, not a Wii IR implementation.
- [Apple hand-pose detection](https://developer.apple.com/videos/play/wwdc2020/10653/): Vision exposes wrist and finger landmarks.
- [Apple headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager): processed orientation, angular velocity, and acceleration.
