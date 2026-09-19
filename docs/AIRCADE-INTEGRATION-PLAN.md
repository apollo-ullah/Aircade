# Aircade: one connected arcade

Implementation and orchestration plan · September 19, 2026

**Status: planned, not implemented.** This document records the next execution plan. The current AirPod/iPhone build, teammate tennis branch, and Wii-shell work remain separate. No integration is claimed by this document.

## 1. Outcome and scope

A player opens the Wii-style channel menu, connects an AirPod or iPhone once, calibrates that device, plays Tennis, switches to Neon Rush, and starts an AirPod-versus-iPhone Saber Duel without pairing again. Games remain playable as a guest without MongoDB or an AI service. Connection status, controller identity, pause/recovery, results, and feedback behave consistently across games.

The milestone is complete when this full path works on the actual Mac, AirPods, and iPhone, plus deterministic software tests. A passing scripted demo alone is insufficient.

**Required for this milestone**

- AirPod or iPhone as the solo controller for Tennis and Neon Rush.
- One AirPod stream plus one iPhone as two independent duel controllers; either device can occupy either player slot.
- Persistent connections across game, home, controller setup, and results routes.
- Existing simple AirPod calibration preserved; separate phone calibration and clear active-device labels.
- Immediate guest play; optional badge profiles and honest score persistence.
- Racket-face contact, with visible differences from face angle and swing speed.
- Nonblocking game feedback, including existing iPhone haptics.
- Wii-shell integration, deterministic regression checks, and a repeatable physical demo.

**After the reliable core**

- Teammate's adaptive opponent, integrated behind a bounded asynchronous interface.
- Avatar-to-local-player display, once the UI agent's avatar work is ready.
- More original sounds, animations, and controller grip polish.

**Deferred**

Eight-player support, two simultaneous independent streams from one AirPods pair, forced earbud selection, new sports, internet multiplayer, external haptic motor drivers, a new camera/6DoF pipeline, raw gyro protocol redesign, and realistic tennis sets/spin. The current tennis mode remains an arcade rally challenge; an adaptive returner does not by itself make it a competitive tennis match.

## 2. Verified starting point

| Work | Location / revision | What it contains | Caveat |
|---|---|---|---|
| Current working app | `main` at `2be0b85`, plus uncommitted files | AirPod tracking, Neon Rush, independent iPhone controller, Saber Duel | Preserve all intended tracked and untracked work before combining branches |
| Teammate push | `origin/main`: `43eb64f`, `5461d7f` | Badge profiles, MongoDB leaderboard, Tennis | Reviewed separately in `/tmp/aircade-review.1H2jMi`; not merged |
| UI task | `wii-shell` at `e2312fb`, worktree `../Aircade-wii-shell` | Approved design document for channel shell, pointer, avatars, theme | Latest observed commit contains the design, not its implementation; recheck at handoff |

Evidence: 62 native tests passed on the isolated teammate revision. The prior local multiplayer verification recorded 71 tests, and the user subsequently confirmed physical AirPod + iPhone play. These are separate baselines with overlapping tests, not an integrated total. Backend JavaScript syntax checks passed, but the MongoDB integration tests were not run in the review. MongoDB and the station API were not listening locally at review time.

Current coupling to remove:

- `MultiplayerModel` owns the phone listener, pairing code, transport, input registry, match, and scene. `close()` destroys the phone connection.
- `MotionModel.showMultiplayer` and `showLab` call that close path. Navigation therefore disconnects hardware.
- `PhoneController` rejects `welcome(player:)` unless the player is 2; its view says Player 2 / ready to duel.
- Tennis only consumes the Mac AirPod pose path.
- `PlayerSession.authorize()` requires a badge profile; starting a fresh session depends on the server.
- Tennis callbacks pass `demo: false`, and its local best-score update has no simulation gate.
- Tennis collision currently sweeps a shortened saber segment. The automatic opponent repeats a lane pattern and always returns a valid shot.

## 3. What waits for the UI agent

