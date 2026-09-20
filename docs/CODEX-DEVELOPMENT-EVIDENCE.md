# Codex development evidence

Status: current-task evidence plus remaining verification fields. Do not present unchecked physical outcomes as completed, and do not infer assistant attribution from a commit author or branch name.

## Verified current-task story: the benchmark caught our own scheduler

While reviewing the first live comparison through its report UI, this Codex task found **seven of eighty planned attempts** labelled as rate limits with **zero-millisecond elapsed time**. The completed report is preserved at `.local/paired-decisions-final/report.json`, run `6d55d7b6-ef15-4e95-97e0-6ff48e66deeb`.

Those instant failures were local admission rejections, not evidence that either external model was rate-limiting the same number of submitted requests. The affected attempt IDs are 15, 27, 43, 51, 61, 67, and 71. The original report also counted planned calls as submitted too early, so retain it as diagnostic evidence rather than a clean provider comparison.

The comparison runner scheduled its next call before the planner recorded the actual start time. Fractional-millisecond waits and early timer wakeups could leave the planner's minimum interval unfinished. A fixture was then consumed by a local cooldown error.

Codex's implementation agent fixed this by exposing the planner's next eligible time from its monotonic clock, rounding waits upward, and rechecking eligibility after every wake. The report now records whether transport actually started and distinguishes `local_rate_limit` from an external `rate_limit` with `failureSource: "provider"`. This preserves failed attempts while identifying which failures really reached a provider.

The focused comparison suite was rerun after the change: **7 tests passed, 0 failed**. In particular, the regression deliberately introduces fractional planner-start delays and early timer wakes; all ten planned synthetic requests are admitted with the required spacing. A separate test checks that local admission failures are not counted as submitted requests and that actual external HTTP 429 responses remain identifiable.

| Evidence | File or check |
| --- | --- |
| Original live report and seven instant failures | `.local/paired-decisions-final/report.json` and its `index.html` |
| Planner admission time | `server/providers/planner.mjs`, `nextEligibleInMs()` |
| Wait rounding, clock rechecks, and request provenance | `server/benchmark/comparison.mjs` |
| Fractional-delay / early-wake regression | `server/benchmark/comparison.test.mjs`, “Fractional planner starts and early timer wakes never consume fixtures as local rate limits” |
| Local versus provider rejection regression | Same test file, “Local admission failures are not submitted API requests and remote HTTP429 is distinguished” |
| Passing focused suite | `node --test server/benchmark/comparison.test.mjs` — 7/7 passed |
| Assistant attribution | This Codex task's report inspection, delegated correction, and passing check; attach its task share link if desired |
| Corrected live rerun | `docs/evidence/DecisionComparison.json` and `.html`, scheduling `monotonic-admission-v2`; completed run `5c52f869-b34d-4d00-a30c-c3241444bc1d` |

Suggested 25-second explanation:

> “Our first comparison showed seven instant rate-limit failures. Codex helped trace them to our own scheduler: a fractional wait could wake too early. We fixed it to recheck the actual request clock and wrote a regression that deliberately wakes early. The report now separates our local rejections from provider failures, so we can make a more defensible comparison.”

The corrected live rerun completed **80/80 planned attempts**. Astra and Jev each produced **40 valid decisions from 40 submitted requests** before the six-second deadline; there were no failed attempts in this run. Astra's median request time was **1,836.5 ms** (range 1,324–4,014 ms), and Jev's was **322 ms** (range 236–1,257 ms). Each latency denominator is 40 valid responses. These are measured results from the completed report, separate from the deterministic regression's result.

The comparison uses synthetic state fixtures and shared tactical inputs/actions while native code supplies movement/contact. It measures decision validity and request latency, not tennis ability, physical controller latency, or a causal token-efficiency effect. Keep the original seven failures in the diagnostic artifact; do not describe them as remote model failures or reuse its original submitted-request denominator. The corrected run is a new complete run, not a replacement of individual failed rows.

## Additional current-task story: station startup and API rival

The implementation plan identified a deleted Jev module still imported by the station as a cold-start problem. This task implemented a shared tactical provider contract, restored the station dependency path, added an Astra Responses API adapter, and made latest versus actually applied model decisions visible in the game. Keep live request evidence and physical verification distinct from mocks and native tests.

The concise story should be written from the final verified result:

> “Our running demo hid a cold-start problem: the station still imported a deleted module. Codex helped us trace the startup dependency, repair it, and add a regression that starts the real entry point. We then reused the tactical interface for Astra so both API rivals receive the same game state and legal shots. The game now shows which model decision was actually applied.”

Use this paragraph only after checking each statement against the final diff, passing startup regression, and actual Codex task. A proposed test is not a passing test, and a successful mocked request is not a live API success.

Capture the following in one evidence card:

| Fact | Required artifact |
| --- | --- |
| Before: cold launch fails | Original missing-import error with the real entry point and revision |
| Codex's contribution | This task's diagnosis/implementation excerpt or shared task link |
| Repair | Small final diff showing the dependency/provider route repair |
| Verification | Passing actual-entry-point startup regression and matching revision |
| API product behavior | Real Astra response identity and a later applied shot using that decision |
| Limits | Physical-controller verification and benchmark status stated separately |

Do not include API keys, authentication headers, attendee identifiers, or full private traces.

## Historical alternative: screenshot rail/court mismatch

`docs/ASTRA-PHASE123-RESULTS.md` records a historical improvement from 1/10 to 5/10 seeded returns after aligning the control rail with the orthographic court and changing latency instructions. Recover the original Codex task and traces before attributing the diagnosis. Two things changed, so this is a before/after development result rather than a controlled causal experiment. It is not a current-build score.

## Team engineering stories with different attribution

The recorded audio-stall repair and packet-gap recovery are strong engineering evidence. Relevant commits `2d15b8c` and `8d7738e` explicitly credit Cursor, so do not relabel them as Codex contributions without separate supporting evidence.

- Original audio reproduction: `~/Library/Application Support/Aircade/Logs/scripted-repro-before-fix.json` records a 505.7 ms feedback callback, 518.9 ms frame, and unintended pause. The matching `scripted-repro-result.json` records a 0.45 ms callback, 51.7 ms frame, and correct defeat/results. These are scripted production-path checks, not physical latency measurements.
- `Tests/AircadeTests/InputRecoveryIntegrationTests.swift` replays the measured 0.280104375-second packet gap through input mapping and collision. The historical live log contains a later pause as well as successful recovery sequences; do not claim the entire session had no pauses.

## Spoken structure

Keep it to 20–30 seconds: what the player saw, what evidence isolated the issue, what Codex specifically changed, and what verified the result. Prefer one concrete failure over a list of generated files or total lines of code.
