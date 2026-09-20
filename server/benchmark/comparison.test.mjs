import { test } from 'node:test';
import assert from 'node:assert/strict';
import { comparisonSchedule, runComparison, summarize } from './comparison.mjs';
import { fixtures } from './fixtures.mjs';
import { renderReport } from './report.mjs';
import { ProviderError } from '../providers/contract.mjs';
import { TacticalPlanner } from '../providers/planner.mjs';
import { evaluateAstra } from '../providers/astra.mjs';
import { evaluateJev } from '../providers/jev.mjs';

test('Schedule freezes 20 paired states, repeats twice and alternates first provider', () => {
  const schedule = comparisonSchedule();
  assert.equal(fixtures.length, 20); assert.equal(schedule.length, 80);
  assert.equal(new Set(fixtures.map(value => value.inputHash)).size, 20);
  assert.deepEqual(schedule.slice(0, 4).map(value => value.provider), ['astra', 'jev', 'jev', 'astra']);
  assert.deepEqual(schedule.slice(40, 42).map(value => value.provider), ['jev', 'astra']);
  for (const fixture of fixtures) {
    const rows = schedule.filter(value => value.fixture.id === fixture.id);
    assert.equal(rows.filter(row => row.provider === 'astra').length, 2);
    assert.equal(rows.filter(row => row.provider === 'jev').length, 2);
  }
});

test('Comparison retains failed attempts, same paired hashes, explicit unknown usage and cooldowns', async () => {
  let clock = 0, calls = 0;
  const waits = [];
  const planner = { async plan(body) {
    calls++; clock += 100;
    if (calls === 1) throw new ProviderError('rate_limit', { retryAfterMs: 9000 });
    if (calls === 3) throw new ProviderError('timeout');
    const fixture = fixtures.find(fixture => fixture.body.score === body.score && fixture.body.previousReturnX === body.previousReturnX);
    return { inputHash: fixture.inputHash, selectedCandidateID: 'right', latencyMs: 100, responseID: 'test-response', modelVersion: body.provider, usage: null, reportedCostUSD: null };
  } };
  const report = await runComparison({ planner, sampleFixtures: fixtures.slice(0, 2), repeats: 1, now: () => clock,
    wait: async delay => { waits.push(delay); clock += delay; } });
  assert.equal(report.attempts.length, 4); assert.equal(calls, 4);
  assert.deepEqual(report.attempts.map(row => row.outcome), ['rate_limit', 'valid', 'timeout', 'valid']);
  assert.equal(report.summary.astra.planned, 2); assert.equal(report.summary.astra.validWithinDeadline, 1);
  assert.equal(report.summary.jev.medianLatencyMs, 100);
  assert.equal(report.attempts[0].inputHash, report.attempts[1].inputHash);
  assert.equal(report.attempts[2].inputHash, report.attempts[3].inputHash);
  assert.ok(waits.some(wait => wait > 2200));
  assert.equal(report.attempts[1].usage, null); assert.equal(report.completed, true);
});

test('Fractional planner starts and early timer wakes never consume fixtures as local rate limits', async () => {
  let clock = 0;
  const starts = [], waits = [];
  const actual = new TacticalPlanner({ now: () => clock, spacingMs: 2.2, adapters: { astra: async ({ onRequestStart }) => {
    onRequestStart(); starts.push(clock); clock += 0.1;
    return { candidateID: 'right', provider: 'OpenAI API', modelVersion: 'gpt-6-astra' };
  } } });
  const planner = {
    nextEligibleInMs: provider => actual.nextEligibleInMs(provider),
    plan: (...args) => { clock += 0.45; return actual.plan(...args); }
  };
  const report = await runComparison({ planner, sampleFixtures: fixtures.slice(0, 5), repeats: 2,
    providers: ['astra'], spacingMs: 2.2, now: () => clock,
    wait: async ms => { waits.push(ms); clock += Math.max(0.1, ms - 1.5); } });
  assert.equal(starts.length, 10);
  assert.ok(starts.slice(1).every((start, index) => start - starts[index] >= 2.2));
  assert.ok(waits.length > 9, 'Early wakes must trigger additional eligibility checks');
  assert.ok(waits.every(Number.isInteger));
  assert.equal(report.summary.astra.submitted, 10);
  assert.equal(report.summary.astra.validWithinDeadline, 10);
  assert.deepEqual(report.summary.astra.outcomes, { valid: 10 });
});

