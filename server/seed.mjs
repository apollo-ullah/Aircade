import crypto from 'node:crypto';
import { MongoClient } from 'mongodb';

const FIXTURE = 'leaderboard-demo-v1';
const mongo = new MongoClient(process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017', {
  serverSelectionTimeoutMS: 5000,
});
const dbName = process.env.MONGODB_DB || 'aircade';
const stationID = process.env.STATION_ID || 'local-demo-station';

const players = [
  { _id: '00000000-0000-4000-8000-000000000101', nickname: 'Test Ace', avatarColor: 'aqua' },
  { _id: '00000000-0000-4000-8000-000000000102', nickname: 'Test Rally', avatarColor: 'orange' },
  { _id: '00000000-0000-4000-8000-000000000103', nickname: 'Test Rookie', avatarColor: 'lime' },
].map((player, index) => ({
  ...player,
  badgeKey: crypto.createHash('sha256').update(`aircade-${FIXTURE}-${index}`).digest('hex'),
  isPublic: true,
  nameConfirmed: true,
  createdAt: new Date(`2026-09-19T14:0${index}:00.000Z`),
  metadata: {
    fixture: FIXTURE,
    event: 'Hack the North',
    profileSource: 'local-seed',
    avatarColor: player.avatarColor,
  },
}));

const run = (suffix, playerIndex, difficulty, score, accuracy, bestCombo, minute, scenario) => ({
  _id: `00000000-0000-4000-8000-${String(suffix).padStart(12, '0')}`,
  playerID: players[playerIndex]._id,
  difficulty,
  score,
  cuts: Math.round(score / 100),
  bestCombo,
  accuracy,
  completed: true,
  gameVersion: 'seed-1.0',
  stationID,
  createdAt: new Date(`2026-09-19T15:${String(minute).padStart(2, '0')}:00.000Z`),
  metadata: {
    fixture: FIXTURE,
    input: 'simulated-test-run',
    scenario,
  },
});

const runs = [
  run(201, 0, 'Arcade', 8400, 0.94, 31, 1, 'public-arcade-best'),
  run(202, 0, 'Arcade', 6200, 0.82, 18, 2, 'older-lower-score'),
  run(203, 0, 'Chill', 7600, 0.96, 35, 3, 'public-chill-score'),
  run(204, 1, 'Arcade', 6900, 0.88, 24, 4, 'public-arcade-score'),
  run(205, 1, 'Chill', 9100, 0.98, 42, 5, 'public-chill-best'),
  run(206, 2, 'Arcade', 4200, 0.72, 12, 6, 'public-arcade-score'),
  run(207, 2, 'Chill', 5100, 0.79, 15, 7, 'public-chill-score'),
];

try {
  await mongo.connect();
  const db = mongo.db(dbName);

  if (process.argv.includes('--remove')) {
    const runResult = await db.collection('runs').deleteMany({ 'metadata.fixture': FIXTURE });
    const playerResult = await db.collection('players').deleteMany({ 'metadata.fixture': FIXTURE });
    console.log(`Removed ${playerResult.deletedCount} test profiles and ${runResult.deletedCount} test runs from ${dbName}.`);
  } else {
    for (const player of players) {
      await db.collection('players').replaceOne({ _id: player._id }, player, { upsert: true });
    }
    for (const gameRun of runs) {
      await db.collection('runs').replaceOne({ _id: gameRun._id }, gameRun, { upsert: true });
    }
    console.log(`Seeded ${players.length} test profiles and ${runs.length} test runs into ${dbName}.`);
    console.log(`Fixture label: metadata.fixture = ${FIXTURE}`);
  }
} finally {
  await mongo.close();
}
