import {encodeCall, word, decodeWords} from './eth.mjs';
import {encodeFunction} from './abi.mjs';

export function bytesCall(signature, stream, hex) {
  if (!/^0x(?:[0-9a-fA-F]{2})*$/.test(hex)) throw Error('Expected hex bytes');
  const length = (hex.length - 2) / 2;
  return encodeCall(signature).slice(0, 10) + word(stream) + word(64) + word(length) + hex.slice(2).padEnd(Math.ceil(length / 32) * 64, '0');
}

export function storedAnswer(log) {
  if (log.removed) return null;
  const words = decodeWords(log.data); const offset = Number(words[1]);
  if (offset !== 64) throw Error('Invalid AnswerStored ABI');
  const length = Number(words[2]);
  if (length !== 288 && length !== 608) throw Error('Unexpected oracle answer length');
  const answer = '0x' + log.data.slice(2 + offset * 2 + 64, 2 + offset * 2 + 64 + length * 2);
  if (answer.length !== 2 + length * 2) throw Error('Truncated oracle answer');
  return {stream: Number(BigInt(log.topics[1])), id: log.topics[2], answer};
}

// ------------------------------------------------------------------ v3.9 attestation relay
/// The protocol's 15-field attestation, in the order the live OracleAttestation library hashes it.
export const ATTESTATION_TYPE = '(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64)';
export const SUBMIT_SIGNATURE = `submit(${ATTESTATION_TYPE},bytes)`;
const ANSWER_TYPES = {bool: 0, address: 1, bytes32: 2, uint256: 3, 'address[]': 4, 'bytes32[]': 5};
const FIELDS = ['requestId', 'chainId', 'questionHash', 'answerType', 'answer', 'figure', 'fromBlock', 'toBlock', 'blockHash', 'panelJobId', 'panelSize', 'quorum', 'agreed', 'issuedAt', 'expiresAt'];

export function answerTypeCode(value) {
  if (typeof value === 'number' || typeof value === 'bigint') return BigInt(value);
  if (!(value in ANSWER_TYPES)) throw Error(`unknown answerType ${value}`);
  return BigInt(ANSWER_TYPES[value]);
}

/** Checks the EIP-712 document served by GET /oracle/requests/:id/attestation and returns the struct values. */
export function attestationValues(doc, {desk, chainId}) {
  const m = doc.message;
  if (!m || doc.primaryType !== 'OracleAttestation') throw Error('not an OracleAttestation document');
  const names = (doc.types?.OracleAttestation || []).map((f) => f.name);
  if (names.length && (names.length !== 15 || names.some((n, i) => n !== FIELDS[i]))) throw Error('attestation struct differs from the v2 library');
  if (doc.domain?.version !== '2' || doc.domain?.name !== 'IdentityMD Oracle') throw Error(`unsupported attestation domain ${doc.domain?.name} v${doc.domain?.version}`);
  if (desk && doc.domain.verifyingContract?.toLowerCase() !== desk.toLowerCase()) throw Error(`signed for ${doc.domain.verifyingContract}, not the Desk`);
  if (chainId && Number(doc.domain.chainId) !== Number(chainId)) throw Error(`signed for chain ${doc.domain.chainId}`);
  return [m.requestId, BigInt(m.chainId), m.questionHash, answerTypeCode(m.answerType), m.answer, BigInt(m.figure ?? 0),
    BigInt(m.fromBlock), BigInt(m.toBlock), m.blockHash, m.panelJobId, BigInt(m.panelSize), BigInt(m.quorum), BigInt(m.agreed),
    BigInt(m.issuedAt), BigInt(m.expiresAt)];
}

/** Calldata for SwarmDesk.submit(attestation, signature). The relayer adds nothing: these are the attester's bytes. */
export function encodeSubmit(values, signature) {
  if (!/^0x[0-9a-fA-F]{130}$/.test(signature)) throw Error('expected a 65-byte signature');
  return encodeFunction(SUBMIT_SIGNATURE, [values, signature]);
}

/** Request ids of the opened oracle runs of a schedule document (GET /schedules/:id), newest first. */
export function scheduleRequestIds(doc, limit = 3) {
  return (doc.latest || []).filter((r) => r.status === 'opened' && r.result?.kind === 'oracle' && r.result.id).map((r) => r.result.id).slice(0, limit);
}