test('Local admission failures are not submitted API requests and remote HTTP429 is distinguished', async () => {
  const planner = new TacticalPlanner({ spacingMs: 0, adapters: {
    astra: options => evaluateAstra({ ...options, key: '', fetchImpl: () => assert.fail('Missing credentials cannot send') }),
    jev: options => evaluateJev({ ...options, key: 'test-only', fetchImpl: async () => new Response('', { status: 429 }) })
  } });
  const report = await runComparison({ planner, sampleFixtures: fixtures.slice(0, 1), repeats: 1, spacingMs: 0 });
  assert.equal(report.summary.astra.submitted, 0); assert.equal(report.summary.jev.submitted, 1);
  assert.equal(report.attempts[0].failureSource, 'local'); assert.equal(report.attempts[0].requestedAt, null);
  assert.equal(report.attempts[1].failureSource, 'provider'); assert.equal(report.attempts[1].outcome, 'rate_limit');

  const denied = { nextEligibleInMs: () => 0, async plan() { throw new ProviderError('rate_limit', { source: 'local', requestSent: false, retryAfterMs: 1 }); } };
  const localReport = await runComparison({ planner: denied, sampleFixtures: fixtures.slice(0, 1), repeats: 1, providers: ['astra'], spacingMs: 0 });
  assert.equal(localReport.summary.astra.submitted, 0);
  assert.equal(localReport.summary.astra.outcomes.local_rate_limit, 1);
});

test('Interrupted comparison records every remaining slot as unstarted, not successful requests', async () => {
  const controller = new AbortController();
  const planner = { async plan() { controller.abort(); throw new ProviderError('cancelled'); } };
  const report = await runComparison({ planner, sampleFixtures: fixtures.slice(0, 2), repeats: 1, signal: controller.signal, spacingMs: 0 });
  assert.equal(report.attempts.length, 4); assert.equal(report.completed, false);
  assert.deepEqual(report.attempts.map(row => row.outcome), ['cancelled', 'not_started', 'not_started', 'not_started']);
  assert.equal(report.summary.astra.submitted, 1); assert.equal(report.summary.jev.submitted, 0);
});

test('Failed model completions keep their available usage and remain in the failure denominator', async () => {
  const planner = { async plan() { throw new ProviderError('incomplete', { metadata: {
    modelVersion: 'gpt-6-astra', responseID: 'resp_incomplete',
    usage: { input_tokens: 100, output_tokens: 2048 }, reportedCostUSD: null
  } }); } };
  const report = await runComparison({ planner, sampleFixtures: fixtures.slice(0, 1), repeats: 1, providers: ['astra'], spacingMs: 0 });
  assert.equal(report.summary.astra.planned, 1);
  assert.equal(report.summary.astra.validWithinDeadline, 0);
  assert.equal(report.summary.astra.outcomes.incomplete, 1);
  assert.equal(report.attempts[0].responseID, 'resp_incomplete');
  assert.equal(report.attempts[0].usage.output_tokens, 2048);
  assert.equal(report.attempts[0].candidateID, null);
  assert.equal(report.attempts[0].reportedCostUSD, null);
});

test('Report keeps failure denominator, safely escapes metadata, and labels simulated results', async () => {
  const planner = { async plan() { throw new ProviderError('unavailable'); } };
  const report = await runComparison({ planner, mode: 'simulated', build: '</script><img src=x onerror=alert(1)>', sampleFixtures: fixtures.slice(0, 1), repeats: 1, spacingMs: 0 });
  const html = renderReport(report);
  assert.match(html, /SIMULATED FIXTURE · NO LIVE API RESULTS/);
  assert.match(html, /unavailable/); assert.match(html, /do not rank tennis ability/);
  assert.doesNotMatch(html, /<img src=x/);
  const evidence = html.match(/id="evidence">(.*?)<\/script>/s)[1];
  assert.deepEqual(JSON.parse(evidence), report);
  assert.equal(summarize([{ provider: 'astra', outcome: 'valid', attempted: true, latencyMs: 10 }, { provider: 'astra', outcome: 'timeout', attempted: true, latencyMs: null }]).astra.medianLatencyMs, 10);
});
