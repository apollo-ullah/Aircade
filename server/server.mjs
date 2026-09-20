import express from 'express';
import { TacticalPlanner } from './providers/planner.mjs';
import { publicFailure, normalizeFailure, contractVersion } from './providers/contract.mjs';
import { loadStationConfig } from './station-config.mjs';
import { MongoClient } from 'mongodb';
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
let localOpponentModel = { modelVersion: 'synthetic-logreg-v1', bias: 2.45, weights: { distance: -1.35, reactionTime: 1.2, pace: -1.05, targetsWeakSide: -0.55, rallyLength: -0.025 } };
try { localOpponentModel = JSON.parse(readFileSync(path.join(root, '..', 'baseten', 'tennis-opponent', 'model', 'weights.json'))); }
catch { /* The bundled coefficients remain a safe fallback for partial deployments. */ }
const { config, host, port, url: stationURL } = loadStationConfig();
const mongo = new MongoClient(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017', { serverSelectionTimeoutMS: 5000 });
await mongo.connect();
const db = mongo.db(process.env.MONGODB_DB || 'aircade');
const players = db.collection('players'), runs = db.collection('runs');
await players.createIndex({ badgeKey: 1 }, { unique: true });
await runs.createIndex({ playerID: 1, game: 1, difficulty: 1, score: -1 });
const app = express();
app.disable('x-powered-by');
app.use((req, res, next) => {
  res.set('Cache-Control', 'no-store');
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'");
  next();
});
app.use(express.json({ limit: '8kb' }));
const asyncRoute = fn => (req, res, next) => Promise.resolve(fn(req, res)).catch(next);
const publicPlayer = p => ({ id: p._id, nickname: p.nickname, isPublic: p.isPublic, needsName: p.nameConfirmed === false || (p.nameConfirmed == null && p.nickname === `Player ${p._id.slice(0, 6)}`) });
const validID = x => typeof x === 'string' && /^[0-9a-f-]{36}$/i.test(x);
const auth = (req, res, next) => {
  const given = Buffer.from(req.get('Authorization') || ''), expected = Buffer.from(`Bearer ${config.token}`);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return res.status(401).json({ error: 'Station authorization required' });
  next();
};
const finite = value => typeof value === 'number' && Number.isFinite(value);
const validOpponentCandidate = value => value && typeof value.id === 'string' && /^[a-z0-9-]{1,32}$/.test(value.id)
  && finite(value.targetX) && Math.abs(value.targetX) <= 3.5
  && finite(value.flightDuration) && value.flightDuration >= 0.85 && value.flightDuration <= 4
  && finite(value.delay) && value.delay >= 0.18 && value.delay <= 0.8
  && ['forehand', 'backhand'].includes(value.stroke)
  && finite(value.distance) && value.distance >= 0 && value.distance <= 5
  && finite(value.reactionTime) && value.reactionTime >= 0.3 && value.reactionTime <= 4
  && finite(value.pace) && value.pace >= 0 && value.pace <= 3
  && typeof value.targetsWeakSide === 'boolean'
  && Number.isInteger(value.rallyLength) && value.rallyLength >= 0 && value.rallyLength <= 1000;

function localOpponentPredictions(candidates) {
  return candidates.map(candidate => {
    // The local fallback loads the same versioned weights deployed by Truss.
    const w = localOpponentModel.weights;
    const logit = localOpponentModel.bias + w.distance * candidate.distance + w.reactionTime * candidate.reactionTime
      + w.pace * candidate.pace + w.targetsWeakSide * Number(candidate.targetsWeakSide)
      + w.rallyLength * Math.min(candidate.rallyLength, 20);
    return { id: candidate.id, returnProbability: 1 / (1 + Math.exp(-logit)) };
  });
}

function opponentPlan(body, inference, metadata) {
  const predictions = new Map(inference.map(value => [value.id, value.returnProbability]));
  const scored = body.candidates.map(candidate => ({
    candidate,
    returnProbability: Math.max(0.02, Math.min(0.98, Number(predictions.get(candidate.id))))
  })).filter(value => Number.isFinite(value.returnProbability));
  if (scored.length !== body.candidates.length) throw Object.assign(new Error('Invalid model response'), { status: 502 });
  // Rival mode aims for competitive shots, while alternating zones prevents a
  // degenerate model from repeating one statistically optimal return forever.
  scored.sort((a, b) => Math.abs(a.returnProbability - 0.56) - Math.abs(b.returnProbability - 0.56));
  const ordered = [], remaining = [...scored];
  while (remaining.length) {
    const previousSide = ordered.at(-1)?.candidate.targetX < -0.2 ? 'left' : ordered.at(-1)?.candidate.targetX > 0.2 ? 'right' : 'center';
    const index = remaining.findIndex(value => {
      const side = value.candidate.targetX < -0.2 ? 'left' : value.candidate.targetX > 0.2 ? 'right' : 'center';
      return side !== previousSide;
    });
    ordered.push(remaining.splice(index < 0 ? 0 : index, 1)[0]);
  }
  return {
    provider: metadata.provider,
    modelVersion: metadata.modelVersion,
    latencyMs: metadata.latencyMs,
    fallbackUsed: metadata.fallbackUsed,
    returns: ordered.map(({ candidate, returnProbability }) => ({
      candidateID: candidate.id,
      targetX: candidate.targetX,
      flightDuration: candidate.flightDuration,
      delay: candidate.delay,
      stroke: candidate.stroke,
      returnProbability
    }))
  };
}

function opponentPlanFromRanking(body, rankedIDs, metadata) {
  const byID = new Map(body.candidates.map(candidate => [candidate.id, candidate]));
  if (!Array.isArray(rankedIDs) || rankedIDs.length !== body.candidates.length
      || new Set(rankedIDs).size !== body.candidates.length
      || rankedIDs.some(id => typeof id !== 'string' || !byID.has(id))) {
    throw new Error('Baseten LLM returned an invalid candidate ranking');
  }
  const ordered = rankedIDs.map(id => byID.get(id));
  return {
    provider: metadata.provider,
    modelVersion: metadata.modelVersion,
    latencyMs: metadata.latencyMs,
    fallbackUsed: false,
    returns: ordered.map((candidate, index) => ({
      candidateID: candidate.id,
      targetX: candidate.targetX,
      flightDuration: candidate.flightDuration,
      delay: candidate.delay,
      stroke: candidate.stroke,
      // Kept for the existing app response schema. For an LLM policy this is a
      // normalized preference score, not a calibrated success probability.
      returnProbability: Math.max(0.05, 0.95 - index * 0.14)
    }))
  };
}

function parseLLMRanking(result, allowedIDs) {
  let content = result?.choices?.[0]?.message?.content;
  const parsedContent = result?.choices?.[0]?.message?.parsed;
  if (Array.isArray(parsedContent?.rankedCandidateIds)) return parsedContent.rankedCandidateIds;
  if (Array.isArray(content)) content = content.map(part => part?.text || '').join('');
  if (typeof content !== 'string') throw new Error('Baseten LLM returned no message');
  let parsed;
  try { parsed = JSON.parse(content); }
  catch {
    const start = content.indexOf('{'), end = content.lastIndexOf('}');
    if (start >= 0 && end > start) parsed = JSON.parse(content.slice(start, end + 1));
    else {
      // Some hosted chat models occasionally ignore JSON mode but still emit
      // every supplied ID. Preserve that ranking only when it is complete and
      // unambiguous; otherwise use the deterministic local fallback.
      const escaped = [...allowedIDs].sort((a, b) => b.length - a.length)
        .map(id => id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
      const matches = [...content.matchAll(new RegExp(`(?:^|[^a-z0-9-])(${escaped.join('|')})(?=$|[^a-z0-9-])`, 'gi'))]
        .map(match => match[1].toLowerCase());
      if (matches.length !== allowedIDs.length || new Set(matches).size !== allowedIDs.length) {
        throw new Error('Baseten LLM returned non-JSON output');
      }
      return matches;
    }
  }
  return parsed?.rankedCandidateIds;
}

async function tennisHistory(playerID) {
  if (!playerID) return { games: 0, averageScore: 0, averageAccuracy: 0, bestCombo: 0 };
  const recent = await runs.find({ playerID, game: 'Tennis' })
    .sort({ createdAt: -1 }).limit(12)
    .project({ _id: 0, score: 1, accuracy: 1, bestCombo: 1 }).toArray();
  if (!recent.length) return { games: 0, averageScore: 0, averageAccuracy: 0, bestCombo: 0 };
  return {
    games: recent.length,
    averageScore: Math.round(recent.reduce((sum, run) => sum + run.score, 0) / recent.length),
    averageAccuracy: Math.round(recent.reduce((sum, run) => sum + run.accuracy, 0) / recent.length),
    bestCombo: Math.max(...recent.map(run => run.bestCombo))
  };
}

async function fetchBasetenLLMPlan(body) {
  const key = process.env.BASETEN_API_KEY;
  if (!key) return null;
  const baseURL = process.env.BASETEN_TENNIS_LLM_URL || 'https://inference.baseten.co/v1';
  const model = process.env.BASETEN_TENNIS_LLM_MODEL || 'zai-org/GLM-5.3-Flash';
  const url = `${baseURL.replace(/\/$/, '')}/chat/completions`;
  const history = await tennisHistory(body.playerID);
  const playerState = {
    currentScore: body.score,
    misses: body.misses,
    longestRally: body.longestRally,
    incomingBallX: body.incomingBallX ?? null,
    opponentAttemptX: body.opponentAttemptX ?? null,
    previousReturnX: body.previousReturnX ?? null,
    history
  };
  const candidateState = body.candidates.map(({ id, targetX, flightDuration, delay, distance, reactionTime, pace, targetsWeakSide, rallyLength }) =>
    ({ id, targetX, flightDuration, delay, distance, reactionTime, pace, targetsWeakSide, rallyLength }));
  const started = performance.now();
  const response = await fetch(url, {
    // Shared Model API latency can spike even when a warm probe is fast. This
    // runs between points and never blocks the render loop, so allow a useful
    // background window before falling back locally.
    method: 'POST', signal: AbortSignal.timeout(8000),
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: 'You are a competitive Wii-style tennis opponent choosing among five horizontal lanes: deep-left, left, middle, right, and deep-right. Rank every supplied legal shot from most to least tactically useful against this player. Do not rank the previous return first when another lane is available. Prefer variety, exploit weak recovery and reaction patterns, and keep the match challenging rather than impossible. Respond with JSON only: {"rankedCandidateIds":["id",...]}. Include every candidate ID exactly once and invent no IDs.' },
        { role: 'user', content: JSON.stringify({ player: playerState, candidates: candidateState }) }
      ],
      reasoning_effort: 'low',
      temperature: 0.15,
      max_tokens: 96,
      response_format: { type: 'json_object' }
    })
  });
  if (!response.ok) throw new Error(`Baseten LLM returned HTTP ${response.status}`);
  const result = await response.json();
  return opponentPlanFromRanking(body, parseLLMRanking(result, body.candidates.map(candidate => candidate.id)), {
    provider: 'Baseten Model API',
    modelVersion: String(result.model || model).slice(0, 80),
    latencyMs: Math.round(performance.now() - started)
  });
}

