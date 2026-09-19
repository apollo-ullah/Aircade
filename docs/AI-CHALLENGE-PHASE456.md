# AI Challenge phases 4–6

Implementation: September 19, 2026. **Live Jev and exhibition acceptance is blocked
by Vercel customer verification**, not a missing API key. Physical-controller
acceptance from the original plan is also still pending.

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
- **Timing:** one Jev call in flight, at most four decisions/second, a six-second
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

## Gateway setup and current blocker

The user's personal Vercel team is `adyan-ullahs-projects`. Chrome was used to
inspect Jev, its official API documentation and Gateway setup. The authenticated
Vercel CLI saved a dedicated `Aircade-Jev-Hackathon` key directly into ignored `.env`
with mode 0600, a $5 total quota and seven-day expiry. No key was printed or committed.

A live evaluation request returned HTTP 403, type `customer_verification_required`:
Vercel requires a card on file before serving requests. Chrome is left at the team's
Add a Card dialog for the user to finish. No payment method was submitted by the agent.
No successful Jev inference, measured Jev latency or Jev tennis return is claimed.
The two-model exhibition cannot be accepted until that provider works.

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

Still required: live Jev ten-ball trial, full two-model round, then three physical
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
