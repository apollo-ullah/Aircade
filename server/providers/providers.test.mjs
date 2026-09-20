import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalState, legalShots, sharedObjective, ProviderError, publicFailure, stateHash } from './contract.mjs';
import { astraBody, evaluateAstra } from './astra.mjs';
import { jevBody, evaluateJev } from './jev.mjs';
import { TacticalPlanner } from './planner.mjs';
import { fixtures } from '../benchmark/fixtures.mjs';

const body = provider => ({ ...structuredClone(fixtures[4].body), provider, observationID: 'test:observation-1' });
const astraResponse = (candidateID = 'right') => ({ id: 'resp_fixture', status: 'completed', model: 'gpt-6-astra', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify({ candidateID }) }] }], usage: { input_tokens: 140, output_tokens: 70, total_tokens: 210, output_tokens_details: { reasoning_tokens: 60 } } });
const jevResponse = (candidateID = 'right') => ({ model: 'typesafe-ai/jev', answers: { shot: { choice: candidateID } } });
const assertCode = code => error => error instanceof ProviderError && error.code === code;

test('Astra and Jev receive identical sanitized state, five actions, objective and order', () => {
  const original = body('astra');
  original.playerID = 'private-badge'; original.nickname = 'Sensitive Name'; original.history = [{ secret: true }];
  const state = canonicalState(original);
  const astra = astraBody(state), jev = jevBody(state);
  assert.deepEqual(JSON.parse(astra.input[1].content), jev.state);
  assert.equal(astra.input[0].content, jev.questions.shot.instructions);
  assert.equal(astra.input[0].content, sharedObjective);
  assert.deepEqual(Object.keys(jev.questions.shot.criteria), legalShots.map(shot => shot.id));
  assert.deepEqual(astra.text.format.schema.properties.candidateID.enum, legalShots.map(shot => shot.id));
  assert.doesNotMatch(JSON.stringify(state), /private-badge|Sensitive Name|history|targetsWeakSide/);
  assert.equal(astra.model, 'gpt-6-astra'); assert.equal(astra.reasoning.effort, 'low');
  assert.equal(astra.text.format.strict, true); assert.equal(astra.store, false);
  assert.equal(astra.max_output_tokens, 2048);
  assert.deepEqual(jev.providerOptions.gateway.only, ['typesafe-ai']);
});

test('Contract rejects missing, duplicate and modified actions, but normalizes Float precision/order', () => {
  for (const mutate of [b => b.candidates.pop(), b => b.candidates[0] = b.candidates[1], b => b.candidates[0].targetX = 4, b => b.candidates[0].flightDuration = NaN, b => b.score = -1]) {
    const value = body('astra'); mutate(value); assert.throws(() => canonicalState(value), assertCode('invalid'));
  }
  const value = body('astra');
  value.candidates[0].targetX = -3.0999999046325684; value.candidates.reverse();
  assert.deepEqual(canonicalState(value).candidates, legalShots);
  assert.equal(stateHash(canonicalState(value)), stateHash(canonicalState(body('jev'))));
});

test('Adapters call the actual documented endpoints, preserve selections and return only safe metadata', async () => {
  const state = canonicalState(body('astra'));
  const signal = AbortSignal.timeout(1000);
  const astra = await evaluateAstra({ state, key: 'test-only', signal, fetchImpl: async (url, request) => {
    assert.equal(url, 'https://api.openai.com/v1/responses'); assert.equal(request.headers.Authorization, 'Bearer test-only');
    assert.equal(request.signal, signal); assert.deepEqual(JSON.parse(request.body), astraBody(state));
    return Response.json(astraResponse('deep-left'));
  } });
  assert.equal(astra.candidateID, 'deep-left'); assert.equal(astra.responseID, 'resp_fixture');
  assert.equal(astra.usage.reasoning_tokens, 60); assert.equal(astra.reportedCostUSD, null);
  const jev = await evaluateJev({ state, key: 'test-only', signal, fetchImpl: async (url, request) => {
    assert.equal(url, 'https://ai-gateway.vercel.sh/v1/evaluate'); assert.deepEqual(JSON.parse(request.body), jevBody(state));
    return Response.json({ ...jevResponse('deep-right'), providerMetadata: { gateway: { cost: '0' } } });
  } });
  assert.equal(jev.candidateID, 'deep-right'); assert.equal(jev.reportedCostUSD, 0); assert.equal(jev.usage, null);
});

