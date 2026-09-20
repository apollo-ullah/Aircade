import { createHash, randomUUID } from 'node:crypto';

export const contractVersion = 'tactical-v1';
export const deadlineMs = 6000;
export const cadenceMs = 2200;
export const sharedObjective = 'Choose exactly one supplied legal tennis return against this player. Your selection directly sets target, flight duration, delay and stroke. The native game handles court movement and contact for every provider. Use only the supplied state. Prefer tactically useful placement and changing the previous return when useful. Do not invent actions or assume unobserved player weaknesses.';
export const legalShots = Object.freeze([
  { id: 'deep-left', targetX: -3.10, flightDuration: 2.72, delay: 0.34, stroke: 'forehand' },
  { id: 'left', targetX: -1.55, flightDuration: 2.88, delay: 0.38, stroke: 'backhand' },
  { id: 'middle', targetX: 0, flightDuration: 2.42, delay: 0.31, stroke: 'forehand' },
  { id: 'right', targetX: 1.55, flightDuration: 2.86, delay: 0.39, stroke: 'forehand' },
  { id: 'deep-right', targetX: 3.10, flightDuration: 2.68, delay: 0.35, stroke: 'backhand' }
].map(Object.freeze));

const descriptions = {
  invalid: 'Model returned an invalid decision', refused: 'Model declined the decision',
  incomplete: 'Model response was incomplete', timeout: 'Model missed the six-second deadline',
  rate_limit: 'Model is cooling down; retry shortly', unavailable: 'Model connection is unavailable',
  network: 'Model connection failed', budget: 'Model request budget reached', cancelled: 'Model request cancelled'
};
export class ProviderError extends Error {
  constructor(code, { retryAfterMs, status, metadata, source, requestSent } = {}) {
    super(descriptions[code] || descriptions.unavailable);
    this.code = Object.hasOwn(descriptions, code) ? code : 'unavailable';
    this.status = status || (this.code === 'rate_limit' ? 429 : ['invalid', 'refused', 'incomplete'].includes(this.code) ? 502 : 503);
    if (Number.isFinite(retryAfterMs)) this.retryAfterMs = Math.max(0, Math.ceil(retryAfterMs));
    // Internal evidence only; publicFailure deliberately omits response metadata.
    if (metadata) this.metadata = metadata;
    if (source) this.source = source;
    if (typeof requestSent === 'boolean') this.requestSent = requestSent;
  }
}
export function normalizeFailure(error, signal) {
  // A deadline can expire while decoding a response body. Its classification
  // takes precedence over a parser error; preserve any already received usage.
  if (signal?.aborted) return new ProviderError(signal.reason?.name === 'TimeoutError' ? 'timeout' : 'cancelled', { metadata: error?.metadata, source: error?.source, requestSent: error?.requestSent });
  if (error instanceof ProviderError) return error;
  if (error?.name === 'TimeoutError') return new ProviderError('timeout');
  if (error?.name === 'AbortError') return new ProviderError('cancelled');
  return new ProviderError('network');
}
export function publicFailure(error, provider) {
  const failure = normalizeFailure(error);
  return { error: failure.message, code: failure.code, provider,
    ...(failure.retryAfterMs == null ? {} : { retryAfterMs: failure.retryAfterMs }) };
}
export function retryAfterMs(response, now = Date.now()) {
  const value = response.headers.get('retry-after');
  const seconds = value == null ? NaN : Number(value);
  return Math.max(1000, Number.isFinite(seconds) ? seconds * 1000 : (Date.parse(value) || now + 1000) - now);
}
export function checkHTTP(response) {
  if (response.ok) return;
  if (response.status === 429) throw new ProviderError('rate_limit', { retryAfterMs: retryAfterMs(response), source: 'provider', requestSent: true });
  throw new ProviderError('unavailable', { source: 'provider', requestSent: true }); // Never expose arbitrary remote error bodies or credentials.
}
export async function responseJSON(response) {
  try {
    const value = await response.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Not an object');
    return value;
  } catch { throw new ProviderError('invalid'); }
}
const finite = (value, low, high) => typeof value === 'number' && Number.isFinite(value) && value >= low && value <= high;
function integer(value, high) {
  if (!Number.isInteger(value) || !finite(value, 0, high)) throw new ProviderError('invalid', { status: 400 });
  return value;
}
function optionalX(value, limit) {
  if (value == null) return null;
  if (!finite(value, -limit, limit)) throw new ProviderError('invalid', { status: 400 });
  return Number(value.toFixed(4));
}
export function canonicalState(body) {
  if (!body || !Array.isArray(body.candidates) || body.candidates.length !== legalShots.length) throw new ProviderError('invalid', { status: 400 });
  // Accept native Float serialization noise, but never change a client's legal action.
  // Re-emit the versioned constants so both providers see byte-identical actions.
  const ids = new Set();
  for (const candidate of body.candidates) {
    const legal = legalShots.find(shot => shot.id === candidate?.id);
    if (!legal || ids.has(candidate.id) || candidate.stroke !== legal.stroke
      || ['targetX', 'flightDuration', 'delay'].some(key => !Number.isFinite(candidate[key]) || Math.abs(candidate[key] - legal[key]) > 0.00001)) {
      throw new ProviderError('invalid', { status: 400 });
    }
    ids.add(candidate.id);
  }
  return {
    contractVersion,
    player: { score: integer(body.score, 1000000), misses: integer(body.misses, 1000), longestRally: integer(body.longestRally, 1000),
      incomingBallX: optionalX(body.incomingBallX, 5), opponentAttemptX: optionalX(body.opponentAttemptX, 5), previousReturnX: optionalX(body.previousReturnX, 3.5) },
    candidates: legalShots.map(shot => ({ ...shot }))
  };
}
export const stateHash = state => createHash('sha256').update(JSON.stringify(state)).digest('hex');
export function selectedShot(state, candidateID) {
  const shot = state.candidates.find(candidate => candidate.id === candidateID);
  if (!shot) throw new ProviderError('invalid');
  return shot;
}
export function sanitizedUsage(usage) {
  if (!usage || typeof usage !== 'object') return null;
  const cleaned = {};
  for (const [key, aliases] of Object.entries({ input_tokens: ['input_tokens', 'inputTokens', 'prompt_tokens'], output_tokens: ['output_tokens', 'outputTokens', 'completion_tokens'], total_tokens: ['total_tokens', 'totalTokens'] })) {
    const value = aliases.map(alias => usage[alias]).find(value => Number.isFinite(value) && value >= 0);
    if (value != null) cleaned[key] = value;
  }
  for (const [key, value] of Object.entries({ cached_input_tokens: usage.input_tokens_details?.cached_tokens, reasoning_tokens: usage.output_tokens_details?.reasoning_tokens })) {
    if (Number.isFinite(value) && value >= 0) cleaned[key] = value;
  }
  return Object.keys(cleaned).length ? cleaned : null;
}
export function decisionPlan({ body, state, result, latencyMs, receivedAt, completedAt }) {
  const shot = selectedShot(state, result.candidateID);
  const observationID = typeof body.observationID === 'string' && /^[a-zA-Z0-9_.:-]{1,100}$/.test(body.observationID) ? body.observationID : randomUUID();
  return {
    provider: result.provider, modelVersion: result.modelVersion, latencyMs, fallbackUsed: false,
    observationID, decisionID: randomUUID(), receivedAt, completedAt, decisionState: 'fresh', contractVersion,
    selectedCandidateID: shot.id, inputHash: stateHash(state),
    inputSummary: `Score ${state.player.score}; ${state.player.misses} misses; previous target ${state.player.previousReturnX ?? 'none'}; five legal shots.`,
    responseID: result.responseID || null, usage: result.usage || null, reportedCostUSD: result.reportedCostUSD ?? null,
    returns: [{ candidateID: shot.id, targetX: shot.targetX, flightDuration: shot.flightDuration, delay: shot.delay, stroke: shot.stroke,
      // Compatibility field only; this is not a calibrated return probability.
      returnProbability: 1 }]
  };
}
