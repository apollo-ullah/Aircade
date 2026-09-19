# Aircade: AI Tennis implementation plan

Status: Phase 0 passed three live Astra screenshot/action/screenshot trials on `codex/astra-phase-zero`. Phases 1–3 are implemented, with live model rehearsal passing; physical-controller acceptance remains pending. Phases 4–6 now have implementation, but live Jev/exhibition acceptance is blocked by Vercel billing verification; physical acceptance remains pending. See `docs/AI-CHALLENGE-PHASE456.md`. Prepared September 19, 2026 against the published `f7d6af2` release. Estimates below are timeboxes for a hackathon implementation, not delivery guarantees.

Phase 0 evidence: seven automated checks and three scripted target trials pass. Separately, the live API run on September 19 at 22:19 UTC passed all three trials using nine requests to `gpt-6-astra`. Median completed-request latency was 3,100 ms; screenshot-to-action latencies were 3,427 / 3,345 / 2,256 ms. Each fresh trial also incurred a preliminary screenshot request, so these action measurements exclude session startup and final confirmation. See `docs/ASTRA-PHASE-ZERO-RESULTS.md`. Normal-speed live tennis remains unproven; begin Phase 1 with manual controls and use the measured latency to choose an explicitly labelled experimental speed in Phase 2.

Implementation evidence: `docs/ASTRA-PHASE123-RESULTS.md`. The challenge uses an isolated local sidecar rather than adding screenshot routes to the existing badge/leaderboard server. This keeps model traffic and credentials independent of the working station. The sidecar and existing GLM rival are separate integrations.

## Product outcome

**Hold an AirPod and challenge an AI that watches the court and operates its own racket.**

Ship Astra versus a human first, with a visible record of the screenshots and actions that produced each return. Then offer Jev and the existing GLM rival as distinct opponents. AI versus AI is a stretch milestone after the human experience passes physical acceptance.

The required demo is a real rally: a person swings, Astra observes the ball, commands movement and a swing, and the game's collision logic determines whether it connects. A late or incorrect model action can lose a point.

## Current foundation and required changes

| Existing component | Reuse | Required change |
| --- | --- | --- |
| `Sources/MotionCore/TennisMatch.swift` | Ball flights, bounces, match clock and player returns | Add an explicitly controlled opponent mode. Current `defenderContactX` is calculated from the ball's destination and a movement allowance; it cannot remain the interception authority in Astra mode. |
| `Sources/MotionCore/RacketGeometry.swift` | Swept racket contact and shot-response math | Apply the geometry in the opponent's coordinate frame, with tests for mirrored axes and court sides. |
| `Sources/Aircade/TennisGame.swift` | Native update loop, human input, pause/recovery, events | Separate opponent commands from the legacy return-plan strategy; own asynchronous session lifecycle and expire old commands. |
| `Sources/Aircade/SaberScene.swift` | Court, ball and opponent artwork | Render the controlled racket pose from physics state. Disable automatic tracking and snap-to-ball animations for controlled opponents. |
| `Sources/Aircade/BasetenTennisOpponent.swift` | Working GLM integration and validated plans | Keep the existing tactical rival available and describe its assistance accurately. |
| `Sources/Aircade/TennisSmoke.swift` | Native rendered scene captures and scripted input harness | Add repeatable incoming-ball trials and render the actual AI observation view. Existing captures demonstrate that SceneKit must be captured separately from ordinary UI bitmaps. |
| `server/server.mjs` | Local station authentication and backend API credentials | Add separate opponent sessions, providers, screenshot transport, control events and trace storage. The current global JSON body limit is 8 KB; screenshots need a bounded, route-specific binary upload. |
| `TennisView.swift`, `RunContext.swift`, `PlayerSession.swift` | Wii presentation, physical controller flow, run identity and results | Add opponent choice, challenge results and variant-specific score eligibility. |

No new AirPod relay, phone slots, game engine or controller calibration is required.

## Architecture decisions

### Two opponent contracts

- **Controlled player:** receives observations and supplies inputs that move and swing a finite racket. Astra uses this contract. Jev can use the same contract with text observations.
- **Tactical rival:** chooses a return strategy while local code handles interception. The current GLM implementation uses this contract. Do not present it as a screenshot-controlled player.

