import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { createHash, randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { MongoClient } from 'mongodb';

test('MongoDB profiles, privacy, idempotent scores, validation and leaderboards', async () => {
  const database = `aircade_test_${randomUUID().replaceAll('-', '')}`;
  const child = spawn(process.execPath, ['server.mjs'], { cwd: import.meta.dirname, env: { ...process.env, PORT: '8788', MONGODB_DB: database }, stdio: 'pipe' });
  let output = ''; child.stdout.on('data', d => output += d); child.stderr.on('data', d => output += d);
  const mongo = new MongoClient(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017');
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      if (child.exitCode !== null) throw new Error(output);
      try { if ((await fetch('http://127.0.0.1:8788/api/health')).ok) { ready = true; break; } } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert.ok(ready, output);
    const config = JSON.parse(readFileSync(new URL('../.local/station.json', import.meta.url)));
    async function request(route, method = 'GET', body, authenticated = true) {
      const r = await fetch(`http://127.0.0.1:8788${route}`, { method, headers: { 'Content-Type': 'application/json', ...(authenticated ? { Authorization: `Bearer ${config.token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
      return { status: r.status, body: await r.json() };
    }
    const digest = createHash('sha256').update('test-badge-only-not-a-real-attendee').digest('hex');
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
        writeFileSync(configFile, JSON.stringify({ ...config, url: 'http://127.0.0.1:8788' }), { mode: 0o600 });
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
  }
});
