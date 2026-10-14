// Minimal Ethereum primitives for the BLACKOUT keeper. Node 22+, no dependencies.
// keccak-256, secp256k1 ECDSA (EIP-1559 signing), RLP and a tiny ABI encoder.
import { randomBytes } from 'node:crypto';

// ---------------------------------------------------------------- keccak-256
const RC = [
  0x0000000000000001n, 0x0000000000008082n, 0x800000000000808an, 0x8000000080008000n,
  0x000000000000808bn, 0x0000000080000001n, 0x8000000080008081n, 0x8000000000008009n,
  0x000000000000008an, 0x0000000000000088n, 0x0000000080008009n, 0x000000008000000an,
  0x000000008000808bn, 0x800000000000008bn, 0x8000000000008089n, 0x8000000000008003n,
  0x8000000000008002n, 0x8000000000000080n, 0x000000000000800an, 0x800000008000000an,
  0x8000000080008081n, 0x8000000000008080n, 0x0000000080000001n, 0x8000000080008008n,
];
const ROT = [
  [0, 36, 3, 41, 18], [1, 44, 10, 45, 2], [62, 6, 43, 15, 61], [28, 55, 25, 21, 56], [27, 20, 39, 8, 14],
];
const M64 = (1n << 64n) - 1n;
const rotl = (x, n) => n === 0 ? x : ((x << BigInt(n)) | (x >> BigInt(64 - n))) & M64;

function keccakF(s) {
  for (let round = 0; round < 24; round++) {
    const c = [];
    for (let x = 0; x < 5; x++) c[x] = s[x] ^ s[x + 5] ^ s[x + 10] ^ s[x + 15] ^ s[x + 20];
    for (let x = 0; x < 5; x++) {
      const d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1);
      for (let y = 0; y < 25; y += 5) s[x + y] ^= d;
    }
    const b = new Array(25);
    for (let x = 0; x < 5; x++) {
      for (let y = 0; y < 5; y++) b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(s[x + 5 * y], ROT[x][y]);
    }
    for (let y = 0; y < 25; y += 5) {
      for (let x = 0; x < 5; x++) s[x + y] = b[x + y] ^ (~b[(x + 1) % 5 + y] & M64 & b[(x + 2) % 5 + y]);
    }
    s[0] ^= RC[round];
  }
}

/** keccak256 of a Uint8Array, returned as 0x-prefixed hex. */
export function keccak256(bytes) {
  const rate = 136;
  const padded = new Uint8Array(Math.ceil((bytes.length + 1) / rate) * rate);
  padded.set(bytes);
  padded[bytes.length] ^= 0x01;
  padded[padded.length - 1] ^= 0x80;
  const s = new Array(25).fill(0n);
  for (let off = 0; off < padded.length; off += rate) {
    for (let i = 0; i < rate / 8; i++) {
      let lane = 0n;
      for (let j = 7; j >= 0; j--) lane = (lane << 8n) | BigInt(padded[off + i * 8 + j]);
      s[i] ^= lane;
    }
    keccakF(s);
  }
  const out = new Uint8Array(32);
  for (let i = 0; i < 4; i++) for (let j = 0; j < 8; j++) out[i * 8 + j] = Number((s[i] >> BigInt(8 * j)) & 0xffn);
  return toHex(out);
}

// ------------------------------------------------------------------- helpers
export const toHex = (bytes) => '0x' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
export function fromHex(hex) {
  const h = hex.startsWith('0x') ? hex.slice(2) : hex;
  const even = h.length % 2 ? '0' + h : h;
  return Uint8Array.from(even.match(/../g) || [], (x) => parseInt(x, 16));
}
export const utf8 = (s) => new TextEncoder().encode(s);
export const bigToHex = (n) => '0x' + n.toString(16);
export function word(value) {
  if (typeof value === 'boolean') value = value ? 1n : 0n;
  if (typeof value === 'string') {
    if (value.startsWith('0x')) return value.slice(2).padStart(64, '0');
    value = BigInt(value);
  }
  return BigInt(value).toString(16).padStart(64, '0');
}
export const selector = (signature) => keccak256(utf8(signature)).slice(0, 10);
/** Static-argument ABI encoding (uint/int/address/bool/bytes32). */
export function encodeCall(signature, args = []) {
  return selector(signature) + args.map(word).join('');
}
export function decodeWords(data) {
  const h = (data || '0x').slice(2);
  const out = [];
  for (let i = 0; i + 64 <= h.length; i += 64) out.push(BigInt('0x' + h.slice(i, i + 64)));
  return out;
}
export const wordToAddress = (w) => '0x' + w.toString(16).padStart(40, '0');

