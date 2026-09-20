import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { loadStationConfig } from './station-config.mjs';

function temporaryConfig(t) {
  const directory = mkdtempSync(join(tmpdir(), 'aircade-launch-config-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  return join(directory, 'station.json');
}

test('Saved station port is honored and an explicit override preserves all station identity', t => {
  const configPath = temporaryConfig(t);
  const original = { url: 'http://127.0.0.1:8794', token: 'test-token', stationID: 'test-station', badgeSecret: 'test-badge-secret', extra: 'preserved' };
  writeFileSync(configPath, JSON.stringify(original), { mode: 0o600 });
  const saved = loadStationConfig({ configPath, env: {} });
  assert.equal(saved.port, 8794); assert.equal(saved.host, '127.0.0.1');
  assert.deepEqual(saved.config, original);
  const changed = loadStationConfig({ configPath, env: { PORT: '8799' } });
  assert.equal(changed.url, 'http://127.0.0.1:8799');
  assert.deepEqual(JSON.parse(readFileSync(configPath)), { ...original, url: changed.url });
  assert.equal(statSync(configPath).mode & 0o777, 0o600);
});

test('New configuration defaults to 8787 or the requested port and prints no secrets', t => {
  const configPath = temporaryConfig(t);
  const result = loadStationConfig({ configPath, env: {} });
  assert.equal(result.port, 8787); assert.equal(result.config.url, 'http://127.0.0.1:8787');
  assert.ok(result.config.token); assert.ok(result.config.badgeSecret); assert.ok(result.config.stationID);
  const cli = spawnSync(process.execPath, ['station-config.mjs'], { cwd: import.meta.dirname,
    env: { ...process.env, HOST: '127.0.0.1', PORT: '8795', AIRCADE_STATION_CONFIG: configPath }, encoding: 'utf8' });
  assert.equal(cli.status, 0, cli.stderr);
  assert.deepEqual(cli.stdout.trim().split('\t'), ['127.0.0.1', '8795', 'http://127.0.0.1:8795', configPath]);
  assert.ok(!cli.stdout.includes(result.config.token)); assert.ok(!cli.stdout.includes(result.config.badgeSecret));
});

test('Malformed URL, null configuration and invalid ports cannot overwrite station credentials', t => {
  const configPath = temporaryConfig(t);
  const original = JSON.stringify({ url: 'http://127.0.0.1:8794', token: 'preserve-me' });
  writeFileSync(configPath, original);
  for (const PORT of ['0', '65536', 'not-a-port']) {
    assert.throws(() => loadStationConfig({ configPath, env: { PORT } }), /PORT/);
    assert.equal(readFileSync(configPath, 'utf8'), original);
  }
  for (const json of ['null', JSON.stringify({ url: 'http://secret:credential@localhost:8794' })]) {
    writeFileSync(configPath, json);
    assert.throws(() => loadStationConfig({ configPath, env: {} }));
    assert.equal(readFileSync(configPath, 'utf8'), json);
  }
});
