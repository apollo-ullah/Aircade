**Aircade: implementation plan for judging**

Prepared September 20, 2026, approximately 1:40 a.m. EDT. Target: submission before 8 a.m.; feature freeze at 5:30 a.m. This is a plan, not a report of completed changes or passing tests. Current audited checkout: `b500cff`.

**Release outcome.** A new player can make a real hit quickly, play a reliable round against an OpenAI API opponent, see how the AirPod and opponent work, reach results, and replay. A small controlled Astra/Jev comparison and one attributable Codex development example support the demo. The supplied rubric rewards wow, originality, actual user experience, and technical work; it does not reward a business case or cosmetic polish by itself. No pitch can guarantee a finalist place.

**Decisions to keep scope under control**

- Add Astra through the OpenAI Responses API as a tactical opponent using the same state and legal actions as Jev. Its chosen shot must visibly affect actual play. This is the substantive API feature; do not add an unrelated chatbot or narration call to check a sponsor box.
- Compare Astra and Jev under that shared tactical contract. Call it a paired decision comparison, not a frontier gameplay benchmark. It measures decision validity and delivery latency, not independent movement or reflexes.
- Keep desktop computer use as a separately labelled experiment. Do not restore the entire deleted screen-control stack before the deadline.
- Add a read-only “How it works” view using existing sensor telemetry, with Live and Recorded sample modes.
- Test physical usability early. Keep the working calibration algorithm, game rules, and visual style unless observed failures justify a targeted change.
- Defer the proposed multi-speed reaction challenge, new games, extra providers, new leaderboard features, and broad refactoring.

**Current findings that affect implementation**

| Finding | Consequence |
| --- | --- |
| [Station server](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/server/server.mjs:2>) imports `../tools/astra-arena/jev.mjs`; commit `1d1a833` deleted that directory. | A fresh station process cannot resolve the import. Repair this before adding another provider. A previously running process does not prove the release can restart. |
| [Tactical opponent](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/BasetenTennisOpponent.swift:76>) already preserves a model-selected shot and refreshes asynchronously. | Extend this path for Astra; retain responsive native simulation. |
| [Codex practice timing](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/TennisGame.swift:228>) advances incoming play at 0.45 simulation speed, with early swings buffered by the match. | It is not equivalent to the normal tactical opponents and must not appear in the same performance ranking. |
| [Diagnostics](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/AircadeApp.swift:339>) already show source, consumed update rate, sample age, orientation, angular velocity, acceleration, and a speed graph. | Reuse the data rather than building another sensor system. |
| [Opening the lab](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/MotionModel.swift:623>) leaves the active games. | The new explanation view must pause/preserve the match instead of navigating through this route. |
| [Current CSV logging](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/MotionModel.swift:599>) lacks a complete mapping/reference/output snapshot. | Old readings alone cannot reconstruct the exact historic racket orientation. Record a fresh short trace with mapping metadata and output. |
| Historical Astra/Jev reports describe different interfaces and deleted code. | Use them as labelled historical evidence only, not acceptance of the current build or a fair cross-model comparison. |

**Work package 0 — repair the release baseline (first; 20–30 minutes)**

Owner: API/integration developer. Other owners can start observing physical play and preparing sensor UI in parallel.

1. Recover the tactical functions from `1d1a833^:tools/astra-arena/jev.mjs` into a maintained `server/providers/jev.mjs`. Remove dependencies on the deleted probe modules; preserve the actual Jev model/provider identity and response interpretation.
2. Update the import and keep existing Jev/Baseten behavior. Do not revert the later UI work or resurrect all removed experiment files.
3. Verify a fresh station launch against the intended local database, then health and a mocked provider request. Exercise the actual entry point, not just syntax checking. Use isolated test ports/configuration for automated checks.
4. Establish the exact signed app build and a known working controller configuration. Record its revision and startup steps. Keep the last working app bundle available while changes are integrated.

