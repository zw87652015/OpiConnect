// Self-contained test for index.mjs: generates a P-256 APNs key, stubs APNs over h2c,
// spawns the server with APNS_URL pointing at the stub, exercises the API.
// Usage: node --test server/test.mjs   (Node 22, built-ins only)
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import http2 from 'node:http2';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const b64uJson = s => JSON.parse(Buffer.from(s, 'base64url').toString('utf8'));
const decodeProtectedHeader = jwt => b64uJson(jwt.split('.')[0]);
// Verify an ES256 JWT with a PKCS8 PEM private key's public counterpart; checks iss.
async function jwtVerify(jwt, p8pem, { iss }) {
  const [h, c, sig] = jwt.split('.');
  const claims = b64uJson(c);
  assert.equal(claims.iss, iss);
  const key = crypto.createPublicKey(p8pem);
  return crypto.verify('sha256', Buffer.from(`${h}.${c}`), { key, dsaEncoding: 'ieee-p1363' }, Buffer.from(sig, 'base64url'));
}

const SERVER = path.join(path.dirname(fileURLToPath(import.meta.url)), 'index.mjs');
const PAIR_ID = 'A'.repeat(22);
const SECRET = 's'.repeat(43);
const TOKEN = 'ab'.repeat(32); // 64 hex chars

let tmp, stub, stubPort, port, proc;
const apnsRequests = []; // {headers, body}
let stubStatus = 200, stubReason = '';

function freePort() {
  return new Promise((resolve, reject) => {
    const s = http2.createServer();
    s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)); });
    s.on('error', reject);
  });
}

const post = (route, body) => fetch(`http://127.0.0.1:${port}${route}`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body),
}).then(async r => ({ status: r.status, json: await r.json().catch(() => null) }));

