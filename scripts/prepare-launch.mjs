import { createHash } from 'node:crypto';
import { chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Native apps should not open a protected Documents file while drawing their UI.
// Keep station credentials local and scoped to this checkout, outside the app bundle.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const source = process.env.AIRCADE_STATION_CONFIG || join(root, '.local', 'station.json');
const config = JSON.parse(await readFile(source, 'utf8'));
if (typeof config.url !== 'string' || typeof config.token !== 'string' || !config.token) {
  throw new Error('Station configuration is incomplete. Run scripts/start-station.sh first.');
}
const hash = createHash('sha256').update(root, 'utf8').digest('hex').slice(0, 16);
const directory = join(homedir(), 'Library', 'Application Support', 'Aircade', 'Stations');
await mkdir(directory, { recursive: true, mode: 0o700 });
const target = join(directory, `${hash}.json`);
const temporary = `${target}.${process.pid}.tmp`;
await writeFile(temporary, JSON.stringify({ url: config.url, token: config.token }) + '\n', { mode: 0o600 });
await rename(temporary, target);
await chmod(target, 0o600);
console.log(`Local station configuration prepared for this checkout (${hash}).`);
