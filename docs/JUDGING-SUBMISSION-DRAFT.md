# Aircade judging and submission draft

Prepared from the implemented judging build. This is a script and descriptive copy, not evidence that physical rehearsals or unfamiliar-player tests have passed. The corrected paired API run completed on September 20, 2026; its results are recorded below. A pitch cannot guarantee finalist selection.

Read-only browser review confirmed that Devpost is **already submitted**, OpenAI's prize is selected, and a 54-second physical-demo video is already embedded. The copy below is a proposed update, not the current public text. See [SUBMISSION-AUDIT.md](SUBMISSION-AUDIT.md) for source-access gaps and the existing video's verification limits.

## Four-minute demo

Before starting: use the signed app, start the intended station, select **Astra · OpenAI API**, verify a valid model decision, and hand over a preconnected, calibrated, identified earbud. Use Guest. Keep a labelled prerecorded backup ready only if a real recording has been made and checked. Do not spend the judging slot pairing Bluetooth or signing in.

| Time | Show and do | Say |
| --- | --- | --- |
| 0:00–0:15 | Hold up the active AirPod. Tilt it so the on-screen racket visibly follows. | **“This AirPod is our tennis racket. We turned the motion sensors in an everyday earbud into a Wii-style controller.”** |
| 0:15–0:55 | Hand it to the judge, recenter the known grip if needed, and start a rally. Keep the instruction to one sentence. | “Keep it fixed in your fingers. Swing when the ball reaches your racket; your player runs automatically.” Let the first genuine hit speak for itself. |
| 0:55–1:25 | Open **How it works** to pause the match. Show a live tilt through the three stages. If showing the bundled sample, switch to **Recorded trace** and identify its source. | “Core Motion gives us an angle and rotation speed. Our calibration maps your grip and neutral pose into the racket. A hit still requires racket-ball contact.” For the bundled sample: **“These are real recorded AirPod readings; this example reconstructs the racket mapping because the original mapping was not saved.”** |
| 1:25–2:05 | Close the sensor screen and explicitly Resume. Expand **AI shot decisions**. Show an actual applied candidate and its decision identity, not just the newest response. Let the round reach results if it has not already. | “Astra receives the game state and five legal shots through the OpenAI API. It chooses the shot; our game handles movement and contact. This is what it received, this is its latest response, and this is the decision actually used on court.” If cached, say it is reusing a previous real decision. |
| 2:05–2:30 | Show results and **Replay rally**. Start the next round, then pause before the explanation. If the original round is still running, use this time to finish it first. | “The controller and rival stay selected, so the next person can play immediately.” |
| 2:30–3:00 | Show `docs/evidence/DecisionComparison.html`, the corrected completed comparison. Keep the conditions and denominator visible. | “We also tested twenty fixed situations twice per provider, with the same state, shots, and six-second deadline. Both delivered forty legal decisions out of forty requests. Median request time was 1.84 seconds for Astra and 322 milliseconds for Jev. That measures decision delivery, not independent tennis skill.” |
| 3:00–3:25 | Give the specific Codex debugging story, with one evidence card if useful. | “Our first comparison showed seven instant rate-limit failures. Codex helped trace them to our own scheduler: a fractional wait could wake too early. We fixed it to recheck the actual request clock and added a regression that deliberately wakes early. Local rejections and provider failures are now separate in the report.” |
| 3:25–4:00 | Return to the racket and leave time for the judge to try again or ask a question. | “Pick it up and challenge Astra.” |

Keep the story flexible around the real round. If the round finishes before the sensor segment, use **How it works** from the lobby and then replay. Do not navigate into the separate training lab during an active round. If the controller or API repeatedly fails, acknowledge the observed failure and use a clearly identified real backup if available.

## Short answers for the likely questions

**“How are you getting position from an AirPod?”** We primarily use orientation. A saved neutral pose and grip axes map the earbud's rotation to a racket. We do not integrate acceleration into absolute 3D hand position. Optional camera tracking supplies a separate screen-plane hand-position signal; tennis moves the character automatically.

**“Is that sensor screen live?”** The selected mode says so. Live input reflects the active controller. The bundled example contains about eighteen seconds of real recorded input with a reconstructed racket mapping. A fresh recording made in the new build can preserve the actual reference, grip basis, smoothing, racket output, and available game events. Playback is display-only and cannot control the match or change its score.

**“What is the AI actually doing?”** The tactical API model selects a legal return: target, pace, delay, and stroke. Native code performs movement, collision, and contact. The panel separates the newest response from the decision actually applied and labels cached reuse.

**“Didn't you also use computer use?”** Yes. The separate Codex computer-use experiment observes the game window, moves the rival through visible controls, and presses swing. Incoming play is slowed and early swings are buffered; it is unranked. Those results are separate from the shared-state tactical API comparison.

**“Which model won?”** Only state the corrected completed run's measured outcome. This small comparison measures timely legal decisions and request latency under a shared tactical contract. It does not establish tennis skill or prove that token efficiency caused a difference. Endpoint serialization differs.

## Devpost copy