const register = (over = {}) => post('/v1/register', { pairId: PAIR_ID, secret: SECRET, token: TOKEN, env: 'sandbox', ...over });
const pairingsFile = () => path.join(tmp, 'data', 'pairings.json');
const pairings = () => JSON.parse(fs.readFileSync(pairingsFile(), 'utf8'));

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'opipush-test-'));
  fs.mkdirSync(path.join(tmp, 'data'));
  const { privateKey } = crypto.generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const p8 = privateKey.export({ type: 'pkcs8', format: 'pem' });
  fs.writeFileSync(path.join(tmp, 'AuthKey.p8'), p8);

  stubPort = await freePort();
  stub = http2.createServer();
  stub.on('stream', (stream, headers) => {
    let body = '';
    stream.on('data', c => { body += c; });
    stream.on('end', () => {
      apnsRequests.push({ headers, body });
      stream.respond({ ':status': stubStatus, 'content-type': 'application/json' });
      stream.end(JSON.stringify(stubReason ? { reason: stubReason } : {}));
    });
  });
  await new Promise(r => stub.listen(stubPort, '127.0.0.1', r));

  port = await freePort();
  proc = spawn(process.execPath, [SERVER], {
    env: {
      ...process.env,
      APNS_KEY_FILE: path.join(tmp, 'AuthKey.p8'),
      APNS_KEY_ID: 'TESTKEYID1',
      APNS_TEAM_ID: 'TEAMID1234',
      APNS_TOPIC: 'com.example.opiconnect.watchkitapp',
      APNS_ENV: 'production',
      APNS_URL: `http://127.0.0.1:${stubPort}`,
      DATA_DIR: path.join(tmp, 'data'),
      PORT: String(port),
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  proc.stderr.on('data', d => process.stderr.write(`[server] ${d}`));
  // wait for healthz
  for (let i = 0; i < 50; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/healthz`);
      if (r.ok) break;
    } catch {}
    await new Promise(r => setTimeout(r, 100));
    if (i === 49) throw new Error('server did not start');
  }
});

after(() => {
  proc?.kill();
  stub?.close();
  fs.rmSync(tmp, { recursive: true, force: true });
});

test('healthz returns ok', async () => {
  const r = await fetch(`http://127.0.0.1:${port}/healthz`);
  assert.equal(r.status, 200);
  assert.equal(await r.text(), 'ok');
});

test('register validates input', async () => {
  for (const [label, body] of [
    ['bad pairId', { pairId: 'short', secret: SECRET, token: TOKEN }],
    ['bad secret', { pairId: PAIR_ID, secret: 'nope', token: TOKEN }],
    ['bad token', { pairId: PAIR_ID, secret: SECRET, token: 'xyz' }],
    ['bad env', { pairId: PAIR_ID, secret: SECRET, token: TOKEN, env: 'staging' }],
  ]) {
    const r = await post('/v1/register', body);
    assert.equal(r.status, 400, label);
  }
  assert.equal(fs.existsSync(pairingsFile()), false, 'no pairing stored');
});

test('register TOFU, wrong-secret 401, update', async () => {
  let r = await register();
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { ok: true });
  let rec = pairings()[PAIR_ID];
  assert.equal(rec.token, TOKEN);
  assert.equal(rec.env, 'sandbox');
  assert.equal(rec.secretHash, crypto.createHash('sha256').update(SECRET).digest('hex'));

  r = await register({ secret: 'x'.repeat(43) });
  assert.equal(r.status, 401);

  const newToken = 'cd'.repeat(32);
  r = await register({ token: newToken, env: 'production' });
  assert.equal(r.status, 200);
  rec = pairings()[PAIR_ID];
  assert.equal(rec.token, newToken);
  assert.equal(rec.env, 'production');
});

test('push alert hits stub with correct path, headers, payload and JWT', async () => {
  apnsRequests.length = 0;
  const c = 'ciphertext_123';
  const r = await post('/v1/push', { pairId: PAIR_ID, secret: SECRET, kind: 'alert', id: 'notif1', c });
  assert.equal(r.status, 200);
  assert.deepEqual(r.json, { ok: true });
  assert.equal(apnsRequests.length, 1);
  const { headers, body } = apnsRequests[0];
  assert.equal(headers[':path'], `/3/device/${'cd'.repeat(32)}`);
  assert.equal(headers['apns-topic'], 'com.example.opiconnect.watchkitapp');
  assert.equal(headers['apns-push-type'], 'alert');
  assert.equal(headers['apns-priority'], '10');
  assert.equal(headers['apns-collapse-id'], 'notif1');
  assert.ok(Number(headers['apns-expiration']) > Math.floor(Date.now() / 1000) + 86000);
  assert.deepEqual(JSON.parse(body), {
    aps: { alert: { title: 'OpiLink', body: 'New notification' }, 'mutable-content': 1, sound: 'default' },
    c,
  });
  const auth = headers['authorization'];
  assert.match(auth, /^bearer /);
  const jwt = auth.slice(7);
  const header = decodeProtectedHeader(jwt);
  assert.equal(header.alg, 'ES256');
  assert.equal(header.kid, 'TESTKEYID1');
  // verify signature with the generated key and the iss claim
  assert.ok(await jwtVerify(jwt, fs.readFileSync(path.join(tmp, 'AuthKey.p8'), 'utf8'), { iss: 'TEAMID1234' }));
});

test('push remove is a background push', async () => {
  apnsRequests.length = 0;
  const r = await post('/v1/push', { pairId: PAIR_ID, secret: SECRET, kind: 'remove', id: 'notif1', c: 'abc' });
  assert.equal(r.status, 200);
  const { headers, body } = apnsRequests[0];
  assert.equal(headers['apns-push-type'], 'background');
  assert.equal(headers['apns-priority'], '5');
  assert.equal(headers['apns-collapse-id'], undefined);
  assert.ok(Number(headers['apns-expiration']) <= Math.floor(Date.now() / 1000) + 3600);
  assert.deepEqual(JSON.parse(body), { aps: { 'content-available': 1 }, c: 'abc' });
});

test('push unknown pairId -> 404', async () => {
  const r = await post('/v1/push', { pairId: 'B'.repeat(22), secret: SECRET, kind: 'alert', id: 'x', c: 'abc' });
  assert.equal(r.status, 404);
  assert.equal(r.json.error, 'not registered');
});

test('push validates kind, id, c', async () => {
  for (const body of [
    { pairId: PAIR_ID, secret: SECRET, kind: 'x', id: 'a', c: 'abc' },
    { pairId: PAIR_ID, secret: SECRET, kind: 'alert', id: 'has space', c: 'abc' },
    { pairId: PAIR_ID, secret: SECRET, kind: 'alert', id: 'a', c: '' },
    { pairId: PAIR_ID, secret: SECRET, kind: 'alert', id: 'a', c: 'a'.repeat(3001) },
  ]) {
    assert.equal((await post('/v1/push', body)).status, 400, JSON.stringify(body));
  }
});

test('APNs 410 -> server 410 and pairing deleted', async () => {
  stubStatus = 410;
  const r = await post('/v1/push', { pairId: PAIR_ID, secret: SECRET, kind: 'alert', id: 'x', c: 'abc' });
  stubStatus = 200;
  assert.equal(r.status, 410);
  assert.equal(r.json.error, 'gone');
  assert.equal(pairings()[PAIR_ID], undefined);
});

test('unregister deletes pairing', async () => {
  await register();
  let r = await post('/v1/unregister', { pairId: PAIR_ID, secret: 'x'.repeat(43) });
  assert.equal(r.status, 401);
  r = await post('/v1/unregister', { pairId: PAIR_ID, secret: SECRET });
  assert.equal(r.status, 200);
  assert.equal(pairings()[PAIR_ID], undefined);
});