// ---------------------------------------------------------------------- RLP
function rlpEncodeItem(item) {
  if (Array.isArray(item)) {
    const body = concat(item.map(rlpEncodeItem));
    return concat([lengthPrefix(body.length, 0xc0), body]);
  }
  const bytes = item instanceof Uint8Array ? item : typeof item === 'bigint' ? bigBytes(item) : fromHex(item);
  if (bytes.length === 1 && bytes[0] < 0x80) return bytes;
  return concat([lengthPrefix(bytes.length, 0x80), bytes]);
}
function lengthPrefix(len, offset) {
  if (len < 56) return Uint8Array.of(offset + len);
  const lenBytes = bigBytes(BigInt(len));
  return concat([Uint8Array.of(offset + 55 + lenBytes.length), lenBytes]);
}
function bigBytes(n) {
  if (n === 0n) return new Uint8Array(0);
  let h = n.toString(16);
  if (h.length % 2) h = '0' + h;
  return fromHex(h);
}
export function concat(arrays) {
  const out = new Uint8Array(arrays.reduce((n, a) => n + a.length, 0));
  let off = 0;
  for (const a of arrays) { out.set(a, off); off += a.length; }
  return out;
}
export const rlp = (item) => rlpEncodeItem(item);

// ---------------------------------------------------------------- secp256k1
const P = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2fn;
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const G = [0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n,
  0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n];
const mod = (a, m = P) => ((a % m) + m) % m;
function modpow(b, e, m) {
  let r = 1n; b = mod(b, m);
  while (e > 0n) { if (e & 1n) r = r * b % m; b = b * b % m; e >>= 1n; }
  return r;
}
const inv = (a, m = P) => modpow(a, m - 2n, m);
// Jacobian coordinates keep signing to one inversion.
function jAdd(a, b) {
  if (a[2] === 0n) return b;
  if (b[2] === 0n) return a;
  const z1z1 = a[2] * a[2] % P, z2z2 = b[2] * b[2] % P;
  const u1 = a[0] * z2z2 % P, u2 = b[0] * z1z1 % P;
  const s1 = a[1] * b[2] % P * z2z2 % P, s2 = b[1] * a[2] % P * z1z1 % P;
  const h = mod(u2 - u1), r = mod(s2 - s1);
  if (h === 0n) return r === 0n ? jDouble(a) : [0n, 1n, 0n];
  const hh = h * h % P, hhh = hh * h % P, v = u1 * hh % P;
  const x = mod(r * r - hhh - 2n * v);
  const y = mod(r * mod(v - x) - s1 * hhh);
  return [x, y, a[2] * b[2] % P * h % P];
}
function jDouble(a) {
  if (a[2] === 0n || a[1] === 0n) return [0n, 1n, 0n];
  const ysq = a[1] * a[1] % P, s = 4n * a[0] % P * ysq % P, m = 3n * a[0] % P * a[0] % P;
  const x = mod(m * m - 2n * s);
  return [x, mod(m * mod(s - x) - 8n * ysq % P * ysq % P), 2n * a[1] % P * a[2] % P];
}
function mul(point, k) {
  let r = [0n, 1n, 0n], q = [point[0], point[1], 1n];
  while (k > 0n) { if (k & 1n) r = jAdd(r, q); q = jDouble(q); k >>= 1n; }
  if (r[2] === 0n) return null;
  const zi = inv(r[2]), zi2 = zi * zi % P;
  return [r[0] * zi2 % P, r[1] * zi2 % P * zi % P];
}
export function privateToAddress(privHex) {
  const pub = mul(G, BigInt(privHex));
  const bytes = concat([fromHex(word(pub[0])), fromHex(word(pub[1]))]);
  return '0x' + keccak256(bytes).slice(-40);
}
/** ECDSA over a 32-byte digest; returns low-s {r, s, v} with v in {0,1}. */
export function sign(digestHex, privHex) {
  const z = BigInt(digestHex), d = BigInt(privHex);
  for (;;) {
    const k = mod(BigInt(toHex(randomBytes(32))), N);
    if (k === 0n) continue;
    const R = mul(G, k);
    const r = mod(R[0], N);
    if (r === 0n) continue;
    let s = mod(inv(k, N) * mod(z + r * d, N), N);
    if (s === 0n) continue;
    let v = Number(R[1] & 1n);
    if (s > N / 2n) { s = N - s; v ^= 1; }
    return { r, s, v };
  }
}
/** Signs an EIP-1559 transaction and returns the raw hex for eth_sendRawTransaction. */
export function signTransaction(tx, privHex) {
  const fields = [BigInt(tx.chainId), BigInt(tx.nonce), BigInt(tx.maxPriorityFeePerGas), BigInt(tx.maxFeePerGas),
    BigInt(tx.gas), tx.to, BigInt(tx.value || 0), tx.data || '0x', []];
  const digest = keccak256(concat([Uint8Array.of(2), rlp(fields)]));
  const { r, s, v } = sign(digest, privHex);
  return toHex(concat([Uint8Array.of(2), rlp([...fields, BigInt(v), r, s])]));
}