**Do not wait to build controller/session logic, guest/run policy, pure racket geometry, and their tests. Wait for a UI handoff before merging or rewriting the shared screens.** All implementation agents work from an agreed integration baseline in separate worktrees.

The UI worktree's design is useful, but predates the tennis push and some multiplayer details. Its design document is reference material, not an instruction to overwrite newer behavior. The coordinator must reconcile these points before final composition:

1. Add a Tennis route and tile. Suggested six public tiles: Tennis, Neon Rush, Saber Duel, Avatars, Controllers, Leaderboard. Put Training Lab and Scripted Tests under an easily accessible developer/settings entry. Final visual arrangement stays with the UI owner.
2. A root session outlives individual routes. Closing a channel ends/leaves its game, not its controller connection.
3. Pointer input comes from the selected menu controller, not directly from `MotionModel.saber`. Both AirPod and iPhone work; mouse/keyboard always remain available.
4. Keep UI selection and gameplay input contexts separate. A gameplay swing cannot activate a menu tile or global control. Reacquiring tracking cannot produce an automatic selection.
5. Reconcile freshness rules: the shell spec's claim that 0.5 seconds is the app-wide threshold is outdated. Gameplay rejects input at 250 ms and distinguishes transient gaps from one-second loss. Pointer timeout is a separate presentation policy; it cannot mark a gameplay controller fresh.
6. Clarify Space/R behavior by route. Space selects a menu item in menu context and pauses/resumes in game context. Recenter targets the selected controller and never resets the other player's calibration.
7. Preserve CLI smoke routes, setup flows, readable Left/Right AirPod identity, and the currently working simple three-pose capture behavior.
8. UI audio must retain the existing off-main-thread/prewarmed behavior. New sounds must not reintroduce the observed pause-on-contact bug.
9. Avatars are local presentation identity. A chosen avatar does not silently create a badge profile or grant leaderboard eligibility.

**UI handoff contents:** exact commit, changed-file list, route API, theme entry points, pointer input API, preview/smoke results, known unfinished screens. No need to wait for the complete avatar part catalog to hand over the working shell. If the shell is still unfinished, keep functional adapters behind the existing views and defer only final presentation.

## 4. Architecture and contracts to freeze first

Names below are proposed implementation names, not existing APIs. Prefer small concrete components; do not introduce a generic game engine or rewrite every game around a new protocol.

```text
App root / ArcadeSession
  ├─ ControllerSession (connection lifetime, devices, assignment, latest input)
  │    ├─ existing MotionModel / AirPod adapter
  │    └─ extracted PhoneControllerHost → ControllerLink → iPhone app
  ├─ run/profile policy → existing PlayerSession → optional station backend
  ├─ selected game → Neon Rush / Tennis / Saber Duel adapters
  └─ UI shell → routes, controller status, menu pointer

Game events → FeedbackRouter → existing audio / phone haptics
                             → future external haptics adapter
```

### Device ownership and lifecycle

- `ControllerSession` is owned by the app root and survives view creation/destruction. It exposes connection state and emits latest input; it does not own score, match physics, or scene nodes.
- Separate connected-device identity from player assignment. A paired phone can remain connected while unassigned; solo controller selection does not require a new handshake. Use the existing two-slot assignment machinery where possible.
- `controllerID` identifies a device; `sessionID` identifies a connection epoch; `sequence` identifies a sample. Earbud Left/Right is the active sensor within the AirPod controller, not a second independent player ID.
- Expose explicit pair, unpair, assign, select-menu-controller, recenter, and app-shutdown actions. Game leave/reset never calls host shutdown. Explicit unpair rotates the code; changing a route does not.
- A reconnect is a new transport session. Reject packets and asynchronous callbacks from the previous session. Do not silently replace another assigned controller.
- Supported scope remains one connected phone plus the Mac's AirPod stream. Structure assignment cleanly without building speculative multi-phone support now.
- A device change during a run requires pausing/restarting input history; assignment should normally happen in home/setup or while paused. Expose the currently assigned device on the phone and Mac.

