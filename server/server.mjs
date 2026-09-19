import express from 'express';
import { MongoClient } from 'mongodb';
import { createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.dirname(fileURLToPath(import.meta.url));
const local = path.join(root, '..', '.local');
mkdirSync(local, { recursive: true, mode: 0o700 });
const configPath = path.join(local, 'station.json');
let config;
try { config = JSON.parse(readFileSync(configPath)); }
catch (error) {
  if (error.code !== 'ENOENT') throw error;
  config = { url: 'http://127.0.0.1:8787', token: randomBytes(32).toString('hex'), stationID: randomUUID(), badgeSecret: randomBytes(32).toString('hex') };
  writeFileSync(configPath, JSON.stringify(config, null, 2), { mode: 0o600 });
}
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
app.get('/api/health', asyncRoute(async (_, res) => { await db.command({ ping: 1 }); res.json({ ok: true }); }));
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
app.post('/api/runs', auth, asyncRoute(async (req, res) => {
  const b = req.body;
  const integer = (x, max) => Number.isInteger(x) && x >= 0 && x <= max;
  if (!validID(b.id) || !validID(b.playerID) || !['Chill', 'Arcade', 'Tennis'].includes(b.difficulty) || (b.game != null && !['Neon Rush', 'Tennis'].includes(b.game)) || !integer(b.score, 1000000) || !integer(b.cuts, 1000) || !integer(b.bestCombo, b.cuts) || !integer(b.accuracy, 100) || typeof b.completed !== 'boolean' || b.isDemo !== false || typeof b.gameVersion !== 'string' || b.gameVersion.length > 40) return res.status(400).json({ error: 'Invalid run; demos and scripted runs are not ranked' });
  if (!await players.findOne({ _id: b.playerID })) return res.status(404).json({ error: 'Player not found' });
  const run = { _id: b.id, playerID: b.playerID, game: b.game || 'Neon Rush', difficulty: b.difficulty, score: b.score, cuts: b.cuts, bestCombo: b.bestCombo, accuracy: b.accuracy, completed: b.completed, gameVersion: b.gameVersion, stationID: config.stationID };
  try { await runs.insertOne({ ...run, createdAt: new Date() }); }
  catch (e) {
    if (e.code !== 11000) throw e;
    const existing = await runs.findOne({ _id: b.id });
    if (Object.keys(run).some(k => (k === 'game' ? existing[k] || 'Neon Rush' : existing[k]) !== run[k])) return res.status(409).json({ error: 'Run ID already used with different data' });
  }
  res.json({ saved: true });
}));
app.get('/api/leaderboard', asyncRoute(async (req, res) => {
  const difficulty = req.query.difficulty || 'Arcade';
  if (!['Chill', 'Arcade', 'Tennis'].includes(difficulty)) return res.status(400).json({ error: 'Invalid difficulty' });
  const rows = await runs.aggregate([
    { $match: { difficulty } }, { $sort: { score: -1, createdAt: 1, _id: 1 } },
    { $group: { _id: '$playerID', score: { $first: '$score' }, accuracy: { $first: '$accuracy' }, bestCombo: { $first: '$bestCombo' }, achievedAt: { $first: '$createdAt' } } },
    { $lookup: { from: 'players', localField: '_id', foreignField: '_id', as: 'player' } }, { $unwind: '$player' }, { $match: { 'player.isPublic': true } },
    { $sort: { score: -1, achievedAt: 1, _id: 1 } }, { $limit: 100 },
    { $project: { _id: 0, nickname: '$player.nickname', score: 1, accuracy: 1, bestCombo: 1 } }
  ]).toArray();
  res.json({ difficulty, rows: rows.map((row, index) => ({ rank: index + 1, ...row })) });
}));
app.use(express.static(path.join(root, 'public')));
app.use((err, req, res, next) => { res.status(err.status === 400 ? 400 : 500).json({ error: err.status === 400 ? 'Invalid request' : 'Database request failed; try again' }); });
const port = Number(process.env.PORT || 8787), host = process.env.HOST || '127.0.0.1';
const server = app.listen(port, host, () => console.log(`Aircade API and leaderboard: http://${host}:${port}`));
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => server.close(async () => { await mongo.close(); process.exit(0); }));