### Project name

Aircade

### One-line description

We turned AirPods into Wii-style motion controllers—and made the sensor pipeline and AI tennis rivals' shot decisions visible.

### Inspiration

We wanted the immediate, physical fun of Wii Sports using hardware already in our pockets. An AirPod contains motion sensors. The challenge was turning those readings into something a new player could hold, swing, and understand.

### What it does

Aircade is a native Mac arcade controlled with an AirPod. In our tennis demo, the player swings a real earbud while the game moves their character around the court. A handoff card identifies the controller, explains the grip, and provides a recenter action. Results lead directly into another rally.

The **How it works** screen exposes the path from Core Motion readings through grip calibration to racket orientation. It includes live input, a real recorded input example with an explicitly reconstructed racket mapping, and capture/replay for new traces. Recorded playback is separate from gameplay.

**Astra · OpenAI API** chooses among five legal tennis shots. A shared tactical interface gives Astra and Jev the same state fields, actions, and objective. The game keeps movement and contact local while the model decides asynchronously. An expandable panel shows the input, latest response, actually applied shot, request time, and cached reuse.

We also built a separate computer-use experiment in which Codex operates visible rival controls. Its slower incoming play and buffered swings are explicitly labelled.

### How we built it

Swift, SwiftUI, and SceneKit drive the native experience. We consume the active AirPod's fused Core Motion orientation and rotation readings, use a neutral reference and grip calibration to map the controller, and check actual racket-ball contact. A Node station keeps API credentials off the client. Astra uses the OpenAI Responses API with a constrained legal-shot output.

For evaluation, we freeze twenty synthetic game situations and repeat each twice per provider under a shared deadline and request cadence. The report retains every planned attempt, failures, model provenance, and available usage. It compares decision validity and delivery time; it does not rank independent tennis ability.

In our corrected recorded run, Astra and Jev each delivered 40 valid decisions from 40 submitted requests before the six-second deadline, with no failed attempts. Median request time was 1,836.5 ms for Astra and 322 ms for Jev. This small sample measures our configured tactical API paths; it does not establish why latency differed or guarantee future performance.

### Challenges and what we learned

Sensor data alone does not produce a usable controller: grip, freshness, feedback, and recovery all matter. AI decisions also arrive on a different schedule from a real-time rally. We separated asynchronous tactical choices from local physics and made the exact applied decision visible.

Codex helped implement and test the judging features and diagnose a flaw in our first comparison runner. Seven instant “rate-limit” failures came from our own scheduler waking slightly early. We corrected admission timing, distinguished local rejections from external provider failures, and added a regression that deliberately simulates early timer wakes.

### What's next

Measure first-hit time and recovery with unfamiliar players, capture more real sensor traces with their original calibration metadata, and extend controlled agent experiments with clearly matched inputs and timing.

### Built with

Swift · SwiftUI · SceneKit · Core Motion · Node.js · OpenAI Responses API · GPT-6 Astra · Codex · Jev

## Evidence and remaining physical checks

| Field | Status |
| --- | --- |
| Corrected comparison | `docs/evidence/DecisionComparison.json` and `.html`; scheduling `monotonic-admission-v2`; run `5c52f869-b34d-4d00-a30c-c3241444bc1d` |
| Completed/planned attempts | **80/80**; 40 submitted requests per provider |
| Astra valid before deadline / actual submitted | **40/40** |
| Jev valid before deadline / actual submitted | **40/40** |
| Astra request time among 40 valid responses | **Median 1,836.5 ms; range 1,324–4,014 ms** |
| Jev request time among 40 valid responses | **Median 322 ms; range 236–1,257 ms** |
| Timeout, provider-rate-limit, local-admission, and other failures | **0 in the corrected recorded run** |
| Automated verification | Swift: **124 tests, 2 gated live tests skipped, 0 failures**. Offline station suite: **25/25 passed**. Signed release compilation passed. These checks do not measure physical controller usability. |
| Signed build / station revision used in physical demo | `build/Aircade.app`; station port 8794. See `JUDGING-RELEASE-CHECKS.md`; physical verification pending. |
| Unfamiliar-player first-hit and replay observations | **Pending physical measurement** |
| Three consecutive physical rehearsals | **Pending physical completion** |
| Hand-and-screen demo video | **Existing 54-second unlisted video is embedded; representative visual playback verified.** Latest-build API/sensor coverage, audio, and an offline backup remain unverified; see [audit](SUBMISSION-AUDIT.md). |
| Genuine physical rally with an applied Astra decision | **Pending physical verification** |

The recorded comparison used build identifier `b500cff+uncommitted` and synthetic tactical states, not physical sensor trials. Endpoint serialization differs. The medians use valid completed responses; the all-attempt denominator is shown alongside them.

The earlier `.local/paired-decisions-final` report is superseded diagnostic evidence for the scheduler bug, retained locally. Do not copy its provider-success rates into the submission. The existing `../devpost-story.md` also contains claims about sub-30-ms latency, crowd counts, and assistant attribution that require independent evidence; this draft does not carry them forward.