### Input, calibration, and timing

- Preserve `PlayerControllerFrame` version 1 if possible. Orientation, readiness, source, sample age, simulation flag, and identity already suffice. Add only the minimum compatible role/status messaging needed; update host and phone together if the wire protocol changes.
- The host updates the iPhone to accept slot 1 or 2. Pairing and readiness are separate. The UI must also distinguish connected-but-unassigned state; select and document a compatible representation rather than faking a player assignment.
- Keep newest-only polling, bounded packets, one outstanding poll, real sample age, RTT accounting, sequence/session validation, and late-response rejection. Receiving an old orientation must not reset its age to zero.
- Use host monotonic receipt time and sender-relative sample age; never subtract unsynchronized device uptimes. Keep a sample's effective capture time stable across render ticks so replaying it cannot create a fresh collision segment.
- Apply the existing AirPod grip transform once and the phone portrait/reference transform once. Do not apply a second generic calibration or smoothing pass in the shared layer.
- Keep AirPod saved grip mappings per source. A source switch invalidates the applicable reference, clears collision history, and requires the existing explicit handover. The UI must never promise it can force a chosen earbud to stream.
- Build game poses using explicit game-specific hilt placement. Solo phone input uses the same arena coordinate convention as solo AirPod input; duel maintains its two hilt anchors. Orientation-only input must not invent tracked hand translation. Preserve the current AirPod camera path where enabled, without extending it to phone tracking in this milestone.
- Freshness is evaluated per device. At 250 ms, stop contact evaluation, clear sweep history, and hold match time. Same-source recovery before confirmed one-second loss automatically establishes a new baseline. Sustained loss, explicit disconnect, source change, and recenter retain explicit pause handling.
- In solo mode, an unused controller going stale must not interrupt the game. In duel, both assigned inputs must be valid. Never hide stale input by re-dating its pose.
- Consume input before the active game evaluates it. One owner polls transport; inactive game timers are disabled. Do not combine a wholesale timer rewrite with this extraction unless necessary to eliminate double consumption.

### Feedback and run identity

- Define a small typed feedback event: originating run, player/controller recipient, cue, intensity if supported. Initial cues map to the existing hit/block/damage/victory/defeat/draw phone strings; richer cues can follow after compatibility checks.
- Route feedback only to the assigned controller for that event. Leaving a game invalidates pending effects from that run. UI audio/transport must not block collision or rendering.
- Capture a `RunContext` at start: unique run ID, game/mode, guest or badge profile snapshot, input provenance, and optional local avatar reference. Switching profiles afterward cannot reattribute a finished run.
- Model profile identity and simulation as separate concepts. Guest runs display results and may update a clearly local best; they do not queue public scores. Badge runs can queue while offline. Scripted/simulated runs update neither real bests nor public scores. If a real run later accepts simulated input, downgrade its eligibility for the entire run.
- Cancelling or abandoning a run produces no completed score submission. Repeated result callbacks cannot enqueue twice. Selecting a guest clears any prior account eligibility for the new run.
- Keep guest play local and immediate. Offer badge sign-in as an optional profile action; do not make an eight-second HTTP failure the path to guest play. Never retroactively upload a guest score merely because someone signs in afterward.

### Tennis contact and opponent boundary