async function fetchBasetenPlan(body) {
  const url = process.env.BASETEN_TENNIS_URL, key = process.env.BASETEN_API_KEY;
  if (!url || !key) return null;
  const started = performance.now();
  const response = await fetch(url, {
    method: 'POST', signal: AbortSignal.timeout(900),
    headers: { Authorization: `Api-Key ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
  if (!response.ok) throw new Error(`Baseten returned HTTP ${response.status}`);
  const result = await response.json();
  if (!Array.isArray(result.predictions) || typeof result.modelVersion !== 'string') throw new Error('Baseten returned an invalid plan');
  return opponentPlan(body, result.predictions, {
    provider: 'Baseten', modelVersion: result.modelVersion.slice(0, 80),
    latencyMs: Math.round(performance.now() - started), fallbackUsed: false
  });
}
// This cap bounds live station calls until its next explicit restart. Comparison
// runs have a separate fixed 80-attempt budget and never silently retry failures.
const configuredLimit = Number(process.env.AIRCADE_TACTICAL_MAX_CALLS || 120);
const tacticalPlanner = new TacticalPlanner({ maxCalls: Number.isInteger(configuredLimit) && configuredLimit > 0 && configuredLimit <= 1000 ? configuredLimit : 120 });
app.get('/api/health', asyncRoute(async (_, res) => { await db.command({ ping: 1 }); res.json({ ok: true, contractVersion }); }));
app.post('/api/tennis/opponent-plan', auth, asyncRoute(async (req, res) => {
  const body = req.body;
  if (!body || (body.provider != null && !['baseten','jev','astra'].includes(body.provider)) || (body.playerID != null && !validID(body.playerID)) || body.difficulty !== 'rival'
      || (body.observationID != null && (typeof body.observationID !== 'string' || !/^[a-zA-Z0-9_.:-]{1,100}$/.test(body.observationID)))
      || !Number.isInteger(body.score) || body.score < 0 || body.score > 1000000
      || !Number.isInteger(body.misses) || body.misses < 0 || body.misses > 1000
      || !Number.isInteger(body.longestRally) || body.longestRally < 0 || body.longestRally > 1000
      || (body.incomingBallX != null && (!finite(body.incomingBallX) || Math.abs(body.incomingBallX) > 5))
      || (body.opponentAttemptX != null && (!finite(body.opponentAttemptX) || Math.abs(body.opponentAttemptX) > 5))
      || (body.previousReturnX != null && (!finite(body.previousReturnX) || Math.abs(body.previousReturnX) > 3.5))
      || !Array.isArray(body.candidates) || body.candidates.length < 3 || body.candidates.length > 12
      || !body.candidates.every(validOpponentCandidate)
      || new Set(body.candidates.map(value => value.id)).size !== body.candidates.length) {
    return res.status(400).json({ error: 'Invalid tennis opponent request' });
  }
  if (body.provider === 'astra' || body.provider === 'jev') {
    const controller = new AbortController();
    const disconnected = () => { if (!res.writableEnded) controller.abort(); };
    res.on('close', disconnected);
    try {
      const plan = await tacticalPlanner.plan(body, { signal: controller.signal });
      if (!res.destroyed) res.json(plan);
    } catch (error) {
      const failure = normalizeFailure(error);
      if (!res.destroyed) {
        if (failure.retryAfterMs != null) res.set('Retry-After', String(Math.ceil(failure.retryAfterMs / 1000)));
        res.status(failure.status).json(publicFailure(failure, body.provider));
      }
    } finally { res.off('close', disconnected); }
    return;
  }
  try {
    const llm = await fetchBasetenLLMPlan(body);
    if (llm) {
      const incoming = finite(body.incomingBallX) ? body.incomingBallX.toFixed(2) : 'serve';
      const attempted = finite(body.opponentAttemptX) ? body.opponentAttemptX.toFixed(2) : 'ready';
      const reached = finite(body.incomingBallX) && finite(body.opponentAttemptX)
        ? Math.abs(body.incomingBallX - body.opponentAttemptX) <= 0.04 : true;
      const preferred = llm.returns[0];
      console.log(`Tennis opponent: ${llm.provider} · ${llm.modelVersion} · ${llm.latencyMs} ms · incomingX=${incoming} · opponentX=${attempted} · ${reached ? 'reached' : 'missed'} · modelPreference=${preferred.candidateID} targetX=${preferred.targetX.toFixed(2)}`);
      return res.json(llm);
    }
    const remote = await fetchBasetenPlan(body);
    if (remote) {
      console.log(`Tennis opponent: ${remote.provider} · ${remote.modelVersion} · ${remote.latencyMs} ms`);
      return res.json(remote);
    }
  } catch (error) {
    console.warn(`Baseten opponent fallback: ${error.message}`);
  }
  if(body.requireModel === true || body.provider === 'jev') return res.status(503).json({error:'Model plan unavailable; retry shortly'});
  res.json(opponentPlan(body, localOpponentPredictions(body.candidates), {
    provider: 'Local fallback', modelVersion: localOpponentModel.modelVersion, latencyMs: 0, fallbackUsed: true
  }));
}));
app.post('/api/sign-in', auth, asyncRoute(async (req, res) => {
  if (typeof req.body.badgeDigest !== 'string' || !/^[a-f0-9]{64}$/.test(req.body.badgeDigest)) return res.status(400).json({ error: 'Invalid badge digest' });
  const badgeKey = createHmac('sha256', config.badgeSecret).update(req.body.badgeDigest).digest('hex');
  const id = randomUUID();
  try { await players.updateOne({ badgeKey }, { $setOnInsert: { _id: id, badgeKey, nickname: `Player ${id.slice(0, 6)}`, isPublic: false, nameConfirmed: false, createdAt: new Date() } }, { upsert: true }); }
  catch (e) { if (e.code !== 11000) throw e; }
  res.json(publicPlayer(await players.findOne({ badgeKey })));
}));
app.patch('/api/players/:id', auth, asyncRoute(async (req, res) => {
  const { nickname, isPublic } = req.body;
  if (!validID(req.params.id) || typeof nickname !== 'string' || nickname.trim().length < 2 || nickname.trim().length > 24 || /[\x00-\x1f\x7f]/.test(nickname) || typeof isPublic !== 'boolean') return res.status(400).json({ error: 'Use a 2–24 character nickname and choose leaderboard visibility' });
  const p = await players.findOneAndUpdate({ _id: req.params.id }, { $set: { nickname: nickname.trim(), isPublic, nameConfirmed: true } }, { returnDocument: 'after' });
  if (!p) return res.status(404).json({ error: 'Player not found' });
  res.json(publicPlayer(p));
}));
app.get('/api/players/:id/bests', auth, asyncRoute(async (req, res) => {
  if (!validID(req.params.id)) return res.status(400).json({ error: 'Invalid player' });
  const results = await runs.aggregate([{ $match: { playerID: req.params.id } }, { $group: { _id: '$difficulty', score: { $max: '$score' } } }]).toArray();
  res.json(Object.fromEntries(results.map(r => [r._id, r.score])));
}));
const modes = ['Chill', 'Arcade', 'Tennis'];
const gameFor = mode => mode === 'Tennis' ? 'Tennis' : 'Neon Rush';
const bestRun = (playerID, difficulty) => runs.find({ playerID, difficulty }).sort({ score: -1, createdAt: 1, _id: 1 }).limit(1).next();
async function rankedBoard(difficulty) {
  return runs.aggregate([
    { $match: { difficulty } }, { $sort: { score: -1, createdAt: 1, _id: 1 } },
    { $group: { _id: '$playerID', score: { $first: '$score' }, accuracy: { $first: '$accuracy' }, bestCombo: { $first: '$bestCombo' }, achievedAt: { $first: '$createdAt' } } },
    { $lookup: { from: 'players', localField: '_id', foreignField: '_id', as: 'player' } }, { $unwind: '$player' }, { $match: { 'player.isPublic': true } },
    { $sort: { score: -1, achievedAt: 1, _id: 1 } }
  ]).toArray();
}
const publicRow = (row, index) => ({ rank: index + 1, nickname: row.player.nickname, score: row.score, accuracy: row.accuracy, bestCombo: row.bestCombo });
async function standingFor(player, difficulty, board) {
  const best = await bestRun(player._id, difficulty);
  const index = board.findIndex(row => row._id === player._id);
  const targetIndex = index > 0 ? index - 1 : index === -1 ? board.length - 1 : -1;
  const target = player.isPublic && targetIndex >= 0 ? board[targetIndex] : null;
  return { difficulty, isPublic: player.isPublic, personalBest: best?.score ?? null,
    rank: index < 0 ? null : index + 1, totalPlayers: board.length,
    next: target ? { rank: targetIndex + 1, nickname: target.player.nickname, score: target.score,
      pointsNeeded: Math.max(1, target.score - (best?.score ?? 0) + 1) } : null };
}
app.get('/api/players/:id/standing', auth, asyncRoute(async (req, res) => {
  const difficulty = req.query.difficulty || 'Arcade';
  if (!validID(req.params.id) || !modes.includes(difficulty)) return res.status(400).json({ error: 'Invalid player or game' });
  const player = await players.findOne({ _id: req.params.id });
  if (!player) return res.status(404).json({ error: 'Player not found' });
  res.json(await standingFor(player, difficulty, await rankedBoard(difficulty)));
}));
app.post('/api/runs', auth, asyncRoute(async (req, res) => {
  const b = req.body;
  const integer = (x, max) => Number.isInteger(x) && x >= 0 && x <= max;
  if (!validID(b.id) || !validID(b.playerID) || !modes.includes(b.difficulty) || (b.game != null && b.game !== gameFor(b.difficulty)) || !integer(b.score, 1000000) || !integer(b.cuts, 1000) || !integer(b.bestCombo, b.cuts) || !integer(b.accuracy, 100) || typeof b.completed !== 'boolean' || b.isDemo !== false || typeof b.gameVersion !== 'string' || b.gameVersion.length > 40) return res.status(400).json({ error: 'Invalid run; demos and scripted runs are not ranked' });
  const player = await players.findOne({ _id: b.playerID });
  if (!player) return res.status(404).json({ error: 'Player not found' });
  const run = { _id: b.id, playerID: b.playerID, game: b.game || gameFor(b.difficulty), difficulty: b.difficulty, score: b.score, cuts: b.cuts, bestCombo: b.bestCombo, accuracy: b.accuracy, completed: b.completed, gameVersion: b.gameVersion, stationID: config.stationID };
  const previous = await bestRun(b.playerID, b.difficulty);
  try { await runs.insertOne({ ...run, previousBest: previous ? { score: previous.score, achievedAt: previous.createdAt } : null, createdAt: new Date() }); }
  catch (e) {
    if (e.code !== 11000) throw e;
    const existing = await runs.findOne({ _id: b.id });
    if (Object.keys(run).some(k => (k === 'game' ? existing[k] || gameFor(existing.difficulty) : existing[k]) !== run[k])) return res.status(409).json({ error: 'Run ID already used with different data' });
  }
  let stored = await runs.findOne({ _id: b.id });
  if (!stored.receipt) {
    const board = await rankedBoard(b.difficulty);
    const standing = await standingFor(player, b.difficulty, board);
    const old = stored.previousBest;
    const oldBoard = old && player.isPublic ? [...board.filter(row => row._id !== player._id), { _id: player._id, score: old.score, achievedAt: old.achievedAt }]
      .sort((a, b) => b.score - a.score || new Date(a.achievedAt) - new Date(b.achievedAt) || a._id.localeCompare(b._id)) : [];
    const previousRank = oldBoard.length ? oldBoard.findIndex(row => row._id === player._id) + 1 : null;
    const newPersonalBest = old == null || b.score > old.score;
    const progress = { runID: b.id, playerID: b.playerID, newPersonalBest, previousBest: old?.score ?? null, previousRank,
      placesClimbed: newPersonalBest && previousRank && standing.rank ? Math.max(0, previousRank - standing.rank) : 0, standing };
    // Retain the receipt so an offline retry cannot award the same climb again with different numbers.
    await runs.updateOne({ _id: b.id, receipt: { $exists: false } }, { $set: { receipt: progress } });
    stored = await runs.findOne({ _id: b.id });
  }
  res.json({ saved: true, progress: stored.receipt });
}));
app.get('/api/leaderboard', asyncRoute(async (req, res) => {
  const difficulty = req.query.difficulty || 'Arcade';
  if (!modes.includes(difficulty)) return res.status(400).json({ error: 'Invalid difficulty' });
  const board = await rankedBoard(difficulty);
  res.json({ difficulty, totalPlayers: board.length, rows: board.slice(0, 100).map(publicRow) });
}));
app.use(express.static(path.join(root, 'public')));
app.use((err, req, res, next) => { res.status(err.status === 400 ? 400 : 500).json({ error: err.status === 400 ? 'Invalid request' : 'Database request failed; try again' }); });
const server = app.listen(port, host, () => console.log(`Aircade API and leaderboard: ${stationURL}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(async () => { await mongo.close(); process.exit(0); }));
