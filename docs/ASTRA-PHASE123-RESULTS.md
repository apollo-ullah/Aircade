# Astra Tennis: phases 1–3

Implemented September 19, 2026 on `codex/astra-phase-zero`.

## What is playable

Tennis → **Challenge Astra** opens a separate 60-second challenge. Astra observes
native court screenshots and operates a browser rail and swing button with the
Responses API computer tool. The native app receives those bounded inputs and
checks real swept racket/ball contact. It does not auto-intercept for Astra.
The original assisted GLM/local rally is unchanged and remains separately selectable.

The experimental challenge uses eight-second flights for both players. Each miss
awards the other player a point; neutral serves alternate; highest points wins and
equal scores draw. Results, rematch, next player, pause/reconnect and AirPod menu
navigation are integrated. The player's name and badge ID are captured at start.
These scores cannot enter the legacy Tennis leaderboard.

The screen shows the last image submitted to the API, actual mouse actions,
completed request latency, input age and counted returns. The local arena uses
an authenticated ephemeral port, one request at a time, bounded image uploads,
run/rally/frame identities, native monotonic timestamps and stale-input rejection.
Pause/end cancels work; a failed service visibly interrupts the challenge.

## Live model evidence

Real `gpt-6-astra`, actual SceneKit observations, Playwright input, production native
command and collision path. Ten seeded incoming balls: -2.5 / 0 / +2.5 court lanes.
No automatic interception or human-return helper was active.

- Initial trial: **1/10 returns**. The rail and rendered court had mismatched scales.
- After aligning the rail with the orthographic court and explaining input latency:
  **5/10 returns**, with successful returns in **all three lanes**.
- Successful trials: 0 (left), 1 (centre), 2 (right), 4 (centre), 7 (centre).
- The other five trials were genuine misses; no fallback substituted a return.
- 30 requests initiated in the revised rehearsal. Known usage estimate: **$0.3252**;
  interrupted requests may not have returned usage, so this is not an invoice.
- Ten completed move/click batches: median request latency **3,013.5 ms**,
  range **2,307–3,610 ms**. This excludes preliminary screenshot requests.
- Median sampled native capture duration: **13.21 ms**, at two captures/second.
  Capture still consumes main-thread time; this is not a claim of zero added latency.

Local artifacts:

- `.local/astra-arena/2026-09-19T23-09-18.664Z/` — initial trace/screenshots.
- `.local/astra-arena/2026-09-19T23-11-23.936Z/` — revised trace/screenshots.
- `.local/astra-arena-rehearsal/report.json` — revised per-ball results.
- `.local/astra-arena-rehearsal/initial-report.json` — initial failed gate.
- `.local/astra-phase123-ui/` — reviewed native menu/challenge UI captures.

## Verification

- Full Swift suite: **190 tests, zero failures, one opt-in live test skipped**.
- Separately enabled live ten-ball test: passed (5 returns, gate is at least 3).
- Controller geometry tests cover bounded movement, idle and misplaced misses,
  both human/opponent contact paths, duplicate/stale commands, exactly-once return,
  alternating serves, pause clock, results and reset.
- Browser integration test operates real controls, checks frame-stamped commands,
  one-time queue consumption, prior-rally rejection and cross-origin/auth rejection.
- Existing Phase 0 probe: 7/7 tests passed. Station: 2/2 tests passed.
- Native challenge menu/UI inspected; release build signed ad hoc.

## Remaining acceptance / limits

**A complete physical AirPod-versus-Astra round has not been verified.** Test a full
round, results, rematch and next player with the real controller before calling
phases 2–3 accepted. Five returns from ten fixed shots establish a working loop,
not a reliable competitive opponent or normal-speed reaction.

The development app launches Node from this checkout; Node, Chrome and the shared
Playwright installation are required. This is not yet a portable app distribution.
Manual browser rehearsal is available without billable calls. API calls begin only
when a challenge starts. Request/cost caps are explicit; reconnect resets the arena.

No Jev integration, shared model leaderboard or AI-versus-AI mode was added.
