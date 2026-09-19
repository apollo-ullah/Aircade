# Astra Tennis arena

Native Aircade owns all physics. This sidecar presents the actual SceneKit court to
`gpt-6-astra` and executes its computer-tool mouse actions with isolated Playwright.
It does not receive ball coordinates or choose interception positions.

## Run

1. `npm ci --prefix tools/astra-probe` (shared Playwright dependency).
2. Put `OPENAI_API_KEY` in the repository's ignored `.env`. Node and Chrome must be installed.
3. Build/run Aircade, open **Tennis → Challenge Astra → Start challenge**.

The app launches this sidecar from its source checkout, with an ephemeral loopback
port and random bearer token. It currently requires the checkout to remain in place;
this is a hackathon station integration, not a distributable app bundle.
Only starting a challenge enables model requests. Reconnect starts a fresh arena.
Stop, route exit, app quit and process termination cancel activity and close Chrome.

**Manual opponent rehearsal** uses the exact same browser → authenticated command
queue → native controller path without API calls. Open the controls in a second
browser window. Native background auto-pause is disabled only in this explicit
manual mode so the browser can receive mouse input.

## Rules

- 60 seconds, eight-second flights on **both** sides, alternating neutral serves.
- Each miss awards one point. Most points wins; equal scores draw.
- Position moves at at most 3 scene units/second, inside ±4.6 units.
- A click initiates one three-second forward stroke. Stationary or misplaced rackets miss.
- Real finite-racket swept collision, no snap-to-ball or automatic return.
- The orthographic camera is behind Astra's baseline. Screen-left is world +X.
  The 184px rail is aligned to the ±4.6-world-unit span in the 1024×510 image.
- Screenshots upload at 2Hz; commands poll at 10Hz; native physics runs at 60Hz.
- Commands retain the exact observed run, rally and frame. Native capture timestamps
  determine age, avoiding cross-process clock comparisons. Maximum age: six seconds.
- One model request at a time; no backlog. Pauses/rally changes invalidate responses.
- Forty calls / estimated $1.50 per match, plus 200 calls / $5 per arena session, checked before each request.
  One in-flight request can cross the estimate. Provider failures visibly interrupt;
  no fallback model is silently substituted. Cost estimates are not invoices.
- Experimental scores never enter the existing Tennis leaderboard.

The panel shows the last exact screenshot sent, returned mouse actions, completed
request latency, command observation age and real return count. No fabricated reasoning.
Traces and original observations are written to `.local/astra-arena/<timestamp>/`.
No camera/user desktop images are captured—only the rendered court/control page.

## Validation

```
node --test tools/astra-arena/server.test.mjs
swift test --filter AIChallengeTests
# Opt-in: ten real API trials, about 90 seconds; not a physical-controller test.
AIRCADE_ASTRA_LIVE_TEST=1 swift test --filter AIChallengeIntegrationTests
```

The live test reports to `.local/astra-arena-rehearsal/report.json`, fails below
three returns, and remains skipped during ordinary tests. Physical AirPod acceptance
is a separate requirement. A passing small trial is not proof of general tennis skill.
