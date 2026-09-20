import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { MongoClient } from 'mongodb';

async function availablePort() {
  const probe = createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  return port;
}

test('MongoDB profiles, privacy, idempotent scores, validation and leaderboards', async () => {
  const database = `aircade_test_${randomUUID().replaceAll('-', '')}`;
  const temporary = mkdtempSync(path.join(tmpdir(), 'aircade-station-test-'));
  const configPath = path.join(temporary, 'station.json');
  const stationPort = await availablePort();
  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: import.meta.dirname,
    env: { ...process.env, PORT: String(stationPort), AIRCADE_STATION_CONFIG: configPath, MONGODB_DB: database, BASETEN_TENNIS_LLM_URL: '', BASETEN_TENNIS_URL: '', BASETEN_API_KEY: '', OPENAI_API_KEY: '', AI_GATEWAY_API_KEY: '' },
    stdio: 'pipe'
  });
  let output = ''; child.stdout.on('data', d => output += d); child.stderr.on('data', d => output += d);
  const mongo = new MongoClient(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017');
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error(output);
      try { if ((await fetch(`http://127.0.0.1:${stationPort}/api/health`)).ok) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready, output);
    const config = JSON.parse(readFileSync(configPath));
    async function request(route, method = 'GET', body, authenticated = true) {
      const r = await fetch(`http://127.0.0.1:${stationPort}${route}`, { method, headers: { 'Content-Type': 'application/json', ...(authenticated ? { Authorization: `Bearer ${config.token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
      return { status: r.status, body: await r.json() };
    }
    const digest = createHash('sha256').update('test-badge-only-not-a-real-attendee').digest('hex');
    const candidates = [
      { id: 'deep-left', targetX: -0.92, flightDuration: 1.22, delay: 0.34, stroke: 'forehand', distance: 0.92, reactionTime: 1.22, pace: 0.82, targetsWeakSide: true, rallyLength: 4 },
      { id: 'center-fast', targetX: 0.02, flightDuration: 1.08, delay: 0.31, stroke: 'forehand', distance: 0.02, reactionTime: 1.08, pace: 0.93, targetsWeakSide: false, rallyLength: 4 },
      { id: 'deep-right', targetX: 0.94, flightDuration: 1.2, delay: 0.35, stroke: 'backhand', distance: 0.94, reactionTime: 1.2, pace: 0.83, targetsWeakSide: false, rallyLength: 4 }
    ];
    assert.equal((await request('/api/tennis/opponent-plan', 'POST', { difficulty: 'rival', score: 0, misses: 0, longestRally: 0, candidates }, false)).status, 401);
    assert.equal((await request('/api/tennis/opponent-plan', 'POST', { difficulty: 'rival', score: 0, misses: 0, longestRally: 0, candidates: [] })).status, 400);
    const opponentPlan = (await request('/api/tennis/opponent-plan', 'POST', { difficulty: 'rival', score: 400, misses: 1, longestRally: 4, candidates })).body;
    assert.equal(opponentPlan.fallbackUsed, true);
    assert.equal((await request('/api/tennis/opponent-plan', 'POST', { difficulty: 'rival', score: 0, misses: 0, longestRally: 0, candidates, requireModel: true })).status, 503);
    assert.equal(opponentPlan.modelVersion, 'synthetic-logreg-v1');
    assert.deepEqual(new Set(opponentPlan.returns.map(value => value.candidateID)), new Set(candidates.map(value => value.id)));
    for (let i = 1; i < opponentPlan.returns.length; i++) {
      const side = value => value.targetX < -0.2 ? 'left' : value.targetX > 0.2 ? 'right' : 'center';
      assert.notEqual(side(opponentPlan.returns[i - 1]), side(opponentPlan.returns[i]));
    }
    assert.equal((await request('/api/sign-in', 'POST', { badgeDigest: digest }, false)).status, 401);
    const a = (await request('/api/sign-in', 'POST', { badgeDigest: digest })).body;
    assert.equal(a.isPublic, false);
    assert.equal((await request('/api/sign-in', 'POST', { badgeDigest: digest })).body.id, a.id);
    const parallel = await Promise.all(Array.from({ length: 8 }, () => request('/api/sign-in', 'POST', { badgeDigest: 'a'.repeat(64) })));
    assert.equal(new Set(parallel.map(r => r.body.id)).size, 1);
    assert.equal((await request('/api/players/' + a.id, 'PATCH', { nickname: 'Test Player', isPublic: true })).status, 200);
    const run = { id: randomUUID(), playerID: a.id, difficulty: 'Arcade', score: 900, cuts: 6, bestCombo: 6, accuracy: 100, completed: true, isDemo: false, gameVersion: 'test' };
    assert.equal((await request('/api/runs', 'POST', { ...run, isDemo: true })).status, 400);
    assert.equal((await request('/api/runs', 'POST', { ...run, score: -1 })).status, 400);
    assert.equal((await request('/api/runs', 'POST', run, false)).status, 401);
    assert.equal((await request('/api/runs', 'POST', run)).status, 200);
    assert.equal((await request('/api/runs', 'POST', run)).status, 200);
    assert.equal((await request('/api/runs', 'POST', { ...run, score: 901 })).status, 409);
    await request('/api/runs', 'POST', { ...run, id: randomUUID(), score: 300 });
    await request('/api/runs', 'POST', { ...run, id: randomUUID(), difficulty: 'Chill', score: 1200 });
    await request('/api/runs', 'POST', { ...run, id: randomUUID(), game: 'Tennis', difficulty: 'Tennis', score: 1800, cuts: 9, bestCombo: 5, accuracy: 90 });
    const privatePlayer = (await request('/api/sign-in', 'POST', { badgeDigest: 'b'.repeat(64) })).body;
    await request('/api/runs', 'POST', { ...run, id: randomUUID(), playerID: privatePlayer.id, score: 5000 });
    const board = (await request('/api/leaderboard', 'GET', undefined, false)).body;
    assert.equal(board.rows.length, 1); assert.equal(board.rows[0].score, 900); assert.equal(board.rows[0].rank, 1);
    assert.deepEqual(Object.keys(board.rows[0]).sort(), ['accuracy', 'bestCombo', 'nickname', 'rank', 'score']);
    assert.equal((await request('/api/leaderboard?difficulty=Chill')).body.rows[0].score, 1200);
    assert.equal((await request('/api/leaderboard?difficulty=Tennis')).body.rows[0].score, 1800);
    assert.deepEqual((await request(`/api/players/${a.id}/bests`)).body, { Arcade: 900, Chill: 1200, Tennis: 1800 });
    await request('/api/players/' + a.id, 'PATCH', { nickname: 'Test Player', isPublic: false });
    assert.equal((await request('/api/leaderboard')).body.rows.length, 0);
    // A real climb, target, tie handling, opt-out, and replay-safe receipt.
    assert.equal((await request('/api/runs', 'POST', { ...run, id: randomUUID(), game: 'Tennis' })).status, 400);
    await request('/api/players/' + a.id, 'PATCH', { nickname: 'Test Player', isPublic: true });
    await request('/api/players/' + privatePlayer.id, 'PATCH', { nickname: 'Top Player', isPublic: true });
    const rival = (await request('/api/sign-in', 'POST', { badgeDigest: 'c'.repeat(64) })).body;
    await request('/api/players/' + rival.id, 'PATCH', { nickname: 'Next Rival', isPublic: true });
    await request('/api/runs', 'POST', { ...run, id: randomUUID(), playerID: rival.id, score: 3000 });
    assert.equal((await request(`/api/players/${a.id}/standing`, 'GET', undefined, false)).status, 401);
    const before = (await request(`/api/players/${a.id}/standing?difficulty=Arcade`)).body;
    assert.equal(before.rank, 3); assert.equal(before.personalBest, 900);
    assert.deepEqual(before.next, { rank: 2, nickname: 'Next Rival', score: 3000, pointsNeeded: 2101 });
    const climbRun = { ...run, id: randomUUID(), score: 4000 };
    const climb = (await request('/api/runs', 'POST', climbRun)).body.progress;
    assert.equal(climb.standing.rank, 2); assert.equal(climb.previousRank, 3);
    assert.equal(climb.placesClimbed, 1); assert.equal(climb.newPersonalBest, true);
    assert.equal(climb.standing.next.pointsNeeded, 1001);
    assert.deepEqual((await request('/api/runs', 'POST', climbRun)).body.progress, climb);
    const lower = (await request('/api/runs', 'POST', { ...run, id: randomUUID(), score: 600 })).body.progress;
    assert.equal(lower.newPersonalBest, false); assert.equal(lower.placesClimbed, 0); assert.equal(lower.standing.personalBest, 4000);
    const tie = (await request('/api/runs', 'POST', { ...run, id: randomUUID(), score: 5000 })).body.progress;
    assert.equal(tie.standing.rank, 2); assert.equal(tie.standing.next.pointsNeeded, 1);
    const first = (await request('/api/runs', 'POST', { ...run, id: randomUUID(), score: 5001 })).body.progress;
    assert.equal(first.standing.rank, 1); assert.equal(first.placesClimbed, 1); assert.equal(first.standing.next, null);
    assert.deepEqual((await request('/api/runs', 'POST', climbRun)).body.progress, climb, 'later scores cannot rewrite old receipts');
    await request('/api/players/' + a.id, 'PATCH', { nickname: 'Test Player', isPublic: false });
    const privateStanding = (await request(`/api/players/${a.id}/standing`)).body;
    assert.equal(privateStanding.rank, null); assert.equal(privateStanding.next, null); assert.equal(privateStanding.personalBest, 5001);
    assert.ok((await request('/api/leaderboard')).body.rows.every(row => row.nickname !== 'Test Player'));
    await mongo.connect();
    assert.equal(await mongo.db(database).collection('runs').countDocuments({ _id: run.id }), 1);
    const stored = await mongo.db(database).collection('players').findOne({ _id: a.id });
    assert.notEqual(stored.badgeKey, digest); assert.ok(!JSON.stringify(stored).includes('test-badge-only'));
    if (process.env.AIRCADE_NATIVE_CHECK) {
      const temporary = mkdtempSync(path.join(tmpdir(), 'aircade-client-check-'));
      try {
        const configFile = path.join(temporary, 'station.json');
        writeFileSync(configFile, JSON.stringify({ ...config, url: `http://127.0.0.1:${stationPort}` }), { mode: 0o600 });
        const native = spawn(process.env.AIRCADE_NATIVE_CHECK, [], { env: { ...process.env, AIRCADE_STATION_CONFIG: configFile, AIRCADE_CHECK_DIRECTORY: temporary }, stdio: 'pipe' });
        let details = ''; native.stdout.on('data', d => details += d); native.stderr.on('data', d => details += d);
        const result = await new Promise((resolve, reject) => { native.on('error', reject); native.on('exit', resolve); });
        assert.equal(result, 0, details); console.log(details.trim());
      } finally { rmSync(temporary, { recursive: true, force: true }); }
    }

  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => child.exitCode !== null ? resolve() : child.once('exit', resolve));
    await mongo.connect(); await mongo.db(database).dropDatabase(); await mongo.close();
    rmSync(temporary, { recursive: true, force: true });
  }
});

test('Baseten LLM ranks only legal returns and reports remote inference', async () => {
  const stationPort = await availablePort();
  const temporary = mkdtempSync(path.join(tmpdir(), 'aircade-station-llm-test-'));
  const configPath = path.join(temporary, 'station.json');
  let received;
  const mock = createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = { url: req.url, authorization: req.headers.authorization, body: JSON.parse(Buffer.concat(chunks)) };
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({
      model: 'qwen-3-4b-test',
      choices: [{ message: { content: JSON.stringify({ rankedCandidateIds: ['deep-right', 'deep-left', 'middle', 'left', 'right'] }) } }]
    }));
  });
  await new Promise(resolve => mock.listen(0, '127.0.0.1', resolve));
  const modelPort = mock.address().port;
  const database = `aircade_llm_test_${randomUUID().replaceAll('-', '')}`;
  const child = spawn(process.execPath, ['server.mjs'], {
    cwd: import.meta.dirname,
    env: {
      ...process.env, PORT: String(stationPort), AIRCADE_STATION_CONFIG: configPath, MONGODB_DB: database, OPENAI_API_KEY: '', AI_GATEWAY_API_KEY: '',
      BASETEN_TENNIS_LLM_URL: `http://127.0.0.1:${modelPort}/v1`,
      BASETEN_TENNIS_LLM_MODEL: 'qwen-3-4b-test', BASETEN_API_KEY: 'test-key', BASETEN_TENNIS_URL: ''
    },
    stdio: 'pipe'
  });
  let output = ''; child.stdout.on('data', data => output += data); child.stderr.on('data', data => output += data);
  const mongo = new MongoClient(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017');
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error(output);
      try { if ((await fetch(`http://127.0.0.1:${stationPort}/api/health`)).ok) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready, output);
    const config = JSON.parse(readFileSync(configPath));
    const candidates = [
      { id: 'deep-left', targetX: -3.1, flightDuration: 2.72, delay: 0.34, stroke: 'forehand', distance: 3.1, reactionTime: 2.72, pace: 0.37, targetsWeakSide: true, rallyLength: 4 },
      { id: 'left', targetX: -1.55, flightDuration: 2.88, delay: 0.38, stroke: 'backhand', distance: 1.55, reactionTime: 2.88, pace: 0.35, targetsWeakSide: true, rallyLength: 4 },
      { id: 'middle', targetX: 0, flightDuration: 2.42, delay: 0.31, stroke: 'forehand', distance: 0, reactionTime: 2.42, pace: 0.41, targetsWeakSide: false, rallyLength: 4 },
      { id: 'right', targetX: 1.55, flightDuration: 2.86, delay: 0.39, stroke: 'forehand', distance: 1.55, reactionTime: 2.86, pace: 0.35, targetsWeakSide: false, rallyLength: 4 },
      { id: 'deep-right', targetX: 3.1, flightDuration: 2.68, delay: 0.35, stroke: 'backhand', distance: 3.1, reactionTime: 2.68, pace: 0.37, targetsWeakSide: false, rallyLength: 4 }
    ];
    const response = await fetch(`http://127.0.0.1:${stationPort}/api/tennis/opponent-plan`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${config.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ difficulty: 'rival', score: 400, misses: 1, longestRally: 4, previousReturnX: 3.1, candidates })
    });
    assert.equal(response.status, 200);
    const plan = await response.json();
    assert.equal(plan.provider, 'Baseten Model API');
    assert.equal(plan.modelVersion, 'qwen-3-4b-test');
    assert.equal(plan.fallbackUsed, false);
    assert.equal(plan.returns[0].candidateID, 'deep-right'); // Preserve model choice even when it repeats the prior lane.
    assert.deepEqual(new Set(plan.returns.map(value => value.candidateID)), new Set(candidates.map(value => value.id)));
    assert.equal(received.url, '/v1/chat/completions');
    assert.equal(received.authorization, 'Bearer test-key');
    assert.equal(received.body.max_tokens, 96);
    assert.equal(received.body.reasoning_effort, 'low');
    assert.match(received.body.messages[0].content, /every candidate ID exactly once/);
    assert.match(received.body.messages[1].content, /"previousReturnX":3\.1/);
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => child.exitCode !== null ? resolve() : child.once('exit', resolve));
    await mongo.connect(); await mongo.db(database).dropDatabase(); await mongo.close();
    await new Promise(resolve => mock.close(resolve));
    rmSync(temporary, { recursive: true, force: true });
  }
});
