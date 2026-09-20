import { mkdir, writeFile, rename, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { TacticalPlanner } from '../providers/planner.mjs';
import { evaluateAstra } from '../providers/astra.mjs';
import { evaluateJev } from '../providers/jev.mjs';
import { runComparison } from './comparison.mjs';
import { fixtures } from './fixtures.mjs';
import { renderReport } from './report.mjs';

const args = process.argv.slice(2);
const value = name => { const index = args.indexOf(name); return index < 0 ? null : args[index + 1]; };
const root = resolve(import.meta.dirname, '../..');
if (!args.includes('--live') && !args.includes('--mock') && !args.includes('--report')) {
  console.log('Usage: node server/benchmark/run.mjs --mock | --live [--smoke --provider astra|jev] [--output-dir PATH]\n       node server/benchmark/run.mjs --report report.json [--output-dir PATH]\nLive calls are opt-in. Export OPENAI_API_KEY / AI_GATEWAY_API_KEY without printing them. A full run sends exactly 40 attempts per provider; no failed attempt is silently retried.');
  process.exit(0);
}
if (args.includes('--live') && args.includes('--mock')) throw Error('Choose live OR mock mode');
const output = resolve(value('--output-dir') || join(root, '.local', 'paired-decisions', new Date().toISOString().replaceAll(':', '-')));
await mkdir(output, { recursive: true, mode: 0o700 });
async function save(report) {
  await writeFile(join(output, 'report.json.tmp'), JSON.stringify(report, null, 2), { mode: 0o600 });
  await rename(join(output, 'report.json.tmp'), join(output, 'report.json'));
  await writeFile(join(output, 'index.html'), renderReport(report), { mode: 0o600 });
}
if (args.includes('--report')) {
  const report = JSON.parse(await readFile(resolve(value('--report')), 'utf8'));
  await save(report); console.log(`Recorded report: ${join(output, 'index.html')}`); process.exit(0);
}
const mock = args.includes('--mock'), smoke = args.includes('--smoke');
const requestedProvider = value('--provider');
if (requestedProvider && (!smoke || !['astra', 'jev'].includes(requestedProvider))) throw Error('--provider astra|jev is only supported with --smoke');
const providers = requestedProvider ? [requestedProvider] : ['astra', 'jev'];
if (!mock) {
  for (const provider of providers) {
    const name = provider === 'astra' ? 'OPENAI_API_KEY' : 'AI_GATEWAY_API_KEY';
    if (!process.env[name]?.trim()) throw Error(`${name} is unavailable; no requests sent`);
  }
}
const adapters = mock ? Object.fromEntries(providers.map(provider => [provider, async ({ state, onRequestStart }) => { onRequestStart(); return ({
  candidateID: state.candidates[Math.floor(state.player.score / 480) % 5].id,
  provider: provider === 'astra' ? 'OpenAI API' : 'Vercel Jev', modelVersion: provider === 'astra' ? 'gpt-6-astra' : 'typesafe-ai/jev',
  responseID: 'simulated-no-api-call', usage: null, reportedCostUSD: null
}); }])) : { astra: evaluateAstra, jev: evaluateJev };
let build = 'unknown';
try { build = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim(); } catch {}
try { if (execFileSync('git', ['status', '--porcelain'], { cwd: root, encoding: 'utf8' }).trim()) build += '+uncommitted'; } catch {}
const controller = new AbortController();
process.once('SIGINT', () => controller.abort()); process.once('SIGTERM', () => controller.abort());
const planner = new TacticalPlanner({ adapters, maxCalls: smoke ? 1 : 40, spacingMs: mock ? 0 : 2200 });
let previousCount = 0;
const report = await runComparison({ planner, mode: mock ? 'simulated' : 'live', build,
  sampleFixtures: smoke ? fixtures.slice(0, 1) : fixtures, repeats: smoke ? 1 : 2,
  providers, signal: controller.signal, spacingMs: mock ? 0 : 2200,
  onProgress: async report => {
    await save(report);
    if (report.processedAttempts !== previousCount) {
      previousCount = report.processedAttempts;
      const row = report.attempts[report.processedAttempts - 1];
      console.log(`${row.index}/${report.plannedAttempts} ${row.provider} ${row.fixtureID} ${row.outcome}${row.latencyMs == null ? '' : ` ${row.latencyMs}ms`}`);
    }
  }
});
console.log(JSON.stringify({ completed: report.completed, mode: report.mode, summary: report.summary, report: join(output, 'index.html') }, null, 2));
if (!report.completed || Object.values(report.summary).some(value => value.submitted && value.validWithinDeadline === 0)) process.exitCode = 1;
