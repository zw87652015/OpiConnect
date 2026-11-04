// OpiConnect push relay: forwards encrypted notification payloads to APNs.
// The watch registers its device token under pairId; Android posts sealed ciphertext to /v1/push.
// The relay never sees plaintext or the encryption key. See docs/PROTOCOL.md.
import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import http2 from 'node:http2';
import path from 'node:path';

const env = process.env;
const required = ['APNS_KEY_FILE', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC', 'DATA_DIR'];
const missing = required.filter(k => !env[k]);
if (missing.length) {
  console.error(`missing env vars: ${missing.join(', ')} (see server/README.md)`);
  process.exit(1);
}
const config = {
  port: Number(env.PORT || 8788),
  host: env.HOST || '127.0.0.1',
  keyId: env.APNS_KEY_ID,
  teamId: env.APNS_TEAM_ID,
  topic: env.APNS_TOPIC,
  defaultEnv: env.APNS_ENV || 'production',
  dataDir: env.DATA_DIR,
  apnsUrl: env.APNS_URL || '', // test-only override: one base URL for all envs
};
if (!['production', 'sandbox'].includes(config.defaultEnv)) {
  console.error('APNS_ENV must be production or sandbox');
  process.exit(1);
}
const apnsKey = fs.readFileSync(env.APNS_KEY_FILE, 'utf8');
crypto.createPrivateKey(apnsKey);

const LIMIT = 8 * 1024;
const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const ENVS = ['production', 'sandbox'];
const HOSTS = { production: 'https://api.push.apple.com', sandbox: 'https://api.sandbox.push.apple.com' };
const DEAD_REASONS = ['BadDeviceToken', 'DeviceTokenNotForTopic'];
const PAIR_ID_RE = /^[A-Za-z0-9_-]{22}$/;
const SECRET_RE = /^[A-Za-z0-9_-]{43}$/;
const TOKEN_RE = /^[0-9a-f]{64,200}$/i;
const NOTIF_ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const CIPHERTEXT_RE = /^[A-Za-z0-9_-]{1,3000}$/;

/* ---------- storage ---------- */

const file = path.join(config.dataDir, 'pairings.json');
fs.mkdirSync(config.dataDir, { recursive: true, mode: 0o700 });
let regs = {};
try { regs = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { if (e.code !== 'ENOENT') throw e; }

function save() {
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(regs), { mode: 0o600 });
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, file);
}

const sha = s => crypto.createHash('sha256').update(s).digest();
const secretOk = (reg, secret) => typeof secret === 'string' && crypto.timingSafeEqual(sha(secret), Buffer.from(reg.secretHash, 'hex'));
const lookup = pairId => (typeof pairId === 'string' && Object.hasOwn(regs, pairId)) ? regs[pairId] : null;

/* ---------- rate limits (fixed windows, in memory) ---------- */

const windows = new Map();
function hit(key, limit, ms) {
  const now = Date.now();
  let w = windows.get(key);
  if (!w || now >= w.reset) { w = { count: 0, reset: now + ms }; windows.set(key, w); }
  return ++w.count <= limit;
}
setInterval(() => {
  const now = Date.now();
  for (const [k, w] of windows) if (now >= w.reset) windows.delete(k);
}, MIN).unref();

/* ---------- APNs ---------- */

