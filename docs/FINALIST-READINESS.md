# Aircade: demo and finalist readiness

Assessment as of September 19, 2026. Initial Devpost submission is confirmed by the team. Finalist selection cannot be guaranteed; the team should optimize what judges can actually experience.

## Positioning

**Your everyday AirPods and iPhone become a walk-up motion arcade. Your hacker badge keeps your score and your next rivalry.**

Lead with the surprising physical interaction, let someone play, then show the engineering behind its feel. Badge scanning and ranks complete the experience; they are not the main technical novelty. Avoid describing Aircade as merely a Wii clone. Do not claim a first-ever invention without research, two independent streams from one AirPods pair, or a trained opponent that does not exist in this build.

## What exists

| Area | Current evidence | Remaining acceptance |
| --- | --- | --- |
| Motion controls | AirPod/iPhone adapters, persistent sessions, simple calibration, stale-input recovery; earlier physical success reported by the user | Updated companion installation and consecutive physical rounds at the demo station |
| Games | Neon Rush, finite-racket Tennis and AirPod+iPhone Saber Duel; complete native scripted rounds | Judge-friendly physical feel and fast device handoff |
| Badge | Camera QR + local optional name OCR, explicit nickname/visibility confirmation, returning identity | Actual event badge, lighting, camera selection and hand-tracking handoff |
| Competition | Persistent per-game bests, rank/next target, results climb card, native and browser boards, offline queue | Two real players producing a real rank change |
| Haptics | Phone feedback protocol and distinct cues in software | Latest companion and perceived cues; external motors are not integrated |
| Opponent | Deterministic automatic Tennis returner | No trained, model-hosted or adaptive boss is claimed |

169 Swift tests pass, including generated QR images through the production Vision reader. A real MongoDB end-to-end test covers native sign-in, offline restart/retry, scores and separate boards. These checks establish software behavior, not motion latency or physical usability.

## Priorities before more features

1. **Close the physical acceptance gap.** Install the current signed iPhone companion, scan an actual badge, play a complete round, see the score, switch players, rescan, then play AirPod+iPhone Duel. Target ten consecutive rounds without a restart or unexplained pause. Record failures and fix the most frequent one first.
2. **Make first play immediate.** Test with people who did not build it. Target a first successful hit within 30 seconds after handing over an already-connected controller. Mark the active earbud and its grip orientation physically. Keep the working simple calibration.
3. **Make contact distinctive.** Integrate the existing haptic hardware only if it can reliably distinguish hit, clash and damage without blocking the motion/render loop. Let a tester identify the cues. A consistent grip and satisfying feel are more valuable than another unfinished game.
4. **Choose one additional showpiece only after the above.** An opponent that detects weak returns and changes its next tactic could differentiate Tennis. Show the measured behavior change in a short match. If using a hosted model, request bounded tactics between rallies, validate the response, and keep local physics and a deterministic fallback. Do not put a network model in the frame loop or call difficulty scaling model training.
5. **Gather real evidence and rehearse.** Invite 5–10 attendees, record time to first hit and successful round completion, and observe whether they voluntarily replay. Populate the board only with real opted-in scores. Capture a short honest backup video and practice the same demo three times without intervention.

## Four-minute demo rehearsal

- 0:00–0:20: Hold up the AirPod. Explain the hook in one sentence and move the on-screen racket with it.
- 0:20–0:45: Scan a consenting participant's badge, confirm nickname, show their score target.
- 0:45–1:50: Give them the calibrated controller for a complete 60-second round. Narrate minimally.
- 1:50–2:15: Show the recorded score, rank and next rival. Celebrate a climb only if it really happened.
- 2:15–3:00: Demonstrate the phone as the second independent controller and a brief Duel exchange.
- 3:00–3:40: Explain calibration, orientation versus position, swept collision detection, independent device timing and recovery from missing packets. Show one concrete engineering result instead of listing libraries.
- 3:40–4:00: End on the replay challenge. Leave questions and a working controller in the judge's hands.

If badge scanning takes too long, use Guest and keep playing; do not spend the demo debugging. Have a prepared real profile available, but explain it is already signed in. A prerecorded backup should be clearly identified as recorded.

## Judging and sponsor fit

The published main criteria are WOW factor, technical ability, originality and design, with 12 finalist awards. Playful projects are explicitly welcome. My recommendation is to optimize the main finalist demo first. [Official event page](https://hackthenorth2026.devpost.com/)

The first round has five minutes; the second has four minutes of demonstration plus a minute of questions. Final edits close at 8 a.m. EDT Sunday, September 20. [Official rules](https://hackthenorth2026.devpost.com/rules)

Sponsor choices must match the team's submitted selections. Conditional options: Baseten needs creative actual use of its platform; OpenAI requires an API-powered experience as well as meaningful Codex development; Sentry asks for at least two products beyond error monitoring and evidence that they improved the project. None is established merely by the current arcade's existence. The badge prize may be worth clarifying with its sponsor if selected, but QR sign-in alone should not be presented as deep badge hardware work. [Official prize requirements](https://hackthenorth2026.devpost.com/)

## Honest conclusion

Aircade now has a coherent, technically substantial arcade loop. Its main risks are perceived derivative gameplay, AirPod lag, physical handoff friction and unverified new-build hardware behavior. Reliable hands-on surprise and demonstrable depth are the next milestones. More channels or sponsor logos will not substitute for them.
