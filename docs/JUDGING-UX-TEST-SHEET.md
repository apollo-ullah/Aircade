**Aircade judging UX and rehearsal worksheet**

Blank worksheet. No tests have been performed or passed by creating this file. Use participant labels rather than names. Record the build and configuration so results apply to the submitted app.

Date/time: ______  App revision/build: ______  Station revision: ______

Controller/source/grip: ______  Camera on/off: ______  Display/window: ______

Provider/model: ______  Mode/speed/assistance: ______  Tester unfamiliar with build: yes/no

**Standard novice task.** Hand over the preconnected, calibrated AirPod with the same one-sentence instruction: “Hold it like this; swing when the ball reaches your racket.” Start timing at handoff, including any recenter/countdown. Ask the person to finish a round, replay, and explain the AI after viewing its panel. Do not coach silently; count each extra prompt. Stop the clock at the first real collision-confirmed hit, not a swing animation.

| Tester | First real hit (s) | Extra prompts | Round complete without rescue? | Pauses/resets | Replay found (s) | Correctly explains AI input/control? | Specific confusion |
| --- | --- | --- | --- | --- | --- | --- | --- |
| P1 | | | | | | | |
| P2 | | | | | | | |
| P3 | | | | | | | |
| P4 | | | | | | | |
| P5 | | | | | | | |

Targets: 4/5 hits within 10 seconds, all within 20; 5/5 complete without rescue; 4/5 find Replay within 10 seconds; 4/5 explain what the AI sees and controls. Report actual counts even if targets are missed. New-player tests after a change are stronger evidence of discoverability than repeating only with trained participants.

**Issue triage.** Blocker: crash, cannot play/finish, corrupt state, false attribution, or wrong-source calibration. Major: repeated confusion, extra calibration, hidden cached provider, or difficult recovery. Minor: cosmetic issue without task impact. Fix blockers and confusion repeated by at least two testers first.

| Issue | Observed evidence / tester IDs | Severity | Smallest proposed fix | Owner | Retest result |
| --- | --- | --- | --- | --- | --- |
| | | | | | |
| | | | | | |
| | | | | | |

**Recovery and evidence checks**

| Scenario | Expected result | Actual / pass / fail |
| --- | --- | --- |
| Fresh app + station launch | No stale module import; health and readiness visible; correct saved controller setup | |
| New player / recenter | Correct grip and source retained; genuine contact; no unintended menu activation | |
| Brief motion interruption | Safe recovery; no phantom connecting hit | |
| Sustained loss or source change | Clear pause/recovery action; no wrong-source grip reuse | |
| Open/close How it works during play | Match preserved; user resumes with fresh input; no lost score | |
| Recorded sensor playback | Always labelled; cannot score or alter saved calibration/readiness | |
| Missing key / provider timeout | Explicit API state; UI/controller responsive; no silent provider substitution | |
| Back/rematch/switch during pending request | Old decision cannot install into the new run/provider | |
| Fresh versus cached shot | UI reflects actual applied decision ID and plan age | |
| Recorded comparison results | Same fixtures/settings; all failures counted; no gameplay-skill claim | |
| Actual presentation window/display | Labels readable; scene visible; no clipped primary action | |
| Backup recording playback | Controller and scene visible; audio usable; prerecorded label; no credentials | |

**Consecutive demo rehearsals**

Use the final candidate build and exact judging flow. At least one begins with a fresh app/station launch. Each rehearsal includes handoff, real hit, API evidence, sensor view, results and replay. Track setup separately from the four-minute presentation. If a change affects the flow, repeat the affected verification and rebuild the consecutive rehearsal evidence.

| Run | Fresh launch? | Presentation duration | First-hit time | Genuine API-selected shot shown? | Results + replay? | Intervention / issue | Pass? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| R1 | | | | | | | |
| R2 | | | | | | | |
| R3 | | | | | | | |

Final build frozen: ______  Backup video verified: ______  Submission links verified: ______

Codex story source/task: ______  Before evidence: ______  Diff: ______  After evidence: ______

Remaining limitation stated in demo/submission: ______
