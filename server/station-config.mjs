import { mkdirSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { randomBytes, randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const defaultPath = fileURLToPath(new URL('../.local/station.json', import.meta.url));

// The native app and station must agree about the endpoint. Preserve identity
// and credentials when an explicit PORT/HOST changes that endpoint.
export function loadStationConfig({ env = process.env, configPath = env.AIRCADE_STATION_CONFIG || defaultPath } = {}) {
  configPath = resolve(configPath);
  let config, exists = true;
  try { config = JSON.parse(readFileSync(configPath, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw new Error('Station configuration could not be read; preserve it and repair the JSON before starting.');
    exists = false;
  }
  if (exists && (!config || typeof config !== 'object' || Array.isArray(config))) throw new Error('Station configuration must be an object.');
  let savedURL;
  if (config?.url != null) {
    try { savedURL = new URL(config.url); } catch { throw new Error('Station configuration has an invalid URL.'); }
    if (savedURL.protocol !== 'http:' || savedURL.username || savedURL.password || savedURL.search || savedURL.hash || savedURL.pathname !== '/') {
      throw new Error('Local station URL must be an HTTP origin without credentials or a path.');
    }
  }
  const host = (env.HOST?.trim() || savedURL?.hostname || '127.0.0.1').replace(/^\[|\]$/g, '');
  if (!/^[a-zA-Z0-9_.:-]+$/.test(host)) throw new Error('HOST must be a valid station hostname or IP address.');
  const portText = env.PORT?.trim() || savedURL?.port || (savedURL ? '80' : '8787');
  const port = Number(portText);
  if (!/^\d+$/.test(portText) || !Number.isInteger(port) || port < 1 || port > 65535) throw new Error('PORT must be an integer from 1 to 65535.');
  const clientHost = ['0.0.0.0', '::'].includes(host) ? '127.0.0.1' : host;
  const address = clientHost.includes(':') ? `[${clientHost}]` : clientHost;
  const url = new URL(`http://${address}:${port}`).origin;
  const created = !config;
  if (!config) config = { url, token: randomBytes(32).toString('hex'), stationID: randomUUID(), badgeSecret: randomBytes(32).toString('hex') };
  if (created || config.url !== url) {
    config = { ...config, url };
    mkdirSync(dirname(configPath), { recursive: true, mode: 0o700 });
    const temporary = `${configPath}.${randomUUID()}.tmp`;
    writeFileSync(temporary, JSON.stringify(config, null, 2), { mode: 0o600, flag: 'wx' });
    renameSync(temporary, configPath);
  }
  return { config, configPath, host, port, url };
}

// Only non-secret launch fields are printed. Never evaluate shell text from a
// config file; start-station.sh reads these tab-separated fields as plain data.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const { host, port, url, configPath } = loadStationConfig();
    if (/[\t\r\n]/.test(configPath)) throw new Error('Station configuration path cannot contain tabs or newlines.');
    console.log([host, port, url, configPath].join('\t'));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
