#!/usr/bin/env node
// Offline IMD oracle question commitment. No network, signing, or transactions.
// Protocol identity fields verified against published api.imd.fun oracle records:
// 4c772fed-d644-4f97-b503-9a629ea19604 (panel bool, definitions)
// 99f49123-221b-412c-b57c-90520c049f46 (panel address, head, definitions)
// 788aea55-9650-4724-9279-c8df6977ce0b (chain bytes32[], head)
// https://imd.fun/docs/#oracle documents absolute-window question commitments.
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { keccak256 } from '../keeper/lib/eth.mjs';

export function canonicalJson(value) {
  if (value === null) return 'null';
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (typeof value === 'object') {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(',')}}`;
  }
  if (typeof value === 'number' && !Number.isSafeInteger(value)) throw Error('Expected a safe JSON integer');
  if (!['string', 'number', 'boolean'].includes(typeof value)) throw Error('Unsupported canonical JSON value');
  return JSON.stringify(value);
}

export function oracleQuestion(input) {
  if (input.v !== 1) throw Error('Expected oracle body v=1');
  if (typeof input.question !== 'string' || !input.question.length || input.question.length > 2000) {
    throw Error('Expected question of 1..2000 characters');
  }
  if (!Number.isSafeInteger(input.chainId) || input.chainId <= 0) throw Error('Invalid question chain');
  if (!['bool', 'address', 'bytes32', 'uint256', 'address[]', 'bytes32[]'].includes(input.answerType)) {
    throw Error('Invalid answerType');
  }
  const { fromBlock, toBlock } = input.window ?? {};
  if (!Number.isSafeInteger(fromBlock) || !Number.isSafeInteger(toBlock) || fromBlock < 0 || toBlock < fromBlock) {
    throw Error('Question hashes require a resolved absolute fromBlock/toBlock window');
  }
  if (input.window.hours !== undefined) throw Error('Relative windows cannot be pinned in advance');
  const question = {
    v: 1,
    question: input.question,
    chainId: input.chainId,
    window: { fromBlock, toBlock },
    answerType: input.answerType,
  };
  if (input.evidence !== undefined && !['chain', 'panel'].includes(input.evidence)) throw Error('Invalid evidence');
  // The protocol normalizes the default evidence mode by omitting it from the commitment.
  if (input.evidence === 'panel') question.evidence = 'panel';
  if (input.head !== undefined) {
    if (!Number.isSafeInteger(input.head) || input.head < 1 || input.head > 32) throw Error('Invalid head');
    question.head = input.head;
  }
  if (input.definitions !== undefined) {
    if (!input.definitions || typeof input.definitions !== 'object' || Array.isArray(input.definitions)) {
      throw Error('Definitions must be an object');
    }
    for (const [key, value] of Object.entries(input.definitions)) {
      if (!key.length || key.length > 64 || typeof value !== 'string' || !value.length || value.length > 512) {
        throw Error('Invalid definition');
      }
    }
    question.definitions = input.definitions;
  }
  // Routing, consumer, price, quorum, expiry, guards and tolerance do not enter this hash.
  // The consumer separately checks the signed panel, expiry, domain, blocks and typed answer.
  return question;
}

export function oracleQuestionHash(input) {
  return keccak256(new TextEncoder().encode(canonicalJson(oracleQuestion(input))));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3) throw Error('Usage: node tools/oracle_question_hash.mjs body.json (or - for stdin)');
  const body = readFileSync(process.argv[2] === '-' ? 0 : process.argv[2], 'utf8');
  const input = JSON.parse(body);
  console.log(JSON.stringify({
    questionHash: oracleQuestionHash(input),
    bodyHash: keccak256(new TextEncoder().encode(body)),
    canonicalQuestion: canonicalJson(oracleQuestion(input)),
  }, null, 2));
}
