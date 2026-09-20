import { randomUUID, createHash } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { contractVersion, cadenceMs, deadlineMs, normalizeFailure, canonicalState, sharedObjective, ProviderError } from '../providers/contract.mjs';
import { astraModel } from '../providers/astra.mjs';
import { jevModel } from '../providers/jev.mjs';
import { fixtures, fixtureVersion } from './fixtures.mjs';

export function comparisonSchedule({ sampleFixtures = fixtures, repeats = 2, providers = ['astra', 'jev'] } = {}) {
  const schedule = [];
  for (let repeat = 0; repeat < repeats; repeat++) {
    for (let index = 0; index < sampleFixtures.length; index++) {
      const order = (repeat + index) % 2 ? [...providers].reverse() : [...providers];
      for (const provider of order) schedule.push({ fixture: sampleFixtures[index], repeat: repeat + 1, provider });
    }
  }
  return schedule;
}
export function summarize(attempts) {
  return Object.fromEntries(['astra', 'jev'].map(provider => {
    const rows = attempts.filter(row => row.provider === provider);
    const valid = rows.filter(row => row.outcome === 'valid');
    const latencies = valid.map(row => row.latencyMs).sort((a, b) => a - b);
    const n = latencies.length;
    const median = n ? (latencies[Math.floor((n - 1) / 2)] + latencies[Math.floor(n / 2)]) / 2 : null;
    const counts = {};
    for (const row of rows) counts[row.outcome] = (counts[row.outcome] || 0) + 1;
    return [provider, { planned: rows.length, submitted: rows.filter(row => row.attempted).length, validWithinDeadline: n,
      medianLatencyMs: median, minimumLatencyMs: n ? latencies[0] : null, maximumLatencyMs: n ? latencies.at(-1) : null, outcomes: counts }];
  }));
}
export async function runComparison({ planner, mode = 'live', build = 'unknown', sampleFixtures = fixtures, repeats = 2,
  providers = ['astra', 'jev'], signal, wait = (ms, signal) => sleep(ms, undefined, { signal }),
  now = () => performance.now(), spacingMs = cadenceMs, onProgress = async () => {} } = {}) {
  const schedule = comparisonSchedule({ sampleFixtures, repeats, providers });
  const nextAllowed = new Map();
  const report = {
    schemaVersion: 1, runID: randomUUID(), mode, recorded: true, completed: false, startedAt: new Date().toISOString(), completedAt: null,
    build, contractVersion, fixtureVersion,
    fixtureSetHash: createHash('sha256').update(JSON.stringify(sampleFixtures.map(fixture => ({ id: fixture.id, inputHash: fixture.inputHash })))).digest('hex'),
    fixtureCount: sampleFixtures.length, repeats, plannedAttempts: schedule.length, processedAttempts: 0,
    fixtures: sampleFixtures.map(fixture => ({ id: fixture.id, inputHash: fixture.inputHash, state: canonicalState(fixture.body) })),
    settings: { models: { astra: astraModel, jev: jevModel }, deadlineMs, cadenceMs: spacingMs, maxInFlightPerProvider: 1,
      astraReasoning: 'low', astraMaxOutputTokens: 2048, objective: sharedObjective, schedulingVersion: 'monotonic-admission-v2' },
    limits: ['Synthetic state fixtures; recorded API results.', 'Native game supplies movement and contact for both tactical rivals.',
      'Measures delivery latency and legal decisions, not tennis skill or a causal token-efficiency effect.',
      'Endpoint-specific serialization differs. This small sample is not a production latency guarantee.',
      'Successful-completion latency excludes failed/cancelled requests; failure counts remain visible. Missing usage/cost is unknown.'],
    attempts: schedule.map((item, index) => ({ index: index + 1, provider: item.provider, fixtureID: item.fixture.id, repeat: item.repeat,
      inputHash: item.fixture.inputHash, attempted: false, requestedAt: null, completedAt: null, outcome: 'not_started',
      candidateID: null, latencyMs: null, elapsedMs: null, responseID: null, usage: null, reportedCostUSD: null }))
  };
  // Persist the frozen inputs and all planned slots before making a request.
  // A hard interruption therefore still leaves an honest planned denominator.
  report.summary = summarize(report.attempts);
  await onProgress(report);
  for (const [index, item] of schedule.entries()) {
    const row = { index: index + 1, provider: item.provider, fixtureID: item.fixture.id, repeat: item.repeat,
      inputHash: item.fixture.inputHash, attempted: false, requestedAt: null, completedAt: null,
      outcome: 'not_started', candidateID: null, latencyMs: null, elapsedMs: null, responseID: null, usage: null, reportedCostUSD: null };
    try {
      // Anchor admission to the planner's actual start time as well as the
      // schedule. Recheck after every wake: timers can truncate fractional ms.
      while (!signal?.aborted) {
        const remaining = Math.max((nextAllowed.get(item.provider) || 0) - now(), planner.nextEligibleInMs?.(item.provider) || 0);
        if (remaining <= 0) break;
        await wait(Math.max(1, Math.ceil(remaining)), signal);
      }
      if (signal?.aborted) throw signal.reason;
      const started = now();
      nextAllowed.set(item.provider, started + spacingMs);
      row.attempted = true; row.requestedAt = new Date().toISOString();
      try {
        const plan = await planner.plan({ ...item.fixture.body, provider: item.provider, observationID: `${report.runID}:${index}` }, { signal });
        row.attempted = plan.requestSent ?? true;
        row.elapsedMs = Math.round(now() - started);
        if (plan.inputHash !== item.fixture.inputHash) throw new ProviderError('invalid');
        row.outcome = plan.latencyMs <= deadlineMs ? 'valid' : 'timeout';
        row.candidateID = plan.selectedCandidateID; row.latencyMs = plan.latencyMs; row.responseID = plan.responseID;
        row.modelVersion = plan.modelVersion; row.usage = plan.usage; row.reportedCostUSD = plan.reportedCostUSD;
      } catch (error) {
        const failure = normalizeFailure(error, signal);
        row.attempted = failure.requestSent ?? row.attempted;
        if (!row.attempted) row.requestedAt = null;
        row.failureSource = failure.source ?? null;
        row.outcome = failure.code === 'rate_limit' && failure.source === 'local' ? 'local_rate_limit' : failure.code;
        row.elapsedMs = Math.round(now() - started);
        // A refused/incomplete/invalid response may still report billed usage.
        // Keep it with the failed attempt; never present it as a valid decision.
        if (failure.metadata) {
          const { modelVersion, responseID, usage, reportedCostUSD } = failure.metadata;
          Object.assign(row, { modelVersion: modelVersion ?? null, responseID: responseID ?? null,
            usage: usage ?? null, reportedCostUSD: reportedCostUSD ?? null });
        }
        if (failure.retryAfterMs != null) {
          row.retryAfterMs = failure.retryAfterMs;
          nextAllowed.set(item.provider, Math.max(nextAllowed.get(item.provider), now() + failure.retryAfterMs));
        }
      }
    } catch (error) {
      // An interrupted schedule retains every unstarted slot without claiming
      // that an API request was sent for those rows.
      if (!signal?.aborted) throw error;
    }
    row.completedAt = row.attempted ? new Date().toISOString() : null;
    report.attempts[index] = row; report.processedAttempts = index + 1; report.summary = summarize(report.attempts);
    await onProgress(report);
  }
  report.completed = !signal?.aborted;
  report.completedAt = new Date().toISOString();
  report.summary = summarize(report.attempts);
  await onProgress(report);
  return report;
}