test('Missing credentials do not initiate network requests', async () => {
  for (const adapter of [evaluateAstra, evaluateJev]) {
    await assert.rejects(adapter({ state: canonicalState(body('astra')), key: '', fetchImpl: () => assert.fail('Unexpected network') }), assertCode('unavailable'));
  }
});

test('Astra rejects refusal, incomplete output, malformed data, invented shots and alternate models', async () => {
  const samples = [
    ['incomplete', { ...astraResponse(), status: 'incomplete' }],
    ['refused', { ...astraResponse(), output: [{ type: 'message', content: [{ type: 'refusal', refusal: 'private refusal body' }] }] }],
    ['invalid', astraResponse('teleport')], ['invalid', { ...astraResponse(), model: 'a-different-model' }],
    ['invalid', { ...astraResponse(), output: [] }], ['invalid', { ...astraResponse(), output: 'unexpected' }],
    ['invalid', { ...astraResponse(), output: [{ type: 'message', content: [null] }] }],
    ['invalid', { ...astraResponse(), output: [{ type: 'message', content: [{ type: 'output_text', text: '{"candidateID":"right","secret":1}' }] }] }], ['invalid', null]
  ];
  for (const [code, sample] of samples) {
    await assert.rejects(evaluateAstra({ state: canonicalState(body('astra')), key: 'dummy', fetchImpl: async () => Response.json(sample) }), assertCode(code));
  }
});

test('Incomplete responses retain reported usage without exposing response text in public failures', async () => {
  await assert.rejects(evaluateAstra({ state: canonicalState(body('astra')), key: 'dummy',
    fetchImpl: async () => Response.json({ ...astraResponse(), status: 'incomplete', incomplete_details: { reason: 'max_output_tokens' } }) }), error => {
    assert.equal(error.code, 'incomplete');
    assert.equal(error.metadata.responseID, 'resp_fixture');
    assert.equal(error.metadata.usage.output_tokens, 70);
    assert.equal(error.metadata.usage.reasoning_tokens, 60);
    assert.equal(publicFailure(error, 'astra').metadata, undefined);
    return true;
  });
});

test('Abort while consuming the HTTP body counts as timeout or cancellation, not malformed JSON', async () => {
  for (const [code, reason] of [['timeout', new DOMException('Deadline expired', 'TimeoutError')], ['cancelled', new DOMException('Cancelled', 'AbortError')]]) {
    const controller = new AbortController();
    const planner = new TacticalPlanner({ adapters: { astra: options => evaluateAstra({ ...options, key: 'dummy',
      fetchImpl: async () => ({ ok: true, async json() { controller.abort(reason); throw reason; } }) }) } });
    await assert.rejects(planner.plan(body('astra'), { signal: controller.signal }), assertCode(code));
  }
});

test('Jev rejects invented shots and model substitution; missing cost stays unknown', async () => {
  for (const result of [jevResponse('teleport'), { ...jevResponse(), model: 'substitute' }]) {
    await assert.rejects(evaluateJev({ state: canonicalState(body('jev')), key: 'dummy', fetchImpl: async () => Response.json(result) }), assertCode('invalid'));
  }
  const result = await evaluateJev({ state: canonicalState(body('jev')), key: 'dummy', fetchImpl: async () => Response.json(jevResponse()) });
  assert.equal(result.reportedCostUSD, null);
});

