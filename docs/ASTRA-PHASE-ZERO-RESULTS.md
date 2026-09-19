# Astra Phase 0: live results

September 19, 2026, 22:19 UTC. Branch: `codex/astra-phase-zero`.

**PASS: three real screenshot/action/screenshot trials using `gpt-6-astra` through the OpenAI Responses API's computer tool.** The model requested a screenshot, selected the target's coordinates, moved the browser pointer, clicked, and completed the response after receiving the changed screenshot. No coordinate hints, DOM access, alternate model or automatic target correction was supplied to the model.

| Measurement | Result |
| --- | --- |
| Static target trials | 3/3 successful, one swing per target |
| Completed API requests | 9/9 |
| Screenshot-to-action latency, individual trials | 3,427 ms / 3,345 ms / 2,256 ms |
| Median screenshot-to-action latency | 3,345 ms |
| Completed API request latency range | 1,552–5,365 ms |
| Median completed API request latency | 3,100 ms |
| Estimated standard token charges | About $0.16, including reported cache writes; excludes additional tool fees and is not a billing receipt |

Action latency is measured from completion of the latest screenshot capture to applying model-returned pointer input. It excludes each trial's preliminary screenshot-request round trip and the final confirmation call. Each fresh trial needed all three calls. Startup must therefore be completed before serving a live ball. These tiny-sample measurements do not establish production percentiles or sustained throughput.

The test page uses a recorded native Tennis court and a static yellow target. Input and resulting pixels are real browser interactions, but there is no moving ball, native racket collision or physical AirPod play in this phase. This result establishes account access, tool compatibility and static visual targeting only.

## Next-phase decision

Proceed with Phase 1's manually controlled opponent and real contact physics. For Phase 2, evaluate Astra in a clearly labelled fixed slower mode first; a roughly three-second action loop leaves little room for repeated observation and correction within the current ball flight. Keep native rendering asynchronous and expire late actions. Do not compensate by silently freezing the ball or handing interception to the legacy bot.

## Evidence and verification

Local ignored evidence: `.local/astra-probe/2026-09-19T22-19-14-968Z-live/` contains `report.json`, `report.md`, before/after screenshots, actual computer actions, response IDs and usage counters. The third trial's resulting screenshot was visually inspected and displays TARGET HIT with the racket on the target. No credentials are stored in these artifacts.

Seven automated checks cover browser input boundaries, whole-batch validation, request configuration, cache accounting, a mocked API round trip through real browser input, safety-check interruption and provider-error redaction/no retry. Three separate scripted browser trials verify hits and deliberate misses without any API access.

The key was copied from the original checkout's `.env` to the integration checkout's ignored `.env` with mode 0600. Neither key nor generated local evidence is committed. The production Mac game and published `main` are unchanged.