Sharing provider selection and diagnostics does not make these contracts equivalent. Keep the distinction visible in the opponent descriptions and results.

### Astra's computer-use surface

Use a small, isolated browser page for the AI's controller. It displays a live rendered view of the native court and offers mouse-based racket positioning plus click/keyboard swing controls. It contains no second physics engine. A human must be able to operate the same page manually before a model is connected.

The local station runs a persistent isolated browser session. Astra uses the Responses API's supported `computer` tool. The station executes returned mouse/keyboard actions on that page and returns the resulting screenshot. This deliberately selects the structured-action alternative to OpenAI's recommended code-execution integration so the initial implementation has a narrow action surface.

```text
Human AirPod -> existing input mapping -> native Tennis physics
                                                |
                                  actual rendered court view
                                                v
                              isolated browser controller page
                                                |
                              screenshot -> Astra Responses API
                                                |
                            computer-tool mouse/keyboard actions
                                                v
                       browser input -> bounded native racket commands
                                                |
                                      real hit or real miss
```

The browser remains separate from the foreground Mac app, avoiding focus-related pauses. Only the game viewport is captured. Astra receives rendered observations and control instructions, without hidden ball coordinates, future trajectories or the native state objects. No automatic aim, ball following or interception is inserted below its inputs.

Local code may smoothly move toward a model-selected target and execute a fixed swing animation at bounded speed. Those are controller mechanics and must be identical for manual and AI operation. The collision racket and the visible racket use the same pose.

### Timing, identity and failure behavior

- Native physics targets 60 Hz. Screen capture and model requests run independently; verify snapshot overhead before setting a capture cadence.
- Keep one inference request in flight per opponent and retain only the latest pending observation. Do not build a backlog of obsolete frames or inputs.
- Stamp observations/actions with session, run, rally, sequence, rules version, frame identity and capture time. Use monotonic clocks; do not compare unrelated process uptimes without a defined mapping.
- Reject expired, duplicate, out-of-order and previous-rally commands. Bound action count and execution duration. A pause, replay, route exit or provider change invalidates the old session generation.
- Snapshot age, request latency and input application delay are separate measurements. Time-to-first-token alone is not controller reaction time.
- Network waiting never freezes the live match. After an action lease expires, release input and let normal physics determine misses. Authentication/service failure shows an explicit interruption; switching to the local rival starts a separate, clearly labelled run.
- A slower game mode, if needed, uses a fixed visible speed selected before the match for both sides. Never pause invisibly between screenshots or give only the AI extra simulation time.
- Store model credentials only on the station. Apply per-session request/spend caps and cancel outstanding work when a session ends.

## Phase 0 — Confirm API access and measure the first action

**Timebox: 20–30 minutes. Dependency: none.**

1. Create a feature branch from the published release and record the baseline build/test evidence.
2. Configure an OpenAI API key outside version control. Verify this account can call exactly `gpt-6-astra` with the computer tool. Availability in Codex is not proof of API access.
3. Use a minimal local browser control page with a captured court frame and one visible target. Ask Astra to inspect it and perform a visible move/click; execute the returned input and send the next screenshot.
4. Run a small, bounded batch of calls. Record completed-action latency, failures and actual token usage/cost. Check against the game's current roughly seconds-long ball flights.

**Exit:** one real screenshot/action/screenshot loop succeeds, with measured timings and model identity. This proves integration, not tennis skill.

**Stop condition:** resolve access or unsupported tool errors before building model selection UI. If response latency cannot fit normal ball travel, choose an explicitly slower experimental mode before proceeding; do not claim normal-speed reaction.

## Phase 1 — Build a racket that inputs actually control

**Timebox: 60–90 minutes. Dependency: Phase 0 access check.**

