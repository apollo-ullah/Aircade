import { checkHTTP, responseJSON, ProviderError, selectedShot, sharedObjective, sanitizedUsage } from './contract.mjs';

export const astraModel = 'gpt-6-astra';
export function astraBody(state) {
  return {
    model: astraModel, store: false, reasoning: { effort: 'low' }, max_output_tokens: 2048,
    input: [{ role: 'developer', content: sharedObjective }, { role: 'user', content: JSON.stringify(state) }],
    text: { format: { type: 'json_schema', name: 'tennis_shot', strict: true,
      schema: { type: 'object', properties: { candidateID: { type: 'string', enum: state.candidates.map(shot => shot.id) } }, required: ['candidateID'], additionalProperties: false } } }
  };
}
export async function evaluateAstra({ state, signal, key = process.env.OPENAI_API_KEY, fetchImpl = fetch, onRequestStart = () => {} }) {
  if (!key?.trim()) throw new ProviderError('unavailable', { source: 'local', requestSent: false });
  onRequestStart();
  const response = await fetchImpl('https://api.openai.com/v1/responses', {
    method: 'POST', signal, headers: { Authorization: `Bearer ${key.trim()}`, 'Content-Type': 'application/json' }, body: JSON.stringify(astraBody(state))
  });
  checkHTTP(response);
  const result = await responseJSON(response);
  const validModel = typeof result.model === 'string' && /^gpt-6-astra(?:-\d{4}-\d{2}-\d{2})?$/.test(result.model);
  const metadata = { provider: 'OpenAI API', modelVersion: validModel ? result.model : null,
    responseID: typeof result.id === 'string' ? result.id.slice(0, 200) : null,
    usage: sanitizedUsage(result.usage), reportedCostUSD: null };
  const fail = code => new ProviderError(code, { metadata });
  if (result.status === 'incomplete') throw fail('incomplete');
  if (result.status !== 'completed' || !validModel) throw fail('invalid');
  const content = (Array.isArray(result.output) ? result.output : []).filter(item => item?.type === 'message').flatMap(item => Array.isArray(item.content) ? item.content : []);
  if (content.some(item => item?.type === 'refusal')) throw fail('refused');
  const texts = content.filter(item => item?.type === 'output_text').map(item => item.text);
  if (texts.length !== 1 || typeof texts[0] !== 'string') throw fail('invalid');
  let parsed;
  try { parsed = JSON.parse(texts[0]); } catch { throw fail('invalid'); }
  if (!parsed || Object.keys(parsed).length !== 1 || typeof parsed.candidateID !== 'string') throw fail('invalid');
  try { selectedShot(state, parsed.candidateID); } catch { throw fail('invalid'); }
  return { candidateID: parsed.candidateID, ...metadata };
}
