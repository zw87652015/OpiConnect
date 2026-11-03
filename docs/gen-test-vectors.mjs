// Generates docs/test-vectors.json for docs/PROTOCOL.md and self-verifies by decrypting.
// Node 22, built-ins only. Usage: node gen-test-vectors.mjs
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const b64u = b => Buffer.from(b).toString('base64url');
const hex = b => Buffer.from(b).toString('hex');

// HKDF-SHA256, ikm=K, zero-length salt (== HashLen zero bytes per RFC 5869), info=ASCII.
function hkdf(ikm, info, len) {
  return Buffer.from(crypto.hkdfSync('sha256', ikm, Buffer.alloc(0), Buffer.from(info, 'ascii'), len));
}

function seal(key, nonce, plaintext) {
  const c = crypto.createCipheriv('aes-256-gcm', key, nonce);
  const body = Buffer.concat([c.update(plaintext, 'utf8'), c.final()]);
  return Buffer.concat([nonce, body, c.getAuthTag()]);
}

function open(key, sealed) {
  const nonce = sealed.subarray(0, 12);
  const tag = sealed.subarray(sealed.length - 16);
  const body = sealed.subarray(12, sealed.length - 16);
  const d = crypto.createDecipheriv('aes-256-gcm', key, nonce);
  d.setAuthTag(tag);
  return Buffer.concat([d.update(body), d.final()]).toString('utf8');
}

const notifId = key => b64u(crypto.createHash('sha256').update(key, 'utf8').digest()).slice(0, 22);

function chunks(sealed, maxLen) {
  const out = [];
  for (let off = 0; off < sealed.length; off += maxLen - 1) {
    const part = sealed.subarray(off, off + maxLen - 1);
    const last = off + maxLen - 1 >= sealed.length;
    out.push(Buffer.concat([Buffer.from([last ? 0x00 : 0x01]), part]));
  }
  return out;
}

const K = Buffer.alloc(32);
for (let i = 0; i < 32; i++) K[i] = i;

const pairId = b64u(hkdf(K, 'opi/id', 16));
const secret = b64u(hkdf(K, 'opi/auth', 32));
const encKey = hkdf(K, 'opi/enc', 32);

const sealInputs = [
  { nonce: Buffer.from([...Array(12).keys()]), plaintext: JSON.stringify({ i: 'AbCdEfGhIjKlMnOpQrStUv', p: 'com.example.chat', a: '示例应用', t: '新消息', b: '你好 👋 晚上一起吃饭吗？', w: 1730000000000, x: [{ l: '回复', r: true }, { l: '标为已读', r: false }] }) },
  { nonce: Buffer.from([...Array(12).keys()].map(i => 0xa0 + i)), plaintext: '{"type":"hello","state":"active"}' },
];

const sealVectors = sealInputs.map(({ nonce, plaintext }) => {
  const sealed = seal(encKey, nonce, plaintext);
  const back = open(encKey, sealed);
  if (back !== plaintext) throw new Error('self-check failed: roundtrip mismatch');
  return { nonceHex: hex(nonce), plaintext, sealedBase64url: b64u(sealed) };
});

const sbnKey = '0|com.whatsapp|1|null|10123';
const idVector = { sbnKey, id: notifId(sbnKey) };

// Chunk the sealed bytes of seal vector (b) at maxLen = 20.
const sealedB = Buffer.from(sealVectors[1].sealedBase64url, 'base64url');
const chunkList = chunks(sealedB, 20);
// Self-verify: reassemble and decrypt.
const reassembled = Buffer.concat(chunkList.map(c => c.subarray(1)));
if (!reassembled.equals(sealedB)) throw new Error('self-check failed: chunk reassembly');
if (chunkList.at(-1)[0] !== 0x00 || chunkList.slice(0, -1).some(c => c[0] !== 0x01)) throw new Error('self-check failed: chunk flags');
if (open(encKey, reassembled) !== sealVectors[1].plaintext) throw new Error('self-check failed: chunk decrypt');

const vectors = {
  description: 'OpiConnect crypto test vectors (docs/PROTOCOL.md). base64url = RFC 4648 url-safe, no padding. K = bytes 0x00..0x1f.',
  masterKeyHex: hex(K),
  qr: `opi1:${b64u(K)}`,
  pairId,
  secret,
  encKeyHex: hex(encKey),
  seal: sealVectors,
  notificationId: idVector,
  chunking: { maxLen: 20, source: 'seal[1]', chunksHex: chunkList.map(hex) },
};

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), 'test-vectors.json');
fs.writeFileSync(out, JSON.stringify(vectors, null, 2) + '\n');
console.log(`wrote ${out}`);
console.log(JSON.stringify(vectors, null, 2));
