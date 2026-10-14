// Small ABI encoder for the keeper: static types, `bytes`/`string`, arrays of static types and tuples
// (dynamic when any member is dynamic). Enough for SwarmDesk.submit, GameRegistry.register, Desk.bind,
// EndowmentEscrow.forward and the hook/launch-factory calls. No dependencies.
import {keccak256, utf8} from './eth.mjs';

export function parseSignature(signature) {
  const open = signature.indexOf('(');
  return {name: signature.slice(0, open), types: splitTop(signature.slice(open + 1, -1))};
}

export function splitTop(s) {
  const out = [];
  let depth = 0, start = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '(') depth++;
    else if (s[i] === ')') depth--;
    else if (s[i] === ',' && depth === 0) { out.push(s.slice(start, i)); start = i + 1; }
  }
  if (s.length) out.push(s.slice(start));
  return out.filter((x) => x.length);
}

const tupleTypes = (t) => splitTop(t.slice(1, t.lastIndexOf(')')));
const isArray = (t) => t.endsWith('[]');
const elementType = (t) => t.slice(0, -2);

export function isDynamic(t) {
  if (t === 'bytes' || t === 'string' || isArray(t)) return true;
  if (t.startsWith('(')) return tupleTypes(t).some(isDynamic);
  return false;
}

function staticSize(t) {
  if (t.startsWith('(')) return tupleTypes(t).reduce((n, x) => n + staticSize(x), 0);
  return 32;
}

function hexWord(t, v) {
  if (t === 'bool') return (v === true || v === 1n || v === 1 || v === 'true' ? 1n : 0n).toString(16).padStart(64, '0');
  if (t === 'address') {
    if (!/^0x[0-9a-fA-F]{40}$/.test(v)) throw Error(`invalid address ${v}`);
    return v.slice(2).toLowerCase().padStart(64, '0');
  }
  if (/^bytes\d+$/.test(t)) {
    const n = Number(t.slice(5));
    if (!/^0x[0-9a-fA-F]*$/.test(v) || (v.length - 2) / 2 > n) throw Error(`invalid ${t} ${v}`);
    return v.slice(2).toLowerCase().padEnd(64, '0');
  }
  if (/^u?int\d*$/.test(t)) {
    let n = typeof v === 'bigint' ? v : BigInt(v);
    const bits = Number(t.replace(/^u?int/, '') || 256);
    if (t.startsWith('int')) { if (n < 0n) n = (1n << 256n) + n; }
    else if (n < 0n || n >= (1n << BigInt(bits))) throw Error(`${t} out of range: ${v}`);
    return n.toString(16).padStart(64, '0');
  }
  throw Error(`unsupported static type ${t}`);
}

function encodeBytes(hex) {
  if (!/^0x(?:[0-9a-fA-F]{2})*$/.test(hex)) throw Error('expected hex bytes');
  const length = (hex.length - 2) / 2;
  return BigInt(length).toString(16).padStart(64, '0') + hex.slice(2).toLowerCase().padEnd(Math.ceil(length / 32) * 64, '0');
}

/** Encodes a value of type t as hex without 0x (static: inline words; dynamic: self-contained tail). */
export function encodeValue(t, v) {
  if (t === 'bytes') return encodeBytes(v);
  if (t === 'string') return encodeBytes('0x' + Array.from(utf8(v), (b) => b.toString(16).padStart(2, '0')).join(''));
  if (isArray(t)) {
    const e = elementType(t);
    if (isDynamic(e)) throw Error('arrays of dynamic types are not supported');
    return BigInt(v.length).toString(16).padStart(64, '0') + v.map((x) => encodeValue(e, x)).join('');
  }
  if (t.startsWith('(')) return encodeTuple(tupleTypes(t), v);
  return hexWord(t, v);
}

/** Standard head/tail tuple encoding (also the top-level argument list). */
export function encodeTuple(types, values) {
  if (types.length !== values.length) throw Error(`expected ${types.length} values, got ${values.length}`);
  const headSize = types.reduce((n, t) => n + (isDynamic(t) ? 32 : staticSize(t)), 0);
  let head = '', tail = '';
  types.forEach((t, i) => {
    if (isDynamic(t)) {
      head += BigInt(headSize + tail.length / 2).toString(16).padStart(64, '0');
      tail += encodeValue(t, values[i]);
    } else head += encodeValue(t, values[i]);
  });
  return head + tail;
}

export function encodeFunction(signature, values) {
  const {types} = parseSignature(signature);
  return keccak256(utf8(signature)).slice(0, 10) + encodeTuple(types, values);
}