test('HTTP errors are sanitized and Retry-After is retained for both providers', async () => {
  for (const adapter of [evaluateAstra, evaluateJev]) {
    const options = { state: canonicalState(body('astra')), key: 'secret-value' };
    await assert.rejects(adapter({ ...options, fetchImpl: async () => new Response('sensitive-provider-body secret-value', { status: 401 }) }), error => {
      assert.doesNotMatch(JSON.stringify(publicFailure(error, 'test')), /secret|sensitive/);
      return assertCode('unavailable')(error);
    });
    await assert.rejects(adapter({ ...options, fetchImpl: async () => new Response('sensitive-provider-body', { status: 429, headers: { 'Retry-After': '3' } }) }), error => error.code === 'rate_limit' && error.retryAfterMs === 3000);
    await assert.rejects(adapter({ ...options, fetchImpl: async () => new Response('invalid-json', { status: 200 }) }), assertCode('invalid'));
  }
});

test('Planner preserves exact chosen shot, echoes observation and gates cadence/budget per provider', async () => {
  let clock = 0;
  const adapter = async () => { clock += 250; return { candidateID: 'deep-right', provider: 'OpenAI API', modelVersion: 'gpt-6-astra' }; };
  const planner = new TacticalPlanner({ adapters: { astra: adapter, jev: adapter }, now: () => clock, maxCalls: 1 });
  const plan = await planner.plan(body('astra'));
  assert.equal(plan.observationID, 'test:observation-1'); assert.equal(plan.selectedCandidateID, 'deep-right');
  assert.equal(plan.returns[0].targetX, 3.1); assert.equal(plan.returns.length, 1); assert.equal(plan.latencyMs, 250);
  assert.equal(plan.decisionState, 'fresh'); assert.equal(plan.fallbackUsed, false); assert.ok(plan.decisionID);
  await assert.rejects(planner.plan(body('astra')), error => error.code === 'rate_limit' && error.retryAfterMs === 1950);
  assert.equal((await planner.plan(body('jev'))).selectedCandidateID, 'deep-right');
  clock = 2400;
  await assert.rejects(planner.plan(body('astra')), assertCode('budget'));
});

test('Planner cancellation and late completion cannot install a plan; one request remains in flight', async () => {
  let finish;
  const pending = new Promise(resolve => { finish = resolve; });
  const planner = new TacticalPlanner({ adapters: { astra: () => pending } });
  const controller = new AbortController();
  const request = planner.plan(body('astra'), { signal: controller.signal });
  await assert.rejects(planner.plan(body('astra')), assertCode('rate_limit'));
  controller.abort(); finish({ candidateID: 'right', modelVersion: 'gpt-6-astra' });
  await assert.rejects(request, assertCode('cancelled'));
  let clock = 0;
  const late = new TacticalPlanner({ now: () => clock, adapters: { astra: async () => { clock = 6001; return { candidateID: 'right', responseID: 'resp_late', usage: { output_tokens: 15 } }; } } });
  await assert.rejects(late.plan(body('astra')), error => {
    assert.equal(error.code, 'timeout'); assert.equal(error.metadata.responseID, 'resp_late');
    assert.equal(error.metadata.usage.output_tokens, 15); return true;
  });
});

test('Planner honors remote cooldown, counts failed calls, and never substitutes a local plan', async () => {
  let clock = 0, calls = 0;
  const planner = new TacticalPlanner({ now: () => clock, maxCalls: 2, adapters: { jev: async () => { calls++; throw new ProviderError('rate_limit', { retryAfterMs: 9000 }); } } });
  await assert.rejects(planner.plan(body('jev')), assertCode('rate_limit'));
  clock = 3000;
  await assert.rejects(planner.plan(body('jev')), error => error.retryAfterMs === 6000);
  assert.equal(calls, 1);
  clock = 9000;
  await assert.rejects(planner.plan(body('jev')), assertCode('rate_limit'));
  clock = 20000;
  await assert.rejects(planner.plan(body('jev')), assertCode('budget'));
  assert.equal(calls, 2);
});
