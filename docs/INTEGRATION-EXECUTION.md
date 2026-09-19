# Implementation execution record

September 19, 2026. Active integration checkout: `../Aircade-integration`, branch `codex/arcade-integration`.

- Original `Aircade` checkout and its uncommitted work preserved. Fallback app: `Aircade/build/Aircade-pre-integration.app`.
- `fff08e7`: checkpoint of working AirPod + iPhone multiplayer and implementation plan.
- `a96e170`, `2cac5e1`: teammate badge/profile and tennis commits incorporated, retaining multiplayer and iOS code.
- G0 baseline `2cac5e1`: all 75 native tests passed; generic iOS unsigned build passed. Logs: `/tmp/aircade-g0-tests.log`, `/tmp/aircade-g0-ios.log`.
- UI owner remains on `wii-shell` in `../Aircade-wii-shell`; work is in flight. No UI files copied prematurely.

## Active implementation ownership

- Coordinator: `MotionModel`, app-root/navigation, `ArcadeGame`, `TennisGame`, `TennisMatch`, `SaberScene`, final presentation integration and release checks.
- Controller agent: `../Aircade-controllers` / `codex/controller-session`; ControllerSession, phone hosting/protocol/iOS, controller tests. Explicitly transferred `MultiplayerModel` extraction to this agent.
- Guest agent: `../Aircade-guests` / `codex/guest-run-policy`; PlayerSession, RunContext, isolated policy tests.
- Racket agent: `../Aircade-racket` / `codex/tennis-contact`; pure RacketGeometry/TennisShotResponse and tests only.

All feature worktrees start at `2cac5e1`. Root cherry-picks completed packets; no other agent launches the real app. The root will use the next free agent slot for integrated regression testing.

## Agreed contracts

- ControllerSession owns transport lifetime and latest snapshots independently of games. Snapshot timestamps remain stable. Root submits accepted calibrated AirPod samples, selects solo/menu device and duel slots, and reacts to input/invalidation callbacks. Phone accepts role changes without reconnecting.
- PlayerSession captures RunContext at start, observes simulated input to latch ineligibility, and completes once using the retained run ID. Completion returns local-best eligibility. Guest starts locally; badge sign-in remains optional.
- RacketGeometry sweeps a finite face against both ball positions. TennisShotResponse maps validated face contact to target/speed. Root applies results to TennisMatch and shares dimensions with SceneKit.

## Release status

Implementation in progress. G1–G5 not yet complete. Automated or compiled paths do not establish physical performance. UI handoff, updated phone installation, cross-game physical play, and MongoDB service checks remain outstanding.