Exit: fresh server process starts; station health works; mock provider path and native build work. The cold-start failure has a regression check.

**Work package 1 — first-hit and handoff experience (45–75 minutes, then physical testing)**

Owner: gameplay/UX developer with a teammate recruiting unfamiliar testers.

Touchpoints: [ControllerSelectionPanel.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/ControllerSelectionPanel.swift>), [SimpleCalibrationGuide.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/SimpleCalibrationGuide.swift>), [TennisView.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/TennisView.swift>), [TennisGame.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/TennisGame.swift>).

1. Fix the demo configuration: one identified active earbud, known grip, working audio output, and the established calibration. Mark the grip physically and add a small handoff card with an actual photograph of that grip, the active L/R earbud, and “Keep it fixed in your fingers.” Keep sign-in optional and start in Guest.
2. Make readiness truthful: correct source, fresh motion, usable saved grip, and prepared API rival. Bluetooth connection alone must not mean “ready.” Distinguish controller problems from provider problems.
3. Give a single instruction: “Hold it like this; swing when the ball reaches your racket.” Put an obvious visual contact cue near the racket if testing shows timing confusion. Use the existing real collision path.
4. Measure first-hit time from handoff, including recenter/countdown. The target assumes the station is already connected and calibrated; record cold setup separately. Do not start the timer only after the player has figured out the controls.
5. Offer a visible handoff/recenter action and a clear Replay action. Preserve the selected provider and controller connection across results/replay. Require fresh input before resuming after loss.
6. If onboarding needs an easier serve, make it an explicitly labelled, unranked practice serve. Do not silently enlarge collision or fabricate successful hits.

Acceptance: at least 4/5 unfamiliar testers make a genuine hit within 10 seconds and all within 20 seconds; all complete a round without developer rescue. At least 4/5 find Replay within 10 seconds. These are release targets, not current results. Fix any blocker and confusion repeated by two testers, then retest the changed path.

**Work package 2 — meaningful Astra API rival (90–150 minutes including package 0 and focused checks)**

Owner: API/integration developer. Use server-side credentials, the existing authenticated local station route, and the existing five legal shots. Never expose keys in the app, trace, or recording.

| Component | Implementation |
| --- | --- |
| Proposed `server/providers/contract.mjs` | Canonical state, shared objective, candidate IDs/values/order, normalized decision, provenance, and error types for Astra/Jev. Strip badge ID/name and unrelated profile data before either external call. |
| Proposed `server/providers/astra.mjs` | Responses API with exact `gpt-6-astra`, low reasoning, strict structured output selecting one legal `candidateID`. Return model/response identity, timings, usage when available. Explicitly handle refusal, incomplete response, invalid/missing output, timeout, and rate limit. |
| [server.mjs](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/server/server.mjs:247>) | Permit `astra`, route to adapter, preserve authentication/validation, and return explicit provider failure. No silent substitution with Baseten, Jev, or a local bot. |
| [BasetenTennisOpponent.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/BasetenTennisOpponent.swift>) | Reuse the existing adapter despite its name. Add observation/decision IDs, plan age and current state. Validate candidate identity and preserve its exact target, pace, delay, and stroke. Avoid a broad rename. |
| [TennisGame.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/TennisGame.swift>) | Gate initial start on a real validated plan. Invalidate in-flight responses on provider change, new run, pause/end. Record which decision was actually consumed for each shot, separately from “latest response.” |
| [TennisView.swift](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/Sources/Aircade/TennisView.swift>) | Add “Astra · OpenAI API.” Present “Model chooses the shot; game handles movement and contact.” Expose a compact expandable panel: input summary, chosen target, actual applied shot, request time, and Fresh/Cached/Waiting/Unavailable state. |

Ordinary play can retain the last valid model-selected plan during inference, with a visible cached label and age. Cancelled/late work cannot install into another run. A cached shot is not a new decision and cannot count as a successful response in the comparison. Keep the normal-speed gameplay path; do not introduce model-specific slowing to flatter Astra.