- Add pure `RacketGeometry` and shared racket dimensions used by both the scene and collision code. Detect the swept racket face against the moving ball, not an elongated handle/saber against the ball's endpoint only.
- Return contact point, face normal, local face position, and relative contact velocity. Bound rotation subdivision/work so fast swings cannot make collision arbitrarily expensive.
- Exclude shaft-only and outside-face contacts. Keep a deliberate swing-speed gate for a powered arcade return; stationary overlap must not award repeated hits. Latch by incoming ball identity so one ball scores once.
- Derive a bounded shot target from racket face direction with a limited swing-direction contribution, and flight speed from meaningful contact speed. Show observable left/right and gentle/strong differences. Keep a forgiving arc; spin and full rigid-body physics are not necessary here.
- Clear contact history on pause, loss, recenter, route change, and ball replacement. Test both moving ball and moving racket between samples at 30/60 Hz.
- The teammate owns adaptive-opponent behavior. Supply recent valid player return observations and a bounded return-plan interface. The current strategy is synchronous and consulted more than once around return scheduling; cache one chosen plan per incoming return sequence to avoid delay/target inconsistency.
- If an external model is used, request a plan off the game loop with a deadline, validate finite/ranged output, and fall back to the deterministic returner. Ignore late plans for an old ball/run. No inference or network request inside `advance`/collision/render callbacks.
- An adaptive demo should visibly react to recent player behavior, with a reproducible test showing the change and a difficulty cap. Describe local heuristics as adaptive logic; call it trained/model-backed only when that implementation and evidence actually exist.

## 5. Orchestration and file ownership

Use one coordinator and at most three active implementation subagents. The existing UI task and human teammate retain their ownership; do not spawn duplicate UI or AI implementations. The two read-only audits used to prepare this plan are planning work only.

| Owner | Packet and files | Must not edit |
|---|---|---|
| Coordinator | Integration baseline, app-root `ArcadeSession`, `MotionModel`, `MultiplayerModel`, `ArcadeGame`, `TennisGame`, `TennisMatch` and `SaberScene` integration, `AircadeApp`, route composition, package/build union, final smoke flow | UI worktree while its owner is editing; teammates' unrelated work |
| A — Controllers | New `ControllerSession`/`PhoneControllerHost`, `PlayerControllers`, `ControllerLink`, `PhoneController`, small iPhone role/status changes, controller tests | Game rules, calibration math, Mac presentation, `MotionModel`, package/build files |
| B — Guest and results | `RunContext`/run policy, `PlayerSession`, profile/run tests, backend regression tests only if needed | Game views, route code, racket physics, station secrets |
| C — Racket contact | `MotionCore/RacketGeometry`, shot-response helper, pure geometry/response tests, a documented integration patch | `SaberScene`, `TennisGame`, `TennisMatch`, UI layouts until coordinator explicitly transfers ownership |
| Existing UI owner | Wii shell, theme, channel grid, pointer presentation, avatars, restyled views | Controller transport, calibration math, game rules, score eligibility |
| Human teammate | Tennis opponent strategy/adaptation and its focused tests | Common controller/session plumbing, root navigation, UI shell |
| D — Release QA (reuse a slot later) | Cross-game/recovery tests, smoke harness, acceptance report | Feature rewrites or changes that make an assertion pass by weakening it |

The coordinator integrates C's geometry into `TennisGame`, shared racket dimensions into `SaberScene`, and the teammate's strategy into `TennisMatch`. Transfer file ownership explicitly before allowing another writer. The UI owner can keep editing App/view files on its branch; the coordinator alone resolves their integration versions. Nobody mass-formats shared files.

Each implementation agent gets the exact baseline commit, this plan, a file allowlist, dependencies, acceptance checks, and forbidden changes. Return: commit(s), changed files, test command/result, API changes, known limitations, and integration notes. Report actual failures; never weaken tests to hide them. Do not launch/restart the user's physical app from a subagent.

Suggested branches: `codex/controller-session`, `codex/guest-run-policy`, and `codex/tennis-contact`, each cut from G0 in a separate worktree. Release QA starts from the latest integrated commit on `codex/arcade-release-checks`, not an earlier feature branch. At fan-out, publish the baseline hash and file ownership in the coordinator's execution notes; reserve contract changes for coordinator review before another agent depends on them.

The UI-facing session contract exposes connected devices, actual AirPod source, selected solo/menu controller, duel assignments, readiness reason, and pairing status/code. Actions are connect, assign, recenter, and forget. Views observe this contract; they do not create a listener or mutate another device's calibration.

## 6. Execution phases and gates

### Phase 0 — Preserve and establish a baseline (coordinator)