let jwtCache = null;
function providerToken(force) {
  const now = Math.floor(Date.now() / 1000);
  if (!force && jwtCache && now - jwtCache.iat < 50 * 60) return jwtCache.jwt;
  const head = Buffer.from(JSON.stringify({ alg: 'ES256', kid: config.keyId })).toString('base64url');
  const claims = Buffer.from(JSON.stringify({ iss: config.teamId, iat: now })).toString('base64url');
  const input = `${head}.${claims}`;
  const sig = crypto.sign('sha256', Buffer.from(input), { key: apnsKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  jwtCache = { iat: now, jwt: `${input}.${sig}` };
  return jwtCache.jwt;
}

const sessions = new Map();
function session(envName) {
  let s = sessions.get(envName);
  if (s && !s.closed && !s.destroyed) return s;
  s = http2.connect(config.apnsUrl || HOSTS[envName]);
  const drop = () => { if (sessions.get(envName) === s) sessions.delete(envName); };
  s.on('error', drop);
  s.on('close', drop);
  s.on('goaway', () => { drop(); s.close(); });
  sessions.set(envName, s);
  return s;
}

function apnsPost(envName, headers, body) {
  return new Promise((resolve, reject) => {
    const req = session(envName).request({ ':method': 'POST', ...headers });
    let status = 0, data = '', done = false;
    const finish = (fn, v) => { if (!done) { done = true; clearTimeout(timer); fn(v); } };
    const timer = setTimeout(() => { req.close(http2.constants.NGHTTP2_CANCEL); finish(reject, new Error('APNs timeout')); }, 10000);
    req.setEncoding('utf8');
    req.on('response', h => { status = h[':status']; });
    req.on('data', c => { data += c; });
    req.on('end', () => {
      let reason = '';
      try { reason = JSON.parse(data).reason || ''; } catch {}
      finish(resolve, { status, reason });
    });
    req.on('error', e => finish(reject, e));
    req.end(body);
  });
}

// One APNs request. Retries once on a thrown (connection-level) error and refreshes the
// provider token once on ExpiredProviderToken.
async function apnsSend(envName, token, pushType, priority, payload, collapse, expireSec) {
  const body = JSON.stringify(payload);
  const headers = {
    ':path': `/3/device/${token}`,
    'apns-topic': config.topic,
    'apns-push-type': pushType,
    'apns-priority': String(priority),
    'apns-expiration': String(Math.floor(Date.now() / 1000) + expireSec),
    ...(collapse ? { 'apns-collapse-id': collapse } : {}),
    'content-type': 'application/json',
  };
  const post = jwt => apnsPost(envName, { ...headers, authorization: `bearer ${jwt}` }, body);
  let r;
  try {
    r = await post(providerToken(false));
  } catch {
    // NAT can drop the kept-open connection after hours of quiet; the first request on it then fails. Retry once on a new one.
    const stale = sessions.get(envName);
    if (stale) { sessions.delete(envName); stale.destroy(); }
    r = await post(providerToken(false));
  }
  if (r.status === 403 && r.reason === 'ExpiredProviderToken') r = await post(providerToken(true));
  return r;
}

/* ---------- HTTP ---------- */

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function clientIp(req) {
  const xff = String(req.headers['x-forwarded-for'] || '').split(',').map(s => s.trim()).filter(Boolean);
  return xff.at(-1) || req.socket.remoteAddress || '';
}

function json(res, status, obj) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', c => {
      size += c.length;
      if (size > LIMIT) return reject(new HttpError(413, 'body too large'));
      chunks.push(c);
    });
    req.on('error', reject);
    req.on('end', () => {
      if (size > LIMIT) return;
      try {
        const obj = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
        if (!obj || typeof obj !== 'object' || Array.isArray(obj)) throw new Error();
        resolve(obj);
      } catch {
        reject(new HttpError(400, 'invalid body'));
      }
    });
  });
}

async function register(ip, body) {
  if (!hit(`reg:${ip}`, 20, HOUR)) return [429, { error: 'too many requests' }];
  const { pairId, secret, token } = body;
  if (typeof pairId !== 'string' || !PAIR_ID_RE.test(pairId)) return [400, { error: 'invalid pairId' }];
  if (typeof secret !== 'string' || !SECRET_RE.test(secret)) return [400, { error: 'invalid secret' }];
  if (typeof token !== 'string' || !TOKEN_RE.test(token)) return [400, { error: 'invalid token' }];
  const envName = body.env ?? config.defaultEnv;
  if (!ENVS.includes(envName)) return [400, { error: 'invalid env' }];
  const now = Date.now();
  const old = lookup(pairId);
  if (old) {
    if (!secretOk(old, secret)) return [401, { error: 'invalid secret' }];
    old.token = token;
    old.env = envName;
    old.updated = now;
    save();
    console.log(`[register] ${pairId.slice(0, 6)} ${envName} updated`);
    return [200, { ok: true }];
  }
  regs[pairId] = { token, env: envName, secretHash: sha(secret).toString('hex'), created: now, updated: now };
  save();
  console.log(`[register] ${pairId.slice(0, 6)} ${envName} created`);
  return [200, { ok: true }];
}

