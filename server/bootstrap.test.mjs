import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { legalShots } from './providers/contract.mjs';

test('Fresh station entry point loads repaired adapters and serves a genuine route using isolated mocks', async () => {
  const temporary = await mkdtemp(join(tmpdir(), 'aircade-station-bootstrap-'));
  const configPath = join(temporary, 'station.json');
  const mongoPath = join(temporary, 'mock-mongo.mjs');
  const loaderPath = join(temporary, 'loader.mjs');
  const preloadPath = join(temporary, 'mock-fetch.mjs');
  // Mock via the subprocess loader, not a production backdoor. No real MongoDB
  // connection, collection writes, test-database deletion, or external calls.
  await writeFile(mongoPath, `export class MongoClient { async connect() {} db(){return {collection(){return {async createIndex(){}}},async command(){return {ok:1}}}} async close(){} }`);
  await writeFile(loaderPath, `export async function resolve(specifier,context,nextResolve){if(specifier==='mongodb')return {url:${JSON.stringify(pathToFileURL(mongoPath).href)},shortCircuit:true};return nextResolve(specifier,context)}`);
  await writeFile(preloadPath, `globalThis.fetch=async(url,request)=>{if(url!=='https://api.openai.com/v1/responses')throw Error('External calls forbidden in bootstrap test');const body=JSON.parse(request.body);if(body.model!=='gpt-6-astra'||body.reasoning.effort!=='low'||body.text.format.strict!==true)throw Error('Unexpected request');return Response.json({id:'resp_bootstrap',status:'completed',model:'gpt-6-astra',output:[{type:'message',content:[{type:'output_text',text:'{"candidateID":"deep-right"}'}]}]})}`);
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const child = spawn(process.execPath, ['--experimental-loader', loaderPath, '--import', preloadPath, 'server.mjs'], {
    cwd: import.meta.dirname,
    env: { ...process.env, HOST: '127.0.0.1', PORT: String(port), AIRCADE_STATION_CONFIG: configPath,
      OPENAI_API_KEY: 'test-only-not-a-real-key', AI_GATEWAY_API_KEY: '', BASETEN_API_KEY: '',
      MONGODB_URI: 'mongodb://127.0.0.1:1', MONGODB_DB: 'unused_mock_only' }, stdio: ['ignore', 'pipe', 'pipe']
  });
  let output = ''; child.stdout.on('data', value => output += value); child.stderr.on('data', value => output += value);
  try {
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt++) {
      if (child.exitCode != null) throw Error(output);
      try { ready = (await fetch(`http://127.0.0.1:${port}/api/health`)).ok; } catch {}
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.equal(ready, true, output);
    const health = await (await fetch(`http://127.0.0.1:${port}/api/health`)).json();
    assert.equal(health.contractVersion, 'tactical-v1');
    const config = JSON.parse(await readFile(configPath, 'utf8'));
    assert.equal(config.url, `http://127.0.0.1:${port}`);
    const request = { provider: 'astra', observationID: 'bootstrap-observation', difficulty: 'rival', score: 0, misses: 0, longestRally: 0,
      playerID: '00000000-0000-0000-0000-000000000000',
      candidates: legalShots.map(shot => ({ ...shot, distance: Math.abs(shot.targetX), reactionTime: shot.flightDuration, pace: 1 / shot.flightDuration, targetsWeakSide: shot.targetX < 0, rallyLength: 0 })) };
    const response = await fetch(`http://127.0.0.1:${port}/api/tennis/opponent-plan`, { method: 'POST',
      headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(request) });
    assert.equal(response.status, 200);
    const plan = await response.json();
    assert.equal(plan.provider, 'OpenAI API'); assert.equal(plan.modelVersion, 'gpt-6-astra');
    assert.equal(plan.observationID, request.observationID); assert.equal(plan.responseID, 'resp_bootstrap');
    assert.equal(plan.returns[0].candidateID, 'deep-right'); assert.equal(plan.returns[0].targetX, 3.1); assert.equal(plan.fallbackUsed, false);
    assert.doesNotMatch(JSON.stringify(plan), /test-only-not-a-real-key|00000000-0000/);
    const unauthorized = await fetch(`http://127.0.0.1:${port}/api/tennis/opponent-plan`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(request) });
    assert.equal(unauthorized.status, 401);
    const jevUnavailable = await fetch(`http://127.0.0.1:${port}/api/tennis/opponent-plan`, { method: 'POST',
      headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ ...request, provider: 'jev' }) });
    assert.equal(jevUnavailable.status, 503);
    const failure = await jevUnavailable.json();
    assert.equal(failure.provider, 'jev'); assert.equal(failure.code, 'unavailable'); assert.equal(failure.returns, undefined);
    const coolingDown = await fetch(`http://127.0.0.1:${port}/api/tennis/opponent-plan`, { method: 'POST',
      headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(request) });
    assert.equal(coolingDown.status, 429); assert.ok(Number(coolingDown.headers.get('retry-after')) > 0);
  } finally {
    child.kill('SIGTERM');
    if (child.exitCode == null && child.signalCode == null) await new Promise(resolve => child.once('exit', resolve));
    await rm(temporary, { recursive: true, force: true });
  }
});