1. Recheck `main`, `origin/main`, `wii-shell`, worktree status, and changes since this plan. Record exact revisions and ownership before combining anything.
2. Preserve the last known working app bundle and intended local code on a named checkpoint. Include intended untracked iOS/controller/duel files; exclude build outputs, logs, `.local` credentials, and unrelated work. Do not reset, clean, or stash an actively edited checkout to make a merge convenient.
3. Create a `codex/arcade-integration` worktree from that checkpoint. Integrate teammate commits there, resolving current app routing and callbacks deliberately. Keep the original live checkout available as fallback. Final UI composition waits for its handoff.
4. Build and run the union's native suite. Resolve baseline integration errors before fan-out. Preserve iOS provisioning/signing settings and confirm the controller target still compiles.
5. Freeze the input/lifecycle, role messaging, run-context, and racket contact contracts above. Record the UI handoff requirements without sending unsolicited messages to the other task.

**Gate G0:** combined baseline compiles, existing tests pass, neither calibration nor phone/duel files were lost. Each agent branch has the same known starting point.

### Phase 1 — Independent foundation work (A, B, C in parallel)

- A extracts controller connection lifetime and supports device assignment independently of the duel. Updates phone role handling in the same packet.
- B implements guest/ranked/simulated run policy and tests without needing a database for guest play.
- C implements racket-face geometry and shot-response tests without touching the visual scene or teammate strategy.
- Coordinator prepares small game-input adapters and fake-controller fixtures against the agreed APIs. Avoid editing A/B/C-owned files. Review the UI handoff when available.

**Gate G1:** each packet has focused tests and a compile-clean handoff. Contracts match; no last-minute silent type/API changes.

### Phase 2 — Connect the games (coordinator; A helps only in its files)

1. Land the controller foundation. Remove listener/connection ownership from `MultiplayerModel`; retain its duel/scene responsibilities.
2. Wire one root session through the existing UI first. Make game enablement/navigation explicit and retain necessary legacy route shims for smoke scripts.
3. Feed the selected solo controller into Neon Rush and Tennis; feed assigned slots into the duel. Ensure phone-only solo play does not require a running/calibrated AirPod.
4. Carry guest/profile/provenance state into all run starts and results. Fix tennis simulated-score handling at both local-best and upload boundaries.
5. Centralize feedback routing and add phone feedback for solo games using existing cues. Role reassignment updates labels; completed runs cannot send delayed cues into the next game.
6. Add connection-persistence and route-switch integration tests before changing racket physics, making regressions easier to isolate.

**Gate G2:** synthetic phone can stay connected through Tennis → home → Neon Rush → home → duel; phone can be solo Player 1; no re-pair, duplicate polling, old-run damage, or score contamination. AirPod simple calibration regression tests still pass.

### Phase 3 — Tennis feel and optional adaptive returner

1. Integrate C's geometry/response through the production TennisGame path; use the same racket dimensions for rendering and collision.
2. Test complete rally sessions, five misses, timeout, restart, pause/recovery, and incoming-ball replacement. Add pose-driven app tests, not only direct calls to `playerHit`.
3. Connect the teammate's completed opponent if ready. Add deterministic fallback, cancellation/run identity, deadlines, and invalid-output tests before enabling a service-backed mode.
4. Tune angle, reach, speed, and generous hit windows using actual AirPod and iPhone trials. Document constants so the teammate can tune the opponent against stable ball behavior.

**Gate G3:** face angle and swing strength visibly change returns; shaft-only motion does not score; short gaps never create ghost hits; an unavailable/slow opponent service cannot stop the rally. Adaptive mode is advertised only after its own behavior checks pass.

### Phase 4 — Wii-shell handoff and integration

