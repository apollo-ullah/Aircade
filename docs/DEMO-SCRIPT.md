# Aircade judging rehearsal

This is a rehearsal script, not a record of completed physical acceptance. Fill the final evidence fields after checking the actual signed build. Finalist selection cannot be guaranteed.

The concrete final judging sequence, current verified API metrics, and Devpost copy are in [JUDGING-SUBMISSION-DRAFT.md](JUDGING-SUBMISSION-DRAFT.md). The corrected recorded comparison is `docs/evidence/DecisionComparison.html`: both providers produced 40/40 valid decisions before the six-second deadline; median request times were 1,836.5 ms for Astra and 322 ms for Jev. This is tactical API decision delivery, not independent tennis skill.

## Before the judge arrives

- Launch the intended station and signed app. Verify the selected rival has a genuine validated model plan; do not substitute a different provider under its name.
- Connect the controller, identify the active L/R earbud, use the saved calibrated grip, and confirm fresh input. Mark the grip physically. The in-app grip drawing is labelled an illustration; it is not a photograph of the team's actual grip.
- Start in Guest. Keep the controller handed to the judge already connected and calibrated; cold setup is a separate test.
- Put the real prerecorded backup within one action. Confirm it plays and shows the hand, game scene, genuine hit, API decision, and results. Identify it as recorded when used.
- Keep the test sheet and evidence card available; do not navigate source files or diagnostic logs during the main demo.

## Main competition: four minutes

| Time | Action | Suggested words |
| --- | --- | --- |
| 0:00–0:20 | Hold up the active AirPod. Move the racket and make a real hit. | “This AirPod is our tennis racket.” |
| 0:20–1:10 | Hand it to the judge. Use the existing grip and recenter if necessary. | “Keep it fixed in your fingers. Swing when the ball reaches your racket; your player runs automatically.” |
| 1:10–1:40 | Open **How it works**, which pauses the match. Tilt the actual controller and show input → calibration → racket. Close and explicitly Resume. | “Core Motion gives us orientation and motion readings. Our saved grip and neutral reference turn those readings into racket orientation. A hit still needs real geometric contact.” |
| 1:40–2:25 | Show the selected API rival and expand **AI shot decisions**. Wait for an actual applied shot, not merely a returned API response. | “The model receives measured game state and chooses one of five legal shots. The game supplies movement and contact. Here is the input, its latest selection, and the decision that actually reached the court.” |
| 2:25–3:00 | Show one verified development evidence card. | State the user-visible failure, the evidence, the specific change, and the check that passed. Name Codex's contribution only when supported by the actual task. |
| 3:00–3:30 | Show results and **Replay rally**. | “Same controller, same rival—ready for another round.” |
| 3:30–4:00 | Buffer for the physical handoff or a question. | End with the controller available to play. |

If the round ends before the inspector segment, open it from the lobby. A paused round remains the same round; do not navigate to the separate training lab to explain the sensors.

## OpenAI sponsor variation

Keep the same physical opening. Allocate roughly one minute to the actual **Astra · OpenAI API** input, selected candidate, applied candidate, request/decision IDs, and request timing. If a recorded Astra/Jev comparison exists, show its run date, settings, sample size, all-attempt denominator, failures, and conditions: same state, same legal shots, same deadline. Say which measured property differed, such as valid responses within the deadline; do not describe it as a tennis-skill ranking or a causal token-efficiency result.

Spend about 30 seconds on a verified Codex development story. The separate **Codex · computer use** mode watches the screen, drags the rival, and presses swing. It has slower play and buffered swings and is unranked. It is a separate experiment from the tactical API rival and is not the API evidence for this build.

## Twenty-second sensor answer

“We use Apple's Core Motion readings from the active earbud. Calibration maps the grip to a racket orientation relative to a neutral pose. We then apply that pose to the game and test the actual racket/ball collision. Acceleration does not give us absolute 3D hand position. If the camera is enabled, its hand-position contribution is shown separately.”

Use **Live** for real current sensor readings. Use **Recorded trace** for a captured trace; keep that label visible. The bundled eighteen-second example contains real AirPod input but a **reconstructed racket mapping**, because its original grip, smoothing, and game output were not saved. Say this explicitly. A new in-app capture preserves those values. Sample age is time since receipt by the app, not measured Bluetooth or motion-to-photon latency; the imported example shows receipt age as unavailable. The displayed update rate describes consumed updates, not every hardware sample.

## Failure handling

- If the controller needs recentering, use the visible action once and resume only after fresh input. Repeated failure means use the labelled backup; do not debug for the rest of the judging slot.
- If the API becomes unavailable, show the actual state. Cached means a previous genuine model decision is being reused, not that a new call succeeded.
- If using a recorded comparison or backup, say “recorded” immediately. Do not replace failed attempts with invented successes.
- Do not display credentials, badge identities, or personal logs in the recording.

## Final evidence to attach

- Signed build revision and station startup command/configuration reference.
- Five unfamiliar-player observations, including unsuccessful attempts and coaching.
- Three consecutive four-minute rehearsals; at least one starts with a fresh app/station launch.
- One physical Astra round, results, and replay with an actual applied API decision.
- Sensor live/replay check and pause/close/resume lifecycle check.
- One genuine Codex task, its specific change, and the corresponding test or before/after artifact.
- A playable prerecorded backup and an intact full rehearsal.
- Final submission links checked from a fresh browser context.
