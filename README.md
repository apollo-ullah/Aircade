# Aircade

### Your earbuds are the controller. Astra is the opponent.

**We turned an AirPod into a Wii-style motion controller—and built an arcade where humans and AI can play through different interfaces.**

Pick up an earbud, tilt through the menus, and swing it like a tennis racket. Slice through Neon Rush or pair an iPhone for a two-player saber duel. Then open the sensor and AI decision views to see how a physical movement and a model's choice become actions on the same court.

Built at **Hack the North 2026** with Swift, SwiftUI, SceneKit, Core Motion, the OpenAI Responses API, and Codex.

[Watch the demo](https://www.youtube.com/watch?v=xdL29Ifvi_A) · [Devpost](https://devpost.com/software/aircade-m4n6zv) · [iPhone companion](iOS/README.md)

## For OpenAI judges

**Codex helped build the arcade, then became a participant in the world it helped us build.** Our integrated judging build explores two interfaces for AI play and makes their behavior visible.

| OpenAI contribution | What we built | What judges can inspect |
| --- | --- | --- |
| **Astra through the Responses API** | A tactical rival that chooses a legal tennis return from the current game state. | Input summary, latest selected shot, actual applied shot, request timing, and decision IDs. |
| **Codex as an engineering collaborator** | Parallel implementation, native UI testing, API integration, sensor inspection, and regression tests. | A specific scheduler bug, its repair, and the verification described below. |
| **Codex computer use** | An experiment controlling the rival through the visible game window. | Court movement and Rival Swing controls, explicitly slower play and buffered swings. |

The API rival and computer-use experiment use different controls and timing. The game's Astra integration makes actual OpenAI API requests; desktop control is a separate experiment.

## Why OpenAI

We wanted to explore what an AI can **do** in a game: choose a return, act through an interface, and participate while a human holds a physical controller.

The Responses API gives us a constrained decision boundary. Astra can consider the state and select a shot while a strict output schema keeps its choice inside the game's legal actions. That makes the result testable and visible on court.

Codex connects development to interaction: it helped implement the system, inspect the native app through computer use, and investigate failures. We then used visible game controls to explore computer use as a way of playing. The same arcade becomes a motion game, an AI opponent interface, and a small experimental environment.

## How the OpenAI API changes the game

1. The native game captures tactical state and supplies five legal return candidates.
2. A local Node station sends the shared objective and state to **GPT-6 Astra through `POST /v1/responses`**.
3. Strict JSON-schema output requires exactly one supplied `candidateID`.
4. The station validates the response. The selected candidate determines target, flight duration, delay, and stroke.
5. Swift handles movement, animation, and contact. The UI records which decision actually became a shot.

```text
AirPod → Core Motion → grip + neutral-pose mapping → racket → geometric contact
                                                        ↓
Game state + five legal shots → local station → OpenAI Responses API
                                                        ↓
Validated candidate → native return → applied-decision evidence
```

Requests run asynchronously. A previous genuine decision may be reused with a **Cached** label if a refresh fails. A late response from an abandoned run cannot overwrite the next one. API keys stay on the station.

In **AI shot decisions**, the latest response and the applied shot are separate facts. Judges can inspect them from the lobby, pause screen, and results without racing the match clock.

## Codex's contribution: a bug we can show

Our first live comparison reported seven rate-limit failures taking **0 ms**. Reviewing the report with Codex exposed the problem: those calls never reached either provider. Fractional waits could wake before our own scheduler's next permitted request time.

Codex helped repair the runner to read the planner's actual monotonic clock, round waits upward, and check eligibility again after every wake. It also separated local admission failures from provider HTTP 429s and added a regression that deliberately wakes timers early.

**Verification:** the station suite passed **25/25 tests**. A new complete live run then delivered **80 valid decisions from 80 requests**. The original run remains diagnostic evidence; failed rows were not replaced individually.

Computer-use testing also caught a native menu freeze caused by a configuration-file read during UI rendering. Configuration now loads off the UI thread with a timeout, and a regression verifies that a stalled read leaves the main actor responsive.

The integrated judging build includes a detailed development record and a judge-facing evidence card.

## A controlled tactical comparison

We gave Astra and Jev **the same twenty frozen synthetic states, five legal shots, candidate order, and objective**, repeated twice per provider. Both used a six-second deadline, at least 2.2 seconds between request starts, and one in-flight request per provider. Endpoint serialization differs.

| Corrected recorded run | Valid decisions before deadline | Median request time | Observed range |
| --- | ---: | ---: | ---: |
| Astra · OpenAI API | **40 / 40** | **1,836.5 ms** | 1,324–4,014 ms |
| Jev · Vercel AI Gateway | **40 / 40** | **322 ms** | 236–1,257 ms |

Recorded September 20, 2026. All 80 attempts remain in the report. These numbers measure decision validity and request latency under our configured tactical interface; they do not rank tennis skill or establish a causal token-efficiency advantage. Native code supplies movement and contact for both rivals.

The team has retained the complete JSON, interactive comparison report, and native API-to-contact evidence with the judging build. Those artifacts are not yet published in this repository.

The separate **Codex · computer use** mode operates visible controls. Incoming play is slowed, early swings are buffered, and runs are unranked. Its results are not included in this table.

## Why an AirPod?

An earbud already contains a wireless motion sensor. We repurposed it as the object you hold to play.

Turning those readings into a controller required grip calibration, a neutral reference, freshness checks, contact detection, and recovery when tracking changes. **A fast swing alone is not a hit:** the racket must make geometric contact with the ball.

The **How it works** screen shows fused Core Motion readings, calibration, and racket output. New eighteen-second captures preserve the actual mapping for display-only replay. An earlier bundled sample contains real input with its reconstructed mapping clearly labelled. We also captured 552 fresh Left AirPod samples in the final build with their original mapping; that nearly stationary trace verifies capture, not a handheld swing.

AirPod orientation does not provide absolute hand position. Optional camera tracking supplies a separate screen-plane hand-position signal; tennis moves the character automatically. One active headphone motion stream led us to use an iPhone as the second controller in Saber Duel.

## Play the arcade

- **Tennis:** a 60-second rally challenge with geometric racket contact, AI rivals, results, and replay.
- **Neon Rush:** three rounds of slashing, directional targets, hazards, and combos.
- **Saber Duel:** two-player AirPod + iPhone combat with independent motion streams and phone haptic cues.
- **Practice:** calibration, diagnostics, optional camera tracking, and reproducible scripted checks.

The native app uses SwiftUI and SceneKit. The local station uses Node.js and MongoDB for model requests and optional player profiles. Menu music and game sounds can play through the Mac speakers while AirPods supply motion.

## Source availability

The public `main` branch contains the complete integrated judging build, including the Astra Responses API opponent, Codex computer-use experiment, sensor inspector, badge flow, and native leaderboards. The existing 54-second video predates some of those additions, so the README and Devpost gallery show the final judging experience in more detail.

## Run locally

Requires macOS 14+, Xcode / Swift 5.9+, compatible AirPods, and Node.js/MongoDB for the station. iPhone setup is documented in [the companion guide](iOS/README.md).

Put `OPENAI_API_KEY` in the ignored root `.env` for Astra; `AI_GATEWAY_API_KEY` enables Jev and `BASETEN_API_KEY` enables Baseten. Never commit those values.

```sh
# Terminal 1: local model/profile station
./scripts/start-station.sh

# Terminal 2: build, prepare local configuration, and open the signed app
./scripts/run.sh
```

Connect the controller, calibrate the active earbud, and recenter in the intended grip. The integrated judging build's tactical match requires both fresh controller input and a validated model plan. Judge first-hit timing through a physical rehearsal; automated checks cannot establish controller feel.

[Existing verification guide](VERIFICATION.md) · [iPhone setup](iOS/README.md)

## What comes next

Measure first-hit time with unfamiliar players, capture more real rallies with their original calibration metadata, and extend agent experiments with matched inputs and timing. Keep the core experience simple: pick up an earbud, understand it, and want another turn.