1. Accept the UI commit + handoff; reconcile route and pointer contracts. Keep its visual system rather than creating a competing layout.
2. Integrate shell as app navigation with Tennis, Neon Rush, Duel, controller setup, results, and optional profiles/leaderboard. Keep developer routes reachable.
3. Replace AirPod-only pointer/status bindings with session selection. Mouse/keyboard work without hardware, during stale tracking, and in every modal.
4. Apply the existing theme to Tennis and Duel where the UI branch predates those views. Restore/check all smoke entry routes and keyboard behaviors.
5. Bind available avatars to local player displays without coupling them to badge sign-in. Defer unfinished catalog breadth or decorative effects if they delay functional acceptance.

**Gate G4:** no dead channels, no pointer-triggered game actions, no missing active-controller labels, no setup trap, and no disconnect when returning home. UI and SceneKit gameplay are both inspected at the supported minimum window size.

### Phase 5 — Release verification and physical rehearsal

1. Run the combined `swift test` suite, Mac release build/signature checks, and iPhone build. Only run relevant suites repeatedly after new changes or failures.
2. Run native scripted Neon Rush and duel smoke modes, plus a new full Tennis smoke mode. Give all tests isolated stores/log directories; they cannot alter real scores or saved grips.
3. Run backend tests against an isolated test database if a MongoDB instance is available. Independently demonstrate guest play with no server running. An untested leaderboard is not described as verified.
4. Install the updated phone app if required by protocol/role changes, then perform the physical matrix below. Avoid multiple running Aircade instances fighting for motion or network state.
5. Record a working demo build and its source revision, controller app revision, startup instructions, known limitations, and fallback path. Update `VERIFICATION.md` to distinguish automated, physical, and still-unverified claims.

**Gate G5:** the end-to-end real-device journey succeeds repeatedly; no false pause on hits; controlled recovery works; results and replay work; no service dependency blocks guest play.

## 7. Acceptance matrix

| Scenario | Required behavior | Evidence |
|---|---|---|
| Fresh install/session, server unavailable | Guest can reach countdown and results without badge/camera/network requests | Injected backend-failure test + native run |
| Phone-only solo | Pair once, recenter, play Tennis and Neon Rush with AirPods stopped | Integration test + physical phone |
| AirPod-only solo | Existing three-pose capture and saved-source identity work in both games | Existing calibration suite + physical AirPod |
| Persistent session | Tennis → home → Neon Rush → home → duel preserves paired phone and grip state | Session identity/connection assertions + physical sequence |
| Slot reassignment | Phone can be P1 or P2; AirPod can occupy the other; feedback follows assignment | Transport/app integration + physical check |
| Short gaps: 0.280104, 0.32, 0.65 seconds | Freeze unsafe contact/time, clear history, recover without pause modal or phantom hit | Fake-clock production-path regressions |
| Sustained loss: 1.05 seconds; disconnect/source change | Clear reason, explicit recovery, no cross-source calibration, no moving replay across gap | Input integration tests + one physical reconnect |
| Inactive device disappears | Solo continues if its selected device is fresh; duel holds if an assigned device is lost | Assignment/recovery tests |
| Phone background/foreground | Pause honestly; reconnect if needed; no old frames accepted; calibration/ready state remains accurate | Session tests + physical phone |
| Contact quality | Face hit registers once; shaft/edge-outside-face misses; left/right angle and gentle/strong swings differ | Swept moving-ball tests at 30/60 Hz + physical tuning |
| Win/lose and replay | All three modes reach proper results; retry clears prior game state | Pose-driven full-run tests + smoke |
| Profile changes/offline uploads | Correct run-start owner, idempotent score, private stays private, guest/demo never public | Policy tests; existing backend suite where runnable |
| Delayed feedback/opponent result | An old run cannot affect a new run; invalid plans fall back immediately | Run-ID/deadline tests |
| Menu controller lost | Mouse/keyboard still navigate; reconnect does not auto-select a channel | Pointer tests + native inspection |
| Sound/effects enabled | Contact feedback does not block input or cause spurious pause | Frame/feedback timing logs + native/physical run |

Track transport RTT, source sample age, frame time, feedback duration, gap count, and pause reason separately. Establish before/after samples on the same device setup; do not describe RTT as motion-to-photon latency or claim zero lag from synthetic tests. Aim for a steady 60 Hz render loop and no new main-thread stalls; investigate repeatable long frames before increasing smoothing or masking stale input.