async function push(ip, body) {
  const { pairId, secret, kind, id, c } = body;
  if (typeof pairId === 'string' && !hit(`push:${pairId}`, 120, MIN)) return [429, { error: 'too many requests' }];
  const reg = lookup(pairId);
  if (!reg) return [404, { error: 'not registered' }];
  if (!secretOk(reg, secret)) return [401, { error: 'invalid secret' }];
  if (kind !== 'alert' && kind !== 'remove') return [400, { error: 'invalid kind' }];
  if (typeof id !== 'string' || !NOTIF_ID_RE.test(id)) return [400, { error: 'invalid id' }];
  if (typeof c !== 'string' || !CIPHERTEXT_RE.test(c)) return [400, { error: 'invalid c' }];
  const tag = pairId.slice(0, 6);
  const alert = kind === 'alert';
  const payload = alert
    ? { aps: { alert: { title: 'OpiLink', body: 'New notification' }, 'mutable-content': 1, sound: 'default' }, c }
    : { aps: { 'content-available': 1 }, c };
  const r = await apnsSend(reg.env, reg.token, alert ? 'alert' : 'background', alert ? 10 : 5, payload, alert ? id : null, alert ? 86400 : 3600);
  if (r.status === 200) {
    console.log(`[push] ${tag} ${kind} ok`);
    return [200, { ok: true }];
  }
  if (r.status === 410 || (r.status === 400 && DEAD_REASONS.includes(r.reason))) {
    delete regs[pairId];
    save();
    console.log(`[push] ${tag} token dead (${r.reason || r.status}), pairing deleted`);
    return [410, { error: 'gone' }];
  }
  console.log(`[push] ${tag} APNs ${r.status} ${r.reason}`);
  return [502, { error: r.reason || `APNs ${r.status}` }];
}

async function unregister(ip, body) {
  const { pairId, secret } = body;
  const reg = lookup(pairId);
  if (!reg) return [200, { ok: true }];
  if (!secretOk(reg, secret)) return [401, { error: 'invalid secret' }];
  delete regs[pairId];
  save();
  console.log(`[unregister] ${pairId.slice(0, 6)}`);
  return [200, { ok: true }];
}

const ROUTES = { '/v1/register': register, '/v1/push': push, '/v1/unregister': unregister };

const server = http.createServer(async (req, res) => {
  try {
    const ip = clientIp(req);
    const { pathname } = new URL(req.url, 'http://localhost');
    if (!hit(`ip:${ip}`, 600, MIN)) return json(res, 429, { error: 'too many requests' });
    if (pathname === '/healthz') {
      if (req.method !== 'GET') return json(res, 405, { error: 'method not allowed' });
      res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      return res.end('ok');
    }
    const route = Object.hasOwn(ROUTES, pathname) ? ROUTES[pathname] : null;
    if (!route) return json(res, 404, { error: 'not found' });
    if (req.method !== 'POST') return json(res, 405, { error: 'method not allowed' });
    const body = await readBody(req);
    const [status, out] = await route(ip, body);
    json(res, status, out);
  } catch (e) {
    if (e instanceof HttpError) {
      if (e.status === 413) res.setHeader('connection', 'close');
      return json(res, e.status, { error: e.message });
    }
    console.error(`[error] ${e.message}`);
    if (!res.headersSent) json(res, 502, { error: e.message });
  }
});

server.listen(config.port, config.host, () => {
  console.log(`opiconnect push listening on ${config.host}:${config.port}, APNS_ENV=${config.defaultEnv}`);
});