1. Add a pure `TennisOpponentController` state model for position, movement target, racket pose, swing phase and cooldown. Add a small validated command type with source/run/rally identity and expiry.
2. Bind the browser's mouse position to a documented, bounded racket target. Use an explicit click or key for forehand/backhand swings. Keep the first control scheme small and display its instructions on the page.
3. Reuse swept contact geometry in the far-court frame. Require an actual swing/contact to return the ball. Remove automatic `defenderContactX` success and ball-chasing scene actions from this mode.
4. Preserve the existing GLM rally mode behind its existing contract. Give the new challenge a 60-second scoreboard: opponent miss awards the human a point; human miss awards the AI a point; highest score at time wins, with a draw on equality. Alternate serves after points using a neutral, explicit serve sequence.
5. Create seeded test shots toward left, center and right. Add a manual browser-control rehearsal and scripted commands through the same input path.

**Exit:** a manual operator can return shots, stationary or misplaced rackets miss, and each rally awards at most one point. Tests cover both court frames, movement limits, contact timing and win/draw conditions.

## Phase 2 — Connect Astra to live Tennis

**Timebox: 60–90 minutes. Dependency: Phase 1.**

1. Add a fixed-resolution AI court view rendered from the authoritative native scene. Choose and document the camera orientation; test that screen-left maps to the intended court direction.
2. Upload bounded frames through authenticated station routes and display the latest frame on the controller page. Freeze the page's frame during screenshot capture long enough to attach the exact frame ID; resume updates immediately afterward.
3. Implement the Responses computer-use loop with tool-call IDs and screenshot outputs. Execute only supported input actions in the isolated game page; report unsupported actions without silently replacing them.
4. Translate browser input events into the same command path used by the manual operator. Stamp model actions with the observation's identity and age, not just the time the input event arrived.
5. Discard old responses across pause, point change, replay and cancellation. Never reuse a swing request on the next ball.
6. Run ten reproducible balls without a human, then a physical AirPod match. Save the observation/action traces for each return or miss.

**Exit:** at least three real returns across the ten-ball trial, including more than one target lane, with no interception helper or fallback; then a complete physical human-versus-Astra round. The hit-rate target is a demo usability gate, not a capability claim from a ten-shot sample.

**Decision:** first improve screen legibility, control instructions or fixed game speed if the model struggles. If it still cannot return reliably within the timebox, retain it as a clearly labelled experiment and keep the working GLM game as the playable demo. Do not mask failures with an automatic opponent.

## Phase 3 — Make the achievement visible and fun

**Timebox: 30–45 minutes. Dependency: Phase 2.**

1. Add a Wii-style Astra opponent card and a clear challenge CTA: **Can you beat Astra?**
2. Show a compact panel with the exact last observation, visible action/cursor, observation age, decision latency and return count. Show actions and optional short model-provided summaries, not invented reasoning.
3. Display human and AI points, announce winners, support rematch and next player, and retain AirPod menu navigation and Mac-speaker audio.
4. Explain failures in place: thinking, input late, service unavailable. Make experimental speed visible on both the play screen and results.
5. Initially keep the new challenge out of the existing Tennis ranking: different scoring and assistance cannot share the legacy board. Preserve the badge identity so Phase 5 can attach valid variant-specific records.

**Exit:** a new player can identify who controls the opponent and what it just did. A 60-second physical round, results and rematch work without debugging UI.

**Minimum shippable feature:** Phases 0–3. This is the critical path and gets priority over a third provider or spectator mode.

## Phase 4 — Offer three distinct AI opponents

**Timebox: 45–75 minutes. Dependency: Phase 3.**

1. Add a provider catalog with configured, connecting, ready and unavailable states. Select an opponent before starting; changing it creates a new session.
2. Keep **Astra / Screen control** and **GLM / Tactical rival** available through their correct contracts. Preserve the existing GLM game behavior and provider/fallback labels.
3. Add **Jev / State control** through Vercel AI Gateway's supported evaluation interface after verifying its API key and installed SDK compatibility.
4. Give Jev compact current/past state, including observed ball/racket positions and time deltas, and ask typed questions for movement, swing timing and stroke. Exclude future landing coordinates or precomputed winning actions. Bound the output and execute it through Phase 1's controller.
5. Measure completed decisions in the actual deployment. Use observed latency in the UI; do not hard-code a claim that Jev is the fastest.
6. Describe inputs and local assistance on each card. Astra's screen-only play, Jev's state access and GLM's automatic interception are different systems, so their results do not establish a fair ranking of raw model intelligence.