Use a small explicit live-call/request budget and bounded timeouts. Validate request configuration with one opt-in call before collecting a batch; do not copy the tiny output-token cap from a different model and assume it permits reasoning plus structured output. No billable calls are part of preparing this plan.

Acceptance: mocked request/response/error checks; one live Astra response; the exact chosen target survives into a real rendered shot; one full physical AirPod-versus-Astra round, results, and rematch. A provider failure is visible and does not freeze the controller or quietly launch another model.

**Work package 3 — small fair comparison (45–60 minutes after the shared contract works)**

Owner: API/evaluation developer. Build a local runner and a saved result card, not a new dashboard.

1. Freeze 20 representative state fixtures before measuring; run two repeats per fixture per provider (40 attempts/provider, 80 total). Alternate which provider goes first. Keep any configuration smoke requests separate. Run the same fixture set even when a provider fails.
2. Supply identical state fields, history, five legal candidates, candidate order and tactical objective. Do not give one provider hidden extra history. Endpoint-specific serialization can differ; record that it does.
3. Use the same six-second request deadline and at least 2.2 seconds between request starts per provider, subject to actual rate limits. Keep one request in flight per provider. Honour Retry-After, record the failure, and schedule a fresh attempt; never erase the failed attempt.
4. Record every outcome: valid completion, invalid/refused/incomplete, timeout, rate limit, network failure, cancelled. Record model/settings, fixture ID, repeat, timestamps, returned candidate, and available usage. Missing usage is unknown, not zero.
5. Report valid decisions within deadline out of all attempts, median completion latency with its sample count, observed range, and all failure counts. Small-sample tail estimates are unstable; do not promote them to production performance guarantees.
6. Keep API round-trip time distinct from native observation-to-applied-shot time. The latter includes scheduling and cached-plan reuse; log it separately in the live demo.
7. Show “same state, same legal shots, same deadline” on the result card. Label results as recorded, with build/model/settings and sample size. A live request should visibly affect an actual shot elsewhere in the demo.

This comparison can establish that one configured provider delivered more valid decisions before the deadline or had lower observed request latency. It does not establish superior tennis ability: native code supplies movement/contact for both tactical rivals. Do not use tactical return percentage as model skill. Do not claim token efficiency caused a difference.

The existing desktop Codex mode belongs on a separate experiment card: screenshot/UI input, manual rival positioning/swing, slower incoming simulation, buffered swings, unranked. Historical API computer-use runs must also remain separately labelled. A future full control benchmark would give both models the same measured state and movement/swing contract with identical physics; recovering that stack is outside this release.

**Work package 4 — show the sensor-to-racket pipeline (60–90 minutes live; up to 45–60 more for recorded replay)**

Owner: sensor/UI developer. Build an in-app read-only “How it works” sheet accessible in one action from Tennis and the home screen.

The sheet pauses the current match and suspends new model work. Closing it returns to the same match/context; the user explicitly resumes after fresh-input checks. It must not call the current lab navigation that abandons the run.

Present three connected stages:

`Core Motion input → grip calibration and recentering → racket orientation and real contact`

- Input: source earbud, quaternion (expandable), labelled orientation axes, angular velocity in rad/s, user acceleration in g, consumed update rate and sample age. Say “Core Motion readings,” not raw hardware IMU. These are processed readings, and the latest-input buffer does not preserve every hardware sample. Sample age is time since app receipt, not measured Bluetooth or motion-to-photon latency.
- Mapping: show how the saved grip and neutral reference make the racket follow a deliberate tilt. State that orientation is relative to the reference. If the camera is active, label its separate 2D hand-position contribution.
- Output: moving racket preview, angular speed, and actual contact event. A fast swing alone is not a hit; scoring requires the game's collision and contact rules. Do not imply absolute 3D position comes from integrating AirPod acceleration.

Live mode uses an immutable telemetry snapshot and bounded history, with UI updates around 10–15 Hz so graphs do not burden input/rendering. It reads existing data; it does not create a second motion manager.

