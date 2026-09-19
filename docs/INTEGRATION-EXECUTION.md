# Implementation execution record

September 19, 2026. Active checkout: `../Aircade-integration`, branch `codex/arcade-integration`.

## Implemented

- App-lifetime controller session: one AirPod stream and one independent iPhone, persistent pairing across channels, solo/menu selection, either duel slot, explicit unpair/recenter, stable sample ages and connection epochs.
- Phone-only Tennis and Neon Rush, plus AirPod + iPhone Saber Duel. The original simple AirPod calibration and per-earbud saved mappings are preserved.
- Immediate guest play without badge/backend; run-start identity, simulation disqualification, local records, offline profile queue, idempotent completion. Optional profile service remains separate.
- Swept finite racket-face collision against a moving ball, shared visual dimensions, bounded angle/strength shot response, no stationary/shaft-only scores, one return per ball. The automatic opponent chooses one validated plan per return.
- Wii shell merged from the UI owner's clean `5e6027a` handoff. Six working channels: Tennis, Neon Rush, Saber Duel, Controllers, Players & scores, Practice. Settings contains scripted tests, menu-pointer selection, sound controls and diagnostics. Avatars stay deferred.
- App-root route ownership stops inactive games while keeping transport and calibration alive. Space/R are route-aware. Mouse movement can temporarily override the motion pointer; reacquisition cannot immediately select a channel.
- Equal/older sensor timestamps cannot erase a valid swing's collision history.

## Orchestration and checkpoints

The coordinator established G0 (`2cac5e1`) from a preserved local checkpoint (`fff08e7`) and the teammate's badge/tennis commits. Original `Aircade` checkout and its uncommitted work remain intact. Fallback app: `Aircade/build/Aircade-pre-integration.app`.

| Packet | Owner / isolated worktree | Integrated commits |
| --- | --- | --- |
| Persistent controllers, phone roles, duel timing | Controller agent / `Aircade-controllers` | `41391ff`, `b3a442f` |
| Guest/run eligibility and offline queue | Guest agent / `Aircade-guests` | `c2edb8a` |
| Racket face geometry and shot response | Racket agent / `Aircade-racket` | `0bd8ddd` |
| App adapters and run/feedback wiring | Coordinator / `Aircade-integration` | `35b3b81`, `fa02e07` |
| Full Tennis production-path tests | Release QA / `Aircade-qa` | `6679960` |
| Cross-game actual TCP/MotionModel tests | Release QA / `Aircade-cross-game` | `73cfdf1` |
| Timestamp regression tests | Release QA / `Aircade-cross-game` | `4457daa` |
| Wii composition and native route harness | Coordinator, UI-owner handoff | `c1d0952`, `042c8cf`, `d49f661` |

Each agent returned focused commits; no agent edited another owner's worktree or launched the user's physical app. The coordinator alone integrated and launched native smoke runs.

## Software verification

- G0: 75 native tests passed; generic unsigned iOS build passed.
- Integrated suite: **162 tests passed** (79 MotionCore, 3 ControllerLink, 80 Aircade), including actual local TCP controller traffic, full game rules, guest/profile policy, calibration, packet gaps and cross-game session continuity. `/tmp/aircade-final-tests.log`.
- Mac release build/ad-hoc signing passed. `/tmp/aircade-final-build.log`.
- Updated physical-device iPhone target compiled and signed for the configured team using a generic device destination. `/tmp/aircade-release-ios.log`. This is not an installation claim.
- Native shell: all 13 route transitions passed, preserving the pairing code and activating only the selected game. Script setup starts the real game and leaving it clears simulation. Captured every channel and inspected layout, setup, profile, settings and duel. `build/release-shell/`.
- Native Tennis: 60 seconds, 24 returns, 0 misses, 10,040 points, results reached, no queued score. Generated orientations enter the actual input and racket collision pipeline. `build/release-tennis/`.
- Native Neon Rush victory: 60 seconds, 43 perfect cuts, 21,300 points, all five lives, no mistakes, no modal interruption; sound/effects enabled. Max feedback duration 0.59 ms, max frame 98.1 ms. Simulated high score unchanged. `build/release-win/`.
- Native Neon Rush defeat: five misses, zero lives, proper results, no false pause, no saved score. `build/release-defeat/`.
- Native Saber Duel: full scripted blue victory, health [5, 0], proper results. `build/release-duel/`.
- `ffec818`: final audit fix renews the feedback recipient/session on an actual solo resume while preserving score ownership/provenance. Three added recovery tests exercise actual local TCP traffic. Old feedback UUIDs are rejected. All 162 tests pass together.

- Final rebuilt native reconnect smoke: tracking loss froze match time, reconnect/resume continued to 13 geometric cuts and 2,200 points, proper results, unchanged high score. `build/release-recovery/game-smoke-result.txt`.

## Physical release gate remains open

The updated iPhone app has not been installed because the previously trusted phone is currently reported unavailable by `devicectl`. The user was asked to reconnect and unlock it; no response yet. No physical AirPod/iPhone performance or haptic output is claimed for this integration build.

After installing the updated companion: connect once, play phone-only Tennis, return home, play Neon Rush, return home, play duel with AirPod + phone, swap slots, rematch, and check explicit disconnect/recovery. Recheck physical lag and feedback. The earlier user-confirmed hardware build remains separate evidence, not proof of this updated protocol.

MongoDB/station integration remains unverified against a running database; guest and offline policy tests use isolated stores and fake service responses. The trained/adaptive opponent, avatars, extra phone slots and external haptic motors remain outside this core milestone.
