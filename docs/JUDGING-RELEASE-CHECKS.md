# Judging build — September 20, 2026

The implemented app is `build/Aircade.app` in this checkout. Start the configured station with `./scripts/start-station.sh`, then use `./scripts/run.sh` to build, prepare its local connection, and open it. This checkout uses port 8794. It does not replace the separate GitHub checkout or its station on 8787.

## Implemented

- Controller handoff instructions, active-earbud identification, readiness, and recenter access in the tennis lobby and pause screen. The grip drawing is an illustration of the expected hold.
- Replay keeps the controller and selected rival. Missing motion and simulation are explicitly labelled.
- Astra through the OpenAI Responses API, sharing a five-shot tactical contract with Jev. Model decisions determine returns while native code supplies movement and contact.
- Actual selected/applied candidate and observation/decision identities, request time, observation-to-shot time, and fresh/cached state. Evidence can be inspected from the lobby, pause screen, or results.
- A sensor explanation with live fused Core Motion readings, quaternion/reference/grip details, an eighteen-second capture, and isolated playback. The bundled real CSV sample has a visibly reconstructed racket mapping because the original mapping was not recorded.
- A complete recorded paired comparison and a verified Codex debugging card, both bundled with the app.
- Cancellation and stale-response protection across pause, inspector, restart, provider change, and leaving a game.
- Model warmup independent of controller readiness in the lobby. Missing input cannot start play; tracking loss during a match still cancels requests and requires explicit resume. Closing controller setup prepares the lobby model again.
- A repaired comparison scheduler that rechecks actual monotonic eligibility and records whether transport started.
- Nonblocking station configuration loading. Computer-use testing found a stalled Documents-folder read inside a view; configuration now loads in the background with a two-second limit and is staged locally in Application Support by the launcher.

## Verified

| Check | Result and scope |
| --- | --- |
| Native test suite | 127 tests, 2 opt-in live tests skipped, 0 failures after keeping leaderboard navigation inside the native app. |
| Station suite | 25/25 passed, including isolated MongoDB integration, cold startup, provider validation, and fractional/early-wake scheduling. The offline subset also passed 23/23. |
| Actual API contact check | One live request each for Baseten, Astra, and Jev; real native collision code produced a player return followed by the exact API-selected opponent return. Controller input was accelerated scripted motion, explicitly unranked. |
| Corrected paired live run | 80/80 requests completed with legal decisions before the shared six-second deadline. Astra: 40/40, median 1,836.5 ms. Jev: 40/40, median 322 ms. Twenty fixed synthetic states repeated twice per provider; this does not measure tennis ability. |
| Final-build sensor capture | 552 fresh Left AirPod samples over 17.985 seconds, all marked calibrated and non-simulated, with the original reference/grip/racket output. Recorded replay was exercised through the UI. This nearly stationary trace contains no contact events; it does not verify a handheld swing. |
| Native computer use | Opened sensor explanation, switched to the real recorded sample, played it, expanded technical details, and returned to the menu. Retested Tennis after the configuration freeze fix; selected Astra, inspected setup, ran simulated gameplay to results, replayed, and paused. |
| Layout preview | Seven isolated native screenshots generated successfully from the final signed build. Simulation and absence of hardware/API evidence are labelled. |
| Browser report | Visually checked; Astra filter shows 40 attempts and failure filter shows none in the corrected run. All 80 attempts and detailed evidence remain available. |
| Distribution preparation | Ad-hoc signed native build; signature verified. Three configured credential values were checked against 779 candidate source files with zero matches. Ignored `.env`, `.local`, `.git`, dependencies and build products are excluded from the source package. This is a targeted check, not a comprehensive historical repository audit. |

The final signed release also compiles the presentation changes that expose evidence while paused/after results and prepare the model when controller setup closes. Live API semantics and benchmark prompts did not change after the recorded comparison.

## Evidence locations

- `docs/evidence/DecisionComparison.json` and `.html`: corrected complete recorded run.
- `docs/evidence/CodexDevelopmentStory.html`: the actual scheduler defect, fix and verification.
- `.local/paired-decisions-final/`: preserved superseded diagnostic run, including the seven local admission failures and two timeouts. Its original submitted counts are not used for the corrected comparison.
- `docs/evidence/RecordedSensorCapture.json`: final-build, nearly stationary hardware capture with its actual mapping.
- `docs/evidence/NativeTacticalContact.json` (also retained at `.local/evidence/native-tactical-contact-live.json`): actual API decisions through native collisions; explicitly no physical-hardware verification.
- `.local/judging-swift-tests-final.log`, `.local/judging-release-build.log`: local validation logs.
- `build/judging-preview-final/`: final native layout screenshots and result JSON.
- `docs/JUDGING-SUBMISSION-DRAFT.md`, `docs/SUBMISSION-AUDIT.md`: demo script and prepared replacement submission text.

## Physical work still needed

The AirPod initially supplied no motion, then began sending live Left-earbud readings. The final-build capture and replay passed; no physical hold condition or swing was independently observed. No unfamiliar-player first-hit time, physical calibration quality, or three consecutive physical rehearsals is claimed. Use `docs/JUDGING-UX-TEST-SHEET.md` to measure those with the final app. A first hit within ten seconds remains a target, not a verified result.

The Devpost entry is submitted and public. Its rewritten story explains the OpenAI API, Astra, Codex development, the separate computer-use experiment, and the corrected comparison. It includes the public GitHub link and seven gallery entries. The existing 54-second recording does not establish coverage of the new API and sensor screens. Finalist selection cannot be guaranteed by the pitch or this build.

Use `docs/FINAL-JUDGING-CHECKLIST.md` for the remaining human rehearsal, device, audio, and claim checks.
