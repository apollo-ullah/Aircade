# Final judging checklist — September 20, 2026

This is the release checklist for the submitted Aircade build. The code is frozen unless a rehearsal exposes a repeatable demo-blocking failure.

## Completed automatically

- [x] Consolidated the judging implementation with the public README history.
- [x] Native release build completed and the app bundle was ad-hoc signed.
- [x] Native test suite passed: 125 tests executed, 2 opt-in live tests skipped, 0 failures.
- [x] Full station suite passed: 25/25 tests, including isolated MongoDB and Baseten integration checks. The offline subset also passed 23/23.
- [x] Both OpenAI and AI Gateway credentials are present in the ignored local environment without being printed.
- [x] The configured station is responding on port 8794 with the `tactical-v1` contract.
- [x] Devpost is publicly accessible while logged out.
- [x] Devpost displays the rewritten story, OpenAI/Astra/Codex explanation, video, seven gallery entries, and public GitHub link.
- [x] Devpost describes the Responses API opponent and Codex computer-use experiment as separate systems.
- [x] Public copy scopes the Astra/Jev comparison to decision delivery rather than tennis skill.
- [x] Final app, source, and 3:2 gallery archives exist locally with SHA-256 checksums in `build/judging-manifest.json`.
- [x] Repository credential scan found no configured secret values in changed or new source files before commit.
- [x] Unfinished Wii-shell work remains isolated and was not merged into the judging build.

## Human checks before the judge arrives

- [ ] Charge the Mac, AirPods, and iPhone; keep chargers connected or within reach.
- [ ] Turn off notifications, sleep, automatic updates, and other visible interruptions.
- [ ] Confirm venue Wi-Fi works and the OpenAI account has available API access.
- [ ] Start the app from a cold terminal using `./scripts/run.sh` and confirm the correct window appears. The station health check is already passing.
- [ ] Confirm the intended AirPod reconnects, its left/right label is correct, and the physical grip matches the on-screen illustration.
- [ ] Recenter immediately before judging.
- [ ] Confirm music and effects use the intended speaker rather than interfering with AirPod motion.
- [ ] Complete three consecutive end-to-end rehearsals: controller handoff, first interaction, gameplay, AI decision evidence, results, and restart.
- [ ] Give the controller to someone who did not build Aircade and measure whether their first successful interaction happens within ten seconds.
- [ ] Confirm the prerecorded video opens locally with usable audio, without relying on Wi-Fi.
- [ ] Keep the app on the main menu and the backup video one click away before the judge arrives.

## Claims to keep precise

- [ ] Say that Astra and Jev both produced 40/40 valid decisions in the corrected recorded run; do not call it a ranking of tennis ability.
- [ ] Do not attribute Jev's latency result to token efficiency without separate evidence.
- [ ] Identify demo/simulated input whenever those modes are shown.
- [ ] Describe the recorded final-build AirPod trace as nearly stationary sensor evidence, not a verified handheld rally.
- [ ] Do not quote unverified sub-30-ms end-to-end latency, unfamiliar-player results, or physical rehearsal counts.

## Demo order

1. “We turned an AirPod into a Wii remote.”
2. Hand over the marked controller and produce one successful interaction.
3. Show live AirPod input, grip mapping, and racket output.
4. Show Astra receiving game state and selecting one of five legal shots through the Responses API.
5. Show the difference between the latest model response and the shot actually applied on court.
6. Explain that Codex helped build and debug the project, then played through the visible computer-use interface.
7. Close with the corrected comparison and invite another turn.
