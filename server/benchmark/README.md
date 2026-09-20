# Recorded tactical decision comparison

This is a small comparison of **legal decisions and delivery latency**, not model
tennis ability. Native Aircade supplies movement/contact for both tactical rivals.
Desktop computer use remains a different experiment and is not included.

Both providers receive `tactical-v1`: identical sanitized state, the same ordered
five legal actions and the exact same objective. Badge identity, stored profiles,
and inferred weak-side attributes are not sent. Astra uses Responses structured
output; Jev uses the typed evaluation endpoint. Serialization necessarily differs.

## Run without billable calls

From the repository root:

```sh
node --test server/providers/providers.test.mjs server/benchmark/comparison.test.mjs
# Needs installed station dependencies; mocks MongoDB and API in a subprocess.
node --test server/bootstrap.test.mjs
node server/benchmark/run.mjs --mock --output-dir .local/paired-decisions-preview
```

The HTML prominently labels simulated data. It includes filters, per-attempt
provenance, failure counts, and an evidence JSON download. Open `index.html` in a
browser; it uses no external resources and sends no requests.

## Authorized live verification

Export `OPENAI_API_KEY` and `AI_GATEWAY_API_KEY` securely without printing them.
The runner only reads environment variables; it does not search for credentials.
Stop concurrent AI gameplay before a batch so account rate limits do not mix runs.

```sh
# Exactly one configuration smoke request, excluded from the final comparison.
node server/benchmark/run.mjs --live --smoke --provider astra --output-dir .local/astra-smoke
node server/benchmark/run.mjs --live --smoke --provider jev --output-dir .local/jev-smoke

# Exactly 40 attempts/provider, 80 planned attempts total.
node server/benchmark/run.mjs --live --output-dir .local/paired-decisions-final
```

Before the calls, 20 synthetic game-state fixtures are fixed in `fixtures.mjs`.
They cover idle/incoming play, all previous lanes, scores, misses, and rally
lengths. Each repeats twice; the provider that goes first alternates. They are
**not** captured sensor data and contain no tactical-quality labels.

Each provider has one request in flight, at least 2.2 seconds between request
starts, and a six-second deadline. A rate-limited attempt stays in the report;
Retry-After affects the next scheduled request, not a hidden replacement. There
are no unbounded retries. Interrupting retains unstarted slots and incomplete
status. Full live calls are explicitly opt-in and capped at 40/provider.

Scheduling version `monotonic-admission-v2` rechecks the planner's actual
eligibility clock after every timer wake and rounds waits upward. This prevents
fractional milliseconds or an early timer wake from consuming a fixture as a
local cooldown rejection. `submitted` counts initiated transport requests;
local admission failures are not submitted requests. A local cooldown is labelled
`local_rate_limit`, while an external HTTP 429 remains `rate_limit` with
`failureSource: "provider"`. Keep older reports with missing scheduling versions
as diagnostic evidence, not as a clean equal-request comparison.

`report.json` and `index.html` update after every attempt. The JSON includes exact
canonical fixtures, hashes, observed model/response identity, timing, available
usage and reported cost. No keys, badge IDs or arbitrary provider error bodies
are saved. Missing usage/cost is `null`, never inferred zero. Median/range use
valid completions and show their denominator and all failures beside them.

Regenerate an HTML report without calls:

```sh
node server/benchmark/run.mjs --report .local/paired-decisions-final/report.json --output-dir .local/paired-decisions-final
```

The live station route uses a separate per-process cap (default 120 attempts per
provider; `AIRCADE_TACTICAL_MAX_CALLS` allows 1–1000) and the same deadline/cadence.
Restarting the station explicitly resets that process budget. It never silently
substitutes another provider or a local bot for Astra/Jev.

`scripts/start-station.sh` respects `.local/station.json` (or
`AIRCADE_STATION_CONFIG`) instead of assuming port 8787. Explicit `PORT`/`HOST`
values update the saved client URL atomically while preserving station identity
and credentials. Existing dependencies are reused when `npm ls` validates them.
Health must advertise `contractVersion: "tactical-v1"`; an older process needs an
explicit restart. No station credentials are printed by the launch helper.

API round-trip latency is different from native observation-to-applied-shot age,
which also includes scheduling/cached reuse. The native UI reports that separately.
No performance claim is justified until live results have actually been collected.

Sources: [Astra model](https://developers.openai.com/api/docs/models/gpt-6-astra),
[Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs),
[Jev evaluation](https://vercel.com/docs/ai-gateway/modalities/evaluation).
