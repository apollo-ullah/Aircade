# Aircade — Neon Rush

Native macOS arcade: **hold an AirPod, swing a saber, and survive a 60-second neon rush**. Includes the original slash/parry test lab and optional webcam hand position.
SwiftUI + SceneKit + Core Motion. No third-party dependencies. macOS 14+, Xcode / Swift 5.9+.

## Launch

```sh
./scripts/run.sh
```

This builds and ad-hoc signs `build/Aircade.app` with the required motion permission description.
Open that app bundle rather than running `swift run`: permission prompts need the bundled identity.
For editing in Xcode, open `Package.swift`; use the script to launch the correctly bundled app.

## Play Neon Rush

1. Click **Connect your controller** or **Controller**. Turn off **Automatic Ear Detection**, hold the earbud in your calibrated grip, and click **Start AirPods**.
2. The saved grip calibration loads for the active earbud. Use the animated three-pose guide if the grip has changed. Hold upright and press **R** to recenter, then close setup.
3. Select **Chill** (seven energy, generous windows, free-direction cuts) or **Arcade** (five energy, tighter windows, directional cuts from round two). Click **Let's play**.
4. After the countdown, wait for blocks to reach your blade. Slice green ✦ blocks in any direction; cut cyan arrows in the indicated direction. Avoid touching red × hazards with the blade. Keep clear of hazards until they disappear.
5. Every five consecutive cuts raises the score multiplier, up to ×4. Clean fast cuts score 150 base points; other valid cuts score 100. A miss, incorrect arrow cut, or hazard costs one energy and resets the combo.
6. Survive three 20-second rounds: **Ignite → Flow → Overdrive**. Results show score, rank for completed runs, cuts, best combo, and accuracy. High scores save locally for each difficulty. Replay or return to the launcher.

**Space** pauses/resumes. **R** recenters and pauses an active game; resume when ready. Tracking loss, opening setup, app interruption, and moving the app to the background pause the game without advancing targets. Resume includes a two-second countdown.

**Watch demo** uses visibly labelled simulated motion and never saves a high score. It is a motion demonstration, not an automated perfect player. To return to physical play, start AirPods again in Controller setup. The game works with AirPod rotation alone; camera tracking adds handle translation.

## Calibrate and use the test lab

1. Choose **Open test lab** from the launcher. Disable **Automatic Ear Detection** for your AirPods (the user confirmed this enables handheld streaming on their setup), and click **Start AirPods**.
2. Keep the earbud fixed in your intended grip. Choose **Calibrate grip — 3 poses**. A large animated guide opens with a wrist pivot, direction arrows, and a dashed target pose. Follow the motion, hold the target pose, then click the save button (or press Return). Replay restarts the illustration; it never captures automatically:
   - Hold the controller upright and capture neutral.
   - Tilt its top 30–60° to your left and capture left. Sliding your hand without rotating is not a calibration tilt.
   - Return to the original upright pose, then tilt its top 30–60° away from you and capture forward.
3. Return upright and press **R**. The resulting rotation basis is saved locally per source earbud. Repeat when the earbud's mounting within your grip changes.
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
- Motion available is false: macOS does not currently report a compatible available stream. Reconnect the AirPods; don't mistake simulation for hardware success.
- Stream stops when removed: test Automatic Ear Detection off and the other earbud's worn/case state. Record results rather than assuming a workaround works.
- Blade jumps/reversed axes: recenter in the intended grip and choose a grip-axis preset. Switching presets recenters.
- Rebuilding an ad-hoc-signed app may require granting permission again. A stable development signing identity can be added later.

## Verification

```sh
swift test
./scripts/build.sh
open -n build/Aircade.app --args --smoke-test
open -n build/Aircade.app --args --game-smoke-test
```

Run smoke checks separately with other Aircade instances closed. The lab check animates synthetic data, captures `scene-smoke.png` in the log directory, writes `smoke-result.txt`, and exits. The game check captures launcher, gameplay, pause, and results, exercises real geometric cuts with simulated motion, verifies demo scores are not saved, writes `game-smoke-result.txt`, and exits. Native UI bitmaps and SceneKit snapshots are captured separately. Neither check verifies real hardware.

Hardware verification remains pending until an actual labelled handheld trial succeeds. Build and unit tests cannot establish that the user's AirPods stream while held.

## Scope and next milestone

This build implements one complete local arcade game, controller setup, motion mapping, optional optical translation, geometric cuts, and a timing/angle-based parry drill. It does not implement a learned boss, multiplayer, or physical haptic output. Game judgments and lab events are logged for the next USB haptic integration.

## Why this approach

- [Nintendo on Wii MotionPlus](https://www.nintendo.com/en-gb/News/2008/Wii-MotionPlus-to-be-detailed-at-E3-250916.html): the gyro worked alongside the accelerometer and sensor bar, rather than providing absolute hand position by itself.
- [Nintendo on the sensor bar](https://en-americas-support.nintendo.com/app/answers/detail/a_id/2954/p/604/c/947): it contains infrared light sources. Aircade's ordinary webcam is a different optical reference, not a Wii IR implementation.
- [Apple hand-pose detection](https://developer.apple.com/videos/play/wwdc2020/10653/): Vision exposes wrist and finger landmarks.
- [Apple headphone motion](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager): processed orientation, angular velocity, and acceleration.