## 8. Subagent launch packets

These are implementation prompts to use after G0, not commands already dispatched.

**A — Controller foundation**

> From the provided integration commit, implement the controller/session contract in section 4 using your assigned files. Extract phone hosting from the duel; support persistent connections and slot-independent assignment. Update the iPhone's hardcoded Player 2 acceptance and status. Preserve newest-only delivery, real age/session checks, simple AirPod calibration behavior, and existing transport compatibility where possible. Add tests for role reassignment, route-independent lifetime, duplicate/old samples, stale input, and device isolation. Do not edit root routing, calibration math, or game rules. Hand back commit, API, tests, and coordinator integration patch instructions.

**B — Guest and run policy**

> Implement immediate guest play and explicit run-start identity/provenance using the assigned model files. Badge runs queue offline; guest runs stay local; simulated runs never affect real local/public bests. Profile changes cannot reattribute a run, repeated finish cannot duplicate it, and accepting simulated input downgrades eligibility. Use fake transport/temp stores to test without a live server. Preserve public opt-in. Do not modify view files or assume the coordinator has already wired game callbacks. Return the callback contract and tests.

**C — Racket contact**

> Implement pure bounded swept moving-ball/racket-face contact plus a bounded arcade shot response. Share dimensions with a future scene adapter; do not edit the scene or TennisGame directly. Exclude shaft-only hits, enforce one return per ball in the documented integration contract, and make normal/velocity available for angle/strength response. Cover between-sample motion, edge misses, stationary/slow returns, invalid input, and 30/60 Hz. Return the tested geometry API, constants, and explicit adapter instructions.

**D — Integrated verification, after foundations land**

> Audit the integrated baseline against section 7 and add missing production-path regression/smoke coverage. Use generated controller poses rather than direct score mutation. Test cross-game connection persistence, source changes, brief/long gaps, run provenance, replay, and delayed events. Report failures with reproductions; do not redesign visuals, weaken assertions, launch the user's physical app, or claim physical results. Hand off a compact acceptance report and exact unverified hardware steps.

## 9. Merge, rollback, and priority rules

- One coordinator owns integration commits and conflict resolution. Agents return focused commits from `codex/` worktrees based on G0; merge one completed packet at a time and check its affected tests before moving on.
- Integrate controller contracts before app adapters; guest/run policy before real score writes; contact helpers before shot tuning; shell after a stable handoff. UI readiness gates final composition, not all engineering.
- Preserve working calibration and input-recovery behavior as hard constraints. Do not re-enable the stricter calibration flow during this work.
- If extraction breaks existing play, return the integration branch to its own known-good checkpoint without altering the original checkout. Keep guest and scripted fallback routes available in release candidates.
- If time shrinks, keep the three playable games, reliable assignment, guest start, truthful results, and the basic Wii shell. Defer the large avatar catalog, motion-only menu polish, model-backed AI, and additional hardware. An incomplete optional feature must not block the working demonstration.
- Finish one release candidate and rehearse it. Do not add a new game after G4 unless every required acceptance check is already complete.

## 10. Final demo script

1. Open the Wii-style home screen and select **Play as guest**.
2. Connect the phone once; show both connected devices and the actual active AirPod source.
3. Select the phone for Tennis; demonstrate a left/right aimed return and a stronger shot.
4. Return home and enter Neon Rush using the same phone connection.
5. Return home and assign AirPod + iPhone to Saber Duel; show independent movement and phone contact feedback.
6. Finish a round, show the result, and rematch without pairing again.
7. If ready, show adaptive opponent behavior and the optional badge leaderboard as additional features. Keep the core path independent of both services.

**Decision:** proceed with the nonvisual foundations once the integration baseline and ownership contracts are settled. Wait for the UI agent's handoff only for shell/view composition; do not pause all development for the full aesthetic or avatar implementation.