Recorded sample mode uses a fresh 15–20-second real trace: still, left/right tilt, deliberate swing, and a real contact if captured. Include capture date/build, source and user-reported handheld condition, input and receipt timestamps, calibration basis, neutral reference, smoothing setting, resulting racket orientation, and timestamped real contact events. Some of these are absent from current CSVs and must be captured at the production mapping/contact points.

Playback is a separate display-only model, never a call into live `MotionModel.receive()`. It cannot change calibration, readiness, real scores, leaderboard state, or hardware-test evidence. Prominently show “Recorded sensor sample” throughout, including when paused. Older reprocessed traces must say they are reprocessed; synthetic fixtures must say simulated.

Acceptance: live physical tilt matches the preview; playback follows the captured input/output; viewing or replaying data cannot score or overwrite settings; open/close returns safely to the game. If replay instrumentation runs over its time box, ship the live sheet plus a labelled recording of the real diagnostics, rather than inventing a trace.

**Work package 5 — physical UX, integration, and recovery gates**

Owner: demo/test lead with the team. Start the first three unfamiliar-player observations while other changes are being built; test at least five people overall. Use the accompanying [test sheet](</Users/adyan/Documents/ChatGPT/Hack The North 2026/Aircade/docs/JUDGING-UX-TEST-SHEET.md>).

Test the actual judging configuration: display size, distance, noise, speakers, active earbud, network, signed app and current station. Count coaching and resets as failures of the flow rather than deleting those trials. Test wrist/handedness differences without changing the calibration algorithm for a single unusual grip.

Meaningful implementation checks:

- Shared provider payload equality, candidate preservation, no silent fallback, stale response after pause/rematch/provider switch, and recorded benchmark outcomes.
- Sensor replay isolation, no score/calibration mutation, true source labels, and match-preserving inspector lifecycle.
- Existing collision, controller-session, recovery, menu and score-eligibility checks where touched; run the full Swift and Node suites once after integration, then signed release build. Repeat broadly only if later changes justify it.
- Visual inspection at the actual demo window size, including composite SwiftUI and SceneKit content; a UI-only bitmap may omit the scene.

Physical release gates:

- At least 4/5 first hits within 10 seconds; all within 20 seconds; all five complete a round without developer rescue.
- At least 4/5 independently find Replay within 10 seconds and correctly explain what the model sees/controls after the AI panel.
- Controller interruption pauses/recovers without phantom hits; source mismatch does not reuse the wrong grip. Network loss keeps controller/UI responsive and shows truthful provider state.
- Back, pause, provider switch, and rematch during an API request cannot apply an old action to the next run.
- Three consecutive complete rehearsals under four minutes: handoff → genuine hit → API/sensor explanation → results → replay. No unexplained pauses, crashes, hidden provider substitution, or manual restart.
- At least one rehearsal starts with a freshly launched app and station. Preconnected/precalibrated judge handoff is a separate, explicitly stated setup condition.

**Work package 6 — verified development story, recording, and submission**

Owner: demo/test lead. Prepare these in parallel, then update with final evidence.

Use the story structure: visible failure → evidence → Codex's specific contribution → fix → verification. A code diff or author name alone does not establish which assistant did the work.

Candidate A: the historical screenshot rail/court mismatch and 1/10 to 5/10 return result. Recover the matching Codex task and original trace before attributing the diagnosis. Two changes were made (mapping and instructions), so do not claim a controlled causal result. It is historical evidence, not a current-build metric.

Candidate B: this review discovered the deleted Jev module still imported by the station. If the team implements and verifies the repair with Codex, capture the actual task, small diff, fresh-start failure and passing regression. Until repaired, describe only the diagnosis.

The audio-stall and packet-gap fixes are useful team engineering stories, but relevant commits explicitly credit Cursor. Do not relabel them as Codex work without separate supporting evidence.