**Exit:** all three choices make live requests to their named providers and complete their respective physical play modes. Missing credentials or provider failure cannot silently launch another model under the selected name.

**Scope limit:** converting GLM to full racket control is optional follow-up work, not necessary for the three-choice MVP. Label its tactical mode clearly.

## Phase 5 — Scores, regression checks and judging rehearsal

**Timebox: 45–60 minutes. Start after Phase 3; Phase 4 can be cut if time is tight.**

1. Add a separate AI Challenge score record keyed by model/provider, control mode, rules version and speed. Include the immutable run/profile identity and whether any assistance, simulation or provider interruption occurred. Define the ranking before displaying a board: wins, then point differential, then human points for the same variant.
2. Permit eligible physical human runs on that variant's board. Keep scripted trials, AI-versus-AI, legacy Tennis and alternate speeds separate. Never queue an experimental result as a normal Tennis high score.
3. Run focused tests for racket commands/collisions, timestamps, stale responses, exactly-once points, match results, provider errors and score eligibility. Re-run the established full Swift and station suites once after integration, then build the signed release.
4. Verify three consecutive physical challenge rounds, including rematch, next player and a controller reconnect. Check that AirPod input/rendering remains responsive during requests and screenshot capture.
5. Rehearse provider outage, exhausted request budget and unavailable key states. Stop/cancel must end model activity and release input. The fallback demo is an explicitly selected legacy GLM/local run.
6. Capture a backup video and a small reproducible trace. Record ordinary and slow-tail action latency, return rate, missed deadlines and per-match cost. Clearly mark the sample size and mode.
7. Prepare a four-minute demo: AirPod hook, one Astra rally with observation/action panel, results, brief engineering explanation and optional Jev comparison. Update public docs and Devpost claims to the evidence actually collected.

**Exit:** three complete physical rounds without an unexplained pause or restart, truthful scoring/provider attribution, passing regression checks and a working backup demonstration.

## Phase 6 — Bonus: AI versus AI exhibition

**Timebox: 45–90 minutes. Dependency: Phase 5; optional.**

1. Instantiate two independent controlled-player sessions with separate observation views, response histories and action queues. Remove the human-input freshness requirement only for this explicit spectator mode.
2. Reuse the same court bounds, contact rules and scoring on both sides. Astra versus Astra is the simplest initial comparison; Astra versus Jev is an exhibition of different observation interfaces, labelled accordingly. GLM can join only with disclosed assistance or a completed controlled-player adapter.
3. Show both last actions, latency and points. Apply per-side and total request budgets. Keep the mode explicitly startable/stoppable rather than starting billable matches automatically.
4. Store exhibition results separately from human badge scores. A provider timeout leaves the affected player idle or visibly ends the exhibition; it never hands control to an unlabelled bot.

**Exit:** a complete unattended match with a winner/draw, separate provider traces, no cross-wired inputs and no human leaderboard contamination.

## Build order and time decisions

`API proof -> manual opponent controls -> live Astra rally -> presentation -> physical acceptance`

Insert Jev/provider selection after the Astra presentation only if enough time remains for acceptance. AI-versus-AI comes last. Expected core work is roughly four to five hours before final acceptance, with meaningful uncertainty in model latency and collision integration. Timeboxes are points to reassess scope, not reasons to declare an unverified phase complete.

Commit after each passed phase. Keep the published release available for immediate launch while the feature branch evolves. The first acceptance evidence to seek is a model-produced return, not a polished provider selector.

## Official references

- [OpenAI computer use](https://developers.openai.com/api/docs/guides/tools-computer-use): screenshots, application-executed actions and the supported structured computer-tool alternative.
- [GPT-6 Astra model](https://developers.openai.com/api/docs/models/gpt-6-astra): model identifier and supported capabilities; account access still needs a live check.
- [Jev on Vercel AI Gateway](https://vercel.com/ai-gateway/models/jev): `typesafe-ai/jev` and the typed evaluation interface.
- [Vercel's Jev explanation](https://vercel.com/i/what-is-jev): text-based inputs and the limits of a decision model.
