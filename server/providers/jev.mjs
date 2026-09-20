import { checkHTTP, responseJSON, ProviderError, selectedShot, sharedObjective, sanitizedUsage } from './contract.mjs';

export const jevModel = 'typesafe-ai/jev';
export function jevBody(state) {
  return { model: jevModel, providerOptions: { gateway: { only: ['typesafe-ai'] } }, state,
    questions: { shot: { type: 'choice', instructions: sharedObjective,
      criteria: Object.fromEntries(state.candidates.map(shot => [shot.id, `Aim x=${shot.targetX}; flight ${shot.flightDuration}s; delay ${shot.delay}s; ${shot.stroke}.`])) } } };
}
export async function evaluateJev({ state, signal, key = process.env.AI_GATEWAY_API_KEY, fetchImpl = fetch, onRequestStart = () => {} }) {
  if (!key?.trim()) throw new ProviderError('unavailable', { source: 'local', requestSent: false });
  onRequestStart();
  const response = await fetchImpl('https://ai-gateway.vercel.sh/v1/evaluate', {
    method: 'POST', signal, headers: { Authorization: `Bearer ${key.trim()}`, 'Content-Type': 'application/json' }, body: JSON.stringify(jevBody(state))
  });
  checkHTTP(response);
  const result = await responseJSON(response);
  const candidateID = result.answers?.shot?.choice;
  const rawCost = result.providerMetadata?.gateway?.cost;
  const cost = rawCost == null || rawCost === '' ? NaN : Number(rawCost);
  const metadata = { provider: 'Vercel Jev', modelVersion: result.model === jevModel ? result.model : null,
    responseID: typeof result.id === 'string' ? result.id.slice(0, 200) : null, usage: sanitizedUsage(result.usage),
    reportedCostUSD: Number.isFinite(cost) && cost >= 0 ? cost : null };
  if (result.model !== jevModel || typeof candidateID !== 'string') throw new ProviderError('invalid', { metadata });
  try { selectedShot(state, candidateID); } catch { throw new ProviderError('invalid', { metadata }); }
  return { candidateID, ...metadata };
}
