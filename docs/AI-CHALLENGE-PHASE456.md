# AI Challenge phases 4–6

Implementation: September 19, 2026. Vercel billing verification is resolved and
real Jev inference works. Physical-controller acceptance remains pending.

## Implemented

- **Opponent selection:** Astra / screen control; Jev / measured-state control;
  GLM / the existing assisted tactical rally. Changing opponent ends the old session.
- **Jev adapter:** documented `POST https://ai-gateway.vercel.sh/v1/evaluate`, model
  `typesafe-ai/jev`, restricted to its TypeSafe provider. Seven bounded lane choices
  plus a typed swing probability. No generative-language-model substitute.
- **Observation contract:** four recent measured ball/racket observations, timestamps,
  incoming direction and current swing status. No flight destination, future ball
  position, intercept helper or scoring outcome is sent. Jev inputs go through the
  same validated native command queue and finite-racket collision rules as Astra.
- **Timing:** one Jev call in flight, at least 2.2 seconds between request starts, a six-second
  timeout/observation lease, frame/run/rally checks and cancellation across changes.
  UI latency is measured after requests finish; there is no fastest-model claim.
- **Separate local rankings:** persisted in Application Support/Aircade, distinct
  from the shared legacy Tennis leaderboard. Exact provider/model/control/rules/speed
  variants; best run per badge; wins, point differential, human points, then earlier
  result. Guest, simulated, assisted, exhibition, incomplete or interrupted runs
  cannot rank. Private badge profiles remain out of the public station board.
- **Exhibition:** explicit Astra-vs-Jev start, two separate processes/queues/leases,
  mirrored court observations and racket geometry, independent command sequences,
  real contact and misses, 60-second results. Human freshness gates are bypassed
  only in this explicit mode. No exhibition score enters a human ranking.
- **Provider errors:** unavailable/expired-budget states are visible and disable
  start. Authentication or billing errors cannot launch another model silently.

## Gateway setup and live evidence

The user's personal Vercel team is `adyan-ullahs-projects`. Chrome was used to
inspect Jev, its official API documentation and Gateway setup. The authenticated
Vercel CLI saved a dedicated `Aircade-Jev-Hackathon` key directly into ignored `.env`
with mode 0600, a $5 total quota and seven-day expiry. No key was printed or committed.
The user completed card verification. A direct inference succeeded in 857 ms.

The first sustained trial exposed HTTP 429. Gateway response headers report
**30 requests/minute**. Rate limits now honor Retry-After and retry using a fresh
observation without pausing the simulation or substituting another model. Requests
are spaced at least 2.2 seconds apart, even across rally/run changes. Cooldowns are
visible in diagnostics and traces.

The first recovered ten-ball rehearsal returned **4/10**, across left and centre
lanes; median completed inference was **395 ms** (209–1,920 ms). This run still used
one-second pacing and encountered two cooldowns (34 and 41 seconds), causing missed
balls. It is evidence of real Jev-controlled contact, not reliable demo performance.
Trace: `.local/astra-arena/2026-09-19T23-47-07.113Z/trace.json`.
The initial full exhibition completed 60 seconds but neither model returned a ball;
merely reaching results is insufficient. The exhibition acceptance test now requires
at least one real return from **each** model.

### Final Jev rehearsal

With 2.2-second pacing and instructions that account for that cadence, Jev returned
**10/10** seeded balls across all three lanes. There were **zero rate limits and
zero timeouts**. The session initiated 37 evaluations; completed decision latency
was median **340 ms**, range **238–848 ms**. Gateway reported zero cost for those
responses; this is an API-reported value, not a future pricing guarantee.
Trace: `.local/astra-arena/2026-09-19T23-51-38.028Z/trace.json`.
Report: `.local/jev-arena-rehearsal/report.json` (`hardwareVerified: false`).

A six-second Jev timeout now discards that decision and retries from fresh measured
state, without pausing the game. Authentication and other permanent failures remain
visible failures. No model fallback or assisted contact was introduced.

### Final two-model exhibition

The final 60-second unattended match completed normally: **Jev 1 – Astra 0**, with
**three real returns by each model**. Both scored through finite racket collision;
there was no physical controller or assisted return logic. The strengthened live
test passed, including completion, both return counts and leaderboard exclusion.
Report: `.local/ai-exhibition-report.json`.
Astra trace: `.local/astra-arena/2026-09-19T23-53-12.311Z/trace.json`.
Jev trace: `.local/astra-arena/2026-09-19T23-53-12.313Z/trace.json`.

Astra's instruction now explicitly identifies the supplied image as the current
browser screenshot, encouraging direct action rather than an initial screenshot
request. This preserves the real computer-use tool/action loop and screenshot-only
observations. A successful single match is not a reliability guarantee.

Validation after these fixes: Jev ten-ball live test passed; full exhibition live
test passed; four Node adapter/arena tests passed; release build passed.

## Validation and acceptance commands

```
node --test tools/astra-arena/*.test.mjs
swift test
# Real API, ten incoming balls, real production command/collision path:
AIRCADE_ASTRA_LIVE_TEST=1 AIRCADE_REHEARSAL_PROVIDER=jev swift test --filter testLiveAstraTenBalls
# Real Astra + Jev, full 60-second unattended round:
AIRCADE_AI_EXHIBITION_TEST=1 swift test --filter testLiveExhibitionRound
./scripts/build.sh
```

Unit coverage includes typed decisions/model identity, sanitized failures, frame
identity, bounded motion, mirrored real contact, independent side sequences,
score idempotency, persistence, exact variants and ranking exclusions. Normal tests
skip billable live rehearsals. The full suite passed before final privacy/UI tweaks;
focused challenge tests are repeated after them. Native opponent-selection UI was
rendered and inspected. Existing Astra evidence remains 5/10 across all three lanes
from the prior phase; that is not evidence about Jev.

Still required: three physical
rounds including rematch, next player and reconnect. Capture a backup video from a
verified round. Do not describe this as finalist-guaranteed or fully demo-accepted.

## Four-minute judging script

1. **0:00–0:35 — Controller:** hand over the AirPod/iPhone, explain that familiar
   hardware becomes a motion controller, and let the judge swing.
2. **0:35–1:35 — Astra rally:** play a full round. Point out the exact screenshot,
   actual mouse action, measured latency, and a real miss. State the fixed slow speed.
3. **1:35–2:10 — Result:** show the score and badge's model-specific station rank.
4. **2:10–3:10 — Jev, only after verification:** select state control and show a
   typed movement/swing decision. Disclose its different observation interface.
5. **3:10–4:00 — Engineering:** bounded inputs, actual collisions, stale-action
   rejection and independent simulation/network loops. If verified, show the two-model
   exhibition; otherwise keep the working Astra or assisted GLM mode as the demo.

Official contracts:
- https://vercel.com/docs/ai-gateway/modalities/evaluation
- https://vercel.com/ai-gateway/models/jev
- https://vercel.com/i/what-is-jev
- https://developers.openai.com/api/docs/guides/tools-computer-use