Prepare one evidence card, not a live tour of logs or source. Record a 45–60-second backup from the final working build showing the hand/controller and screen together, a genuine hit, API provenance/actual shot, and results. Label it prerecorded. Keep an intact full rehearsal too. Verify that the captured file plays and includes SceneKit content and usable audio; do not assume a recorder captured the rendered court.

Main-competition four-minute flow: 0:00–0:20 AirPod reveal and hit; 0:20–1:10 judge plays; 1:10–1:40 live sensor explanation; 1:40–2:25 visible API-selected shot; 2:25–3:00 one engineering story; 3:00–3:30 results/replay; leave 30 seconds of buffer.

OpenAI flow: same physical opening; use roughly one minute for actual API input/output/applied action and the measured comparison, and 30 seconds for the verified Codex story. Only show computer use if it adds evidence within the time limit. State the difference between tactical API play and the screen-control experiment.

Suggested opening: “This AirPod is our tennis racket. We built the motion controls and game, then added AI opponents. You can see both the sensor readings moving your racket and the model decisions driving the other player's shots.” Adapt it to the behavior actually verified.

Finish the Devpost source/build links, selected sponsor information, team details, API/Codex description, limitations, and video by 7 a.m.; verify links from a fresh browser context. Ensure the public description reflects the final build, not removed experiment features. Official submission and prize rules remain authoritative.

**Schedule and cut rules**

These are planning estimates, assuming existing accounts/devices work and multiple teammates can own independent lanes. With fewer people, cut optional comparison presentation and replay polish first; do not compress physical acceptance into the last minutes.

| Time EDT | API/integration lane | Controller/sensor lane | Demo/testing lane |
| --- | --- | --- | --- |
| Now–2:15 | Fix import; prove fresh station startup | Observe first-hit failures; mark grip; sketch existing-data sheet | Recruit testers; record baseline observations; locate Codex attribution |
| 2:15–3:45 | Shared contract, Astra adapter, provenance, mocks | Targeted first-hit fixes; live sensor sheet; fresh trace capture | Test baseline/fixed flow; prepare evidence/submission text |
| 3:45–4:30 | Live Astra round; paired comparison if ready | Replay isolation and inspector lifecycle checks | Unfamiliar-player retest; capture repeatable failures |
| 4:30–5:30 | Integrate and resolve correctness/regression failures | Fix observed UX blockers; inspect actual demo layout | Verify scorecard claims and demonstration timing |
| 5:30–6:15 | Feature freeze; release verification | Physical recovery check | Three consecutive complete rehearsals |
| 6:15–7:00 | Only necessary fixes, followed by affected checks | Support final recording | Record backup; finish and verify submission |
| 7:00–8:00 | Contingency only | Keep working setup stable | Recheck submission, evidence and equipment |

If the API rival is not ready by 4:30, prioritize one working genuine Astra path and its physical verification over the comparison report. Do not disguise failure with an unrelated API call. If credentials/model access block it, document that sponsor gap explicitly. If unfamiliar players cannot reliably hit, controller usability takes priority over graphs and comparison polish. After 5:30, fix only release blockers. Every changed demo path needs another rehearsal.

**Sources and claim limits**

The user-supplied photographed judging rubric is the source for the overall criteria. The [official event page](https://hackthenorth2026.devpost.com/) specifies the separate OpenAI API and Codex-development dimensions; the [official rules](https://hackthenorth2026.devpost.com/rules) govern demo duration and deadline. A working integration supports the prize requirements but does not guarantee eligibility decisions or placement.

[OpenAI's Astra model documentation](https://developers.openai.com/api/docs/models/gpt-6-astra) documents Responses/Structured Outputs support and low reasoning. Use [Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs) for the bounded response and exceptional cases. [Computer-use guidance](https://developers.openai.com/api/docs/guides/tools-computer-use) describes the separate screenshot/action loop. The proposed comparison protocol and engineering choices above are this plan's recommendations, not vendor benchmark claims.
