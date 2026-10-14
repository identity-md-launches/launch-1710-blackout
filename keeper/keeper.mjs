#!/usr/bin/env node
// BLACKOUT v3.9 keeper. Node 22+, no dependencies. Reads RPC_URL and KEEPER_KEY only from an env
// file outside the repository (default /etc/blackout/keeper.env, override with --env PATH).
//
//   node keeper.mjs status            read-only overview of what is due
//   node keeper.mjs once [--dry-run]  one pass over every duty
//   node keeper.mjs run  [--dry-run]  loop forever (systemd unit); --interval SECONDS (default 2)
//   node keeper.mjs wire --wiring FILE [--step STEP] [--dry-run]
//                                     post-launch wiring in order: bind-desk, register, bind-router,
//                                     forward, fund, claim-fees (see keeper/README.md, keeper/wiring.example.json)
//                                     v3.16: bind-desk never sends; it simulates SwarmDesk.bind from the Desk's
//                                     pinned binder and prints the calldata for that wallet to sign.
//   node keeper.mjs relay --request UUID [--dry-run]
//                                     relay one attested oracle answer to SwarmDesk.submit
//   node keeper.mjs ask-backup --stream event|regulator [--body PATH] [--dry-run]
//
// Every duty is simulated with eth_call first and only sent when the simulation succeeds, so a
// disabled phase (locks, billboards, pot...) or a not-yet-due action never costs gas.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname } from 'node:path';
import {bytesCall, storedAnswer, attestationValues, encodeSubmit, scheduleRequestIds} from './lib/oracle.mjs';
import {encodeFunction} from './lib/abi.mjs';
import { encodeCall, decodeWords, wordToAddress, keccak256, utf8, signTransaction, privateToAddress, bigToHex, word }
  from './lib/eth.mjs';

const args = process.argv.slice(2);
const command = args.find((a) => !a.startsWith('--')) || 'status';
const flag = (name, fallback) => {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1];
};
const dryRun = args.includes('--dry-run') || command === 'status';
const envPath = flag('--env', '/etc/blackout/keeper.env');
const interval = Number(flag('--interval', '2')) * 1000;

function loadEnv(path) {
  const out = {};
  if (!existsSync(path)) throw new Error(`env file not found: ${path} (see keeper/README.md)`);
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*"?([^"#]*)"?\s*(#.*)?$/);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}
const env = loadEnv(envPath);
const RPC = env.RPC_URL;
const REGISTRY = env.REGISTRY;
const KEY = env.KEEPER_KEY;
const STATE = env.STATE_FILE || '/var/lib/blackout/keeper-state.json';
const CHAIN = env.CHAIN_ID ? Number(env.CHAIN_ID) : null;
const ORACLE_API = (env.ORACLE_API || 'https://api.imd.fun').replace(/\/$/, '');
const SCHEDULES = [env.SCHEDULE_EVENT || null, env.SCHEDULE_REGULATOR || null];
const RELAY_EVERY = Number(env.RELAY_INTERVAL || '60') * 1000;
const CLAIM_EVERY = Number(env.CLAIM_INTERVAL || '21600') * 1000;
if (!RPC || (!REGISTRY && command !== 'wire')) throw new Error('RPC_URL and REGISTRY are required in the env file');
if (!dryRun && !/^0x[0-9a-fA-F]{64}$/.test(KEY || '')) throw new Error('KEEPER_KEY (0x + 64 hex) is required unless --dry-run');
const keeper = KEY && /^0x[0-9a-fA-F]{64}$/.test(KEY) ? privateToAddress(KEY) : null;

let rpcId = 1;
async function rpc(method, params = []) {
  const res = await fetch(RPC, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: rpcId++, method, params }),
  });
  const body = await res.json();
  if (body.error) throw Object.assign(new Error(body.error.message || 'rpc error'), { rpc: body.error });
  return body.result;
}
const call = (to, sig, a = []) => rpc('eth_call', [{ to, data: encodeCall(sig, a), from: keeper || undefined }, 'latest']);
const uint = async (to, sig, a = []) => decodeWords(await call(to, sig, a))[0] ?? 0n;
const addr = async (to, sig, a = []) => wordToAddress(await uint(to, sig, a));
const topic = (sig) => keccak256(utf8(sig));
const ZERO = '0x' + '0'.repeat(40);
const same = (a, b) => (a || '').toLowerCase() === (b || '').toLowerCase();
async function api(path) {
  const res = await fetch(`${ORACLE_API}${path}`, { headers: { accept: 'application/json' } });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return res.json();
}

// ---------------------------------------------------------------- state
function loadState() {
  try { return JSON.parse(readFileSync(STATE, 'utf8')); } catch { return { nextBlock: 0, pending: {} }; }
}
function saveState(state) {
  if (dryRun) return;
  mkdirSync(dirname(STATE), { recursive: true });
  writeFileSync(STATE, JSON.stringify(state));
}

// ------------------------------------------------------------- contracts
const ROLES = { pool: 0, rewards: 1, farm: 2, items: 3, packs: 4, starter: 5, fees: 6, grid: 7, season: 8, engine: 9,
  economy: 10, enhancement: 11, civic: 12, billboards: 13 };
const ROLE_NAMES = ['RewardPool', 'FarmRewards', 'FarmCore', 'FarmItems', 'PackSale', 'StarterClaim', 'FeeRouter',
  'GridOperator', 'Season', 'FarmEngine', 'Economy', 'Enhancement', 'Civic', 'Billboards'];
async function modules() {
  const out = { registry: REGISTRY };
  for (const [name, role] of Object.entries(ROLES)) {
    try { out[name] = await addr(REGISTRY, 'module(uint256)', [role]); } catch { out[name] = null; }
    if (out[name] && (await rpc('eth_getCode', [out[name], 'latest'])) === '0x') out[name] = null;
  }
  if (Object.values(ROLES).some((_, i) => !out[Object.keys(ROLES)[i]])) {
    throw new Error(`registry ${REGISTRY} has unregistered or codeless modules; run \`wire\` first (register all fourteen roles)`);
  }
  out.market = await addr(REGISTRY, 'market()');
  out.params = await addr(REGISTRY, 'params()');
  out.desk = await addr(out.params, 'swarmWallet()');
  return out;
}

// --------------------------------------------------------------- sending
const log = (...m) => console.log(new Date().toISOString(), ...m);
async function attempt(label, to, sig, a = [], rawData) {
  if (!to) return { label, ok: false, reason: 'module not registered' };
  const data = rawData || encodeCall(sig, a);
  let simulated;
  try {
    simulated = await rpc('eth_call', [{ from: keeper || undefined, to, data }, 'latest']);
  } catch (e) {
    return { label, ok: false, reason: e.rpc?.data || e.message };
  }
  if (dryRun) { log(`[dry-run] would send ${label}`); return { label, ok: true, dry: true, simulated }; }
  const [nonce, gasHex, block] = await Promise.all([
    rpc('eth_getTransactionCount', [keeper, 'pending']),
    rpc('eth_estimateGas', [{ from: keeper, to, data }]),
    rpc('eth_getBlockByNumber', ['latest', false]),
  ]);
  const base = BigInt(block.baseFeePerGas || '0x0');
  const tip = BigInt(env.PRIORITY_FEE_WEI || '1000000');
  const tx = { chainId: CHAIN ?? Number(BigInt(await rpc('eth_chainId'))), nonce, maxPriorityFeePerGas: tip,
    maxFeePerGas: base * 2n + tip, gas: BigInt(gasHex) * 12n / 10n, to, data, value: 0n };
  const raw = signTransaction(tx, KEY);
  const hash = await rpc('eth_sendRawTransaction', [raw]);
  log(`sent ${label} ${hash}`);
  for (let i = 0; i < 60; i++) {
    const receipt = await rpc('eth_getTransactionReceipt', [hash]);
    if (receipt) {
      const ok = BigInt(receipt.status) === 1n;
      log(`${ok ? 'confirmed' : 'REVERTED'} ${label} in block ${Number(BigInt(receipt.blockNumber))}`);
      return { label, ok, hash, simulated };
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  return { label, ok: false, reason: 'no receipt after 60s', hash };
}

// ----------------------------------------------------------------- duties
async function scanCommits(m, state) {
  const head = Number(BigInt(await rpc('eth_blockNumber')));
  const start = Math.max(0, state.nextBlock - 16); // re-read a little after restarts
  const sources = [
    ['pack', m.packs, topic('PackCommitted(uint256,address,uint256,uint256,bool)')],
    ['starter', m.starter, topic('StarterCommitted(uint256,address,uint256)')],
    ['enhance', m.enhancement, topic('EnhancementCommitted(uint256,address,uint256,uint256,uint256,uint256)')],
    ['season', m.season, topic('SeasonPrepared(uint256,uint256)')],
    ['oracle', m.desk, topic('AnswerStored(uint8,bytes32,uint256,bytes)')],
  ];
  for (let low = start; low <= head; low += 2000) {
    const high = Math.min(head, low + 1999);
    for (const [kind, address, t] of sources) {
      if (!address) continue;
      const logs = await rpc('eth_getLogs', [{ address, fromBlock: bigToHex(BigInt(low)), toBlock: bigToHex(BigInt(high)), topics: [t] }]);
      for (const entry of logs) {
        if (entry.removed) continue;
        if (kind === 'oracle') {
          const result=storedAnswer(entry);state.oracleAnswers ??= {};state.oracleAnswers[result.stream]=result;continue;
        }
        state.pending[`${kind}:${BigInt(entry.topics[1])}`] = [kind, BigInt(entry.topics[1]).toString()];
      }
    }
  }
  state.nextBlock = head + 1;
}

async function entropyDuties(m, state, results) {
  for (const [key, [kind, idStr]] of Object.entries(state.pending)) {
    const id = BigInt(idStr);
    let done = false;
    if (kind === 'pack') {
      const c = decodeWords(await call(m.packs, 'commits(uint256)', [id]));
      // Commit layout: player, target, count, opened, mythic, guaranteed, seed, fixedSeed, expired
      done = c.length && c[7] === 1n && c[3] >= c[2];
      if (!done && c[7] === 0n) {
        const r = await attempt(`pack capture #${id}`, m.packs, 'captureEntropy(uint256)', [id]);
        results.push(r);
        if (!r.ok) results.push(await attempt(`pack re-arm #${id}`, m.packs, 'rearm(uint256)', [id]));
      }
    } else if (kind === 'starter') {
      const captured = await uint(m.starter, 'entropyCaptured(uint256)', [id]);
      done = captured === 1n;
      if (!done) {
        const r = await attempt(`starter capture #${id}`, m.starter, 'captureEntropy(uint256)', [id]);
        results.push(r);
        if (!r.ok) results.push(await attempt(`starter re-arm #${id}`, m.starter, 'rearm(uint256)', [id]));
      }
    } else if (kind === 'enhance') {
      const a = decodeWords(await call(m.enhancement, 'attempts(uint256)', [id]));
      done = a.length && a[6] === 1n; // resolved
      if (!done) {
        if (a[5] === 0n) results.push(await attempt(`enhancement capture #${id}`, m.enhancement, 'capture(uint256)', [id]));
        results.push(await attempt(`enhancement resolve #${id}`, m.enhancement, 'resolve(uint256)', [id]));
      }
    } else if (kind === 'season') {
      const r = await attempt(`season finalize week ${id}`, m.season, 'finalize(uint256)', [id]);
      results.push(r);
      if (!r.ok) results.push(await attempt(`season re-arm week ${id}`, m.season, 'rearm(uint256)', [id]));
      else if (!r.dry) done = true;
    }
    if (done) delete state.pending[key];
  }
}

async function epochDuties(m, results) {
  const [live, end, epoch] = await Promise.all([uint(m.rewards, 'live()'), uint(m.rewards, 'epochEnd()'), uint(m.rewards, 'epoch()')]);
  const now = BigInt(Math.floor(Date.now() / 1000));
  if (live === 1n && now >= end) results.push(await attempt(`advanceEpoch -> ${epoch + 1n}`, m.rewards, 'advanceEpoch()'));
  // Event resolution for the current epoch (no-op if the epoch advance already resolved it).
  const ev = decodeWords(await call(m.grid, 'eventAt(uint256)', [epoch]));
  if (ev.length && ev[4] === 0n) results.push(await attempt(`grid resolve epoch ${epoch}`, m.grid, 'resolve(uint256)', [epoch]));
  return { live, end, epoch };
}

async function seasonDuties(m, results) {
  let week = 0n;
  try { week = await uint(m.billboards || m.civic, 'week()'); } catch { return { week: null }; }
  for (let w = week > 2n ? week - 2n : 0n; w < week; w++) {
    results.push(await attempt(`season prepare week ${w}`, m.season, 'prepare(uint256,uint256)', [w, 64n]));
    results.push(await attempt(`season rollover week ${w}`, m.season, 'rollover(uint256)', [w]));
  }
  if (m.billboards) {
    for (let d = 0n; d < 8n; d++) results.push(await attempt(`billboard settle week ${week} district ${d}`, m.billboards, 'settleBillboard(uint256,uint256)', [week, d]));
  }
  return { week };
}

async function feeDuties(m, results) {
  // The hook holds swap fees until anyone flushes them to the FeeRouter (1% base + sell surcharge + launch tax).
  const held = decodeWords(await call(m.market, 'heldBase()'))[0] + decodeWords(await call(m.market, 'heldSellTax()'))[0]
    + decodeWords(await call(m.market, 'heldLaunchTax()'))[0];
  if (held > 0n) results.push(await attempt(`flush hook fees ${held} wei`, m.market, 'flushFees()'));
  const [amount, minimum] = decodeWords(await call(m.fees, 'sellBatchQuote()'));
  if (amount && amount > 0n) results.push(await attempt(`system sell ${amount} tokens`, m.fees, 'executeSells(uint256,uint256)', [amount, minimum]));
  const [rewardETH, potETH, batch, slippage] = await Promise.all([
    uint(m.fees, 'rewardETH()'), uint(m.fees, 'potETH()'),
    uint(m.params, 'get(uint8)', [22n]), uint(m.params, 'get(uint8)', [23n]),
  ]);
  const MIN = 50000000000000000n; // 0.05 ETH, FeeRouter.MIN_BUY_AMOUNT
  for (const [name, balance, fn, bps] of [['reward', rewardETH, 'executeBuys(uint256,uint256)', slippage], ['pot', potETH, 'executePotBuys(uint256,uint256)', 150n]]) {
    if (balance === 0n) continue;
    const eth = balance < batch ? balance : batch;
    if (eth < (balance < MIN ? balance : MIN)) continue;
    const quote = await uint(m.market, 'quote(uint256)', [eth]);
    if (quote === 0n) continue;
    results.push(await attempt(`${name} buy ${eth} wei`, m.fees, fn, [eth, quote * (10000n - bps) / 10000n]));
  }
  return { sellBatch: amount ?? 0n, rewardETH, potETH, held };
}

async function phaseDuties(m, results) {
  const flags = [];
  for (let f = 0n; f < 8n; f++) {
    const [enabled, notice] = await Promise.all([uint(m.civic, 'enabled(uint256)', [f]), uint(m.civic, 'noticeAt(uint256)', [f])]);
    flags.push({ feature: Number(f), enabled: enabled === 1n, noticeAt: Number(notice) });
    if (enabled === 0n && notice !== 0n) results.push(await attempt(`enable feature ${f}`, m.civic, 'enable(uint256)', [f]));
  }
  const announcedCap = await uint(m.enhancement, 'announcedCap()');
  if (announcedCap !== 0n) results.push(await attempt(`activate enhancement cap +${announcedCap}`, m.enhancement, 'activateCap()'));
  return flags;
}

async function oracleDuties(m,state,results) {
  const status=[];
  for(let stream=0;stream<2;stream++) {
    const a=decodeWords(await call(m.desk,'lastAnswer(uint8)',[stream]));
    const row={stream,hash:a[0],requestId:a[1],issuedAt:Number(a[2]),validUntil:Number(a[3]),slot:a[4],pending:a[5]===1n,receivedBlock:a[6]};
    status.push(row);
    let cached=state.oracleAnswers?.[stream];
    if(row.pending&&(!cached||BigInt(cached.id)!==row.requestId)) {
      const logs=await rpc('eth_getLogs',[{address:m.desk,fromBlock:bigToHex(row.receivedBlock),toBlock:bigToHex(row.receivedBlock),topics:[topic('AnswerStored(uint8,bytes32,uint256,bytes)'),'0x'+word(stream),'0x'+word(row.requestId)]}]);
      for(const entry of logs) {cached=storedAnswer(entry);if(cached){state.oracleAnswers??={};state.oracleAnswers[stream]=cached;}}
    }
    if(row.pending&&cached&&BigInt(cached.id)===row.requestId) {
      results.push(await attempt(`execute swarm ${stream===0?'event':'regulator'}`,m.desk,'execute(uint8,bytes)',[],bytesCall('execute(uint8,bytes)',stream,cached.answer)));
    }
  }
  return status;
}

// ------------------------------------------------------------ v3.9 relay
/// Desk question commitments: oracleConfig() is a static tuple; words 9 and 10 are the two question hashes.
async function deskQuestions(desk) {
  const oc = decodeWords(await call(desk, 'oracleConfig()'));
  return { questions: ['0x' + word(oc[9]), '0x' + word(oc[10])], asset: wordToAddress(oc[3]) };
}

/// Relays one attested answer. The Desk re-checks signature, question, window, panel, slot, epoch and UUID;
/// the keeper only pays gas. Returns the attempt result or a reason for skipping.
async function relayOne(m, state, requestId, label) {
  state.relayed ??= {};
  if (state.relayed[requestId]) return { label, ok: false, reason: 'already relayed' };
  const doc = await api(`/oracle/requests/${requestId}/attestation`);
  if (!doc) return { label, ok: false, reason: 'not attested yet' };
  const chainId = CHAIN ?? Number(BigInt(await rpc('eth_chainId')));
  let values;
  try { values = attestationValues(doc, { desk: m.desk, chainId }); } catch (e) { state.relayed[requestId] = `refused: ${e.message}`; return { label, ok: false, reason: e.message }; }
  const { questions } = await deskQuestions(m.desk);
  if (!questions.some((q) => same(q, values[2]))) { state.relayed[requestId] = 'foreign question'; return { label, ok: false, reason: 'question hash is not one of the Desk commitments' }; }
  const consumed = await uint(m.desk, 'consumed(bytes32)', [values[0]]);
  if (consumed === 1n) { state.relayed[requestId] = 'consumed'; return { label, ok: false, reason: 'already consumed on chain' }; }
  const r = await attempt(label, m.desk, null, [], encodeSubmit(values, doc.signature));
  if (r.ok && !r.dry) state.relayed[requestId] = r.hash;
  return r;
}

async function relayDuties(m, state, results) {
  if (!SCHEDULES.some(Boolean)) return { schedules: [] };
  const now = Date.now();
  if (state.lastRelayCheck && now - state.lastRelayCheck < RELAY_EVERY) return { schedules: SCHEDULES, skipped: 'throttled' };
  state.lastRelayCheck = now;
  const seen = [];
  for (const [stream, scheduleId] of SCHEDULES.entries()) {
    if (!scheduleId) continue;
    let doc;
    try { doc = await api(`/schedules/${scheduleId}`); } catch (e) { results.push({ label: `schedule ${scheduleId}`, ok: false, reason: e.message }); continue; }
    if (!doc) { results.push({ label: `schedule ${scheduleId}`, ok: false, reason: 'unknown schedule' }); continue; }
    seen.push({ stream, id: scheduleId, status: doc.status, runsRemaining: doc.runsRemaining, nextRunAt: doc.nextRunAt });
    for (const requestId of scheduleRequestIds(doc)) {
      results.push(await relayOne(m, state, requestId, `relay ${stream === 0 ? 'event' : 'regulator'} ${requestId}`));
    }
  }
  return { schedules: seen };
}

// --------------------------------------------------------- v3.9 claimFees
async function claimDuties(m, state, results) {
  const factory = env.LAUNCH_FACTORY, launch = env.TOKEN_LAUNCH;
  if (!factory || !launch) return null;
  const now = Date.now();
  if (state.lastClaim && now - state.lastClaim < CLAIM_EVERY) return { skipped: 'interval' };
  const data = encodeFunction('claimFees(uint64)', [BigInt(launch)]);
  // The simulation returns the two amounts (paying wallet, network); nothing to claim means nothing to send.
  let simulated;
  try { simulated = decodeWords(await rpc('eth_call', [{ to: factory, data }, 'latest'])); } catch (e) { return { reason: e.rpc?.data || e.message }; }
  if (!simulated.some((x) => x > 0n)) { state.lastClaim = now; return { skipped: 'no fees accrued' }; }
  const r = await attempt(`LaunchFactory.claimFees(${launch})`, factory, null, [], data);
  results.push(r);
  if (r.ok && !r.dry) state.lastClaim = now;
  return { amounts: simulated.map(String) };
}

// ------------------------------------------------------------- v3.9 wiring
function loadWiring() {
  const path = flag('--wiring', env.WIRING_FILE);
  if (!path) throw new Error('wire needs --wiring FILE (see keeper/wiring.example.json)');
  const w = JSON.parse(readFileSync(path, 'utf8'));
  for (const k of ['desk', 'registry']) if (!/^0x[0-9a-fA-F]{40}$/.test(w[k] || '')) throw new Error(`wiring.${k} must be an address`);
  w.artifacts = Array.isArray(w.artifacts) ? w.artifacts : [w.artifacts || 'out-launch'];
  return w;
}
function creationCodes(w, name) {
  const out = [];
  for (const dir of w.artifacts) {
    const p = `${dir}/${name}.sol/${name}.json`;
    if (!existsSync(p)) continue;
    const code = JSON.parse(readFileSync(p, 'utf8')).bytecode.object;
    if (code && code !== '0x') out.push({ dir, code });
  }
  if (!out.length) throw new Error(`no artifact for ${name} in ${w.artifacts.join(', ')}; build with the launch toolchain first`);
  return out;
}
function coordinate(w, name) {
  for (const job of [w.jobA, w.jobB]) {
    const index = (job?.contracts || []).indexOf(name);
    if (index !== -1) return job.launch ? { launch: BigInt(job.launch), index: BigInt(index) } : null;
  }
  throw new Error(`${name} is not listed in jobA or jobB of the wiring file`);
}
/// Tries each artifact toolchain until the simulation accepts the exact deployed initcode.
async function attemptWithCode(label, to, signature, build) {
  let last;
  for (const candidate of build.codes) {
    last = await attempt(`${label} [${candidate.dir}]`, to, null, [], encodeFunction(signature, build.args(candidate.code)));
    if (last.ok) return last;
  }
  return last;
}

async function wire() {
  const w = loadWiring();
  const only = flag('--step', null);
  const steps = ['bind-desk', 'register', 'bind-router', 'forward', 'fund', 'claim-fees'];
  if (only && !steps.includes(only)) throw new Error(`--step must be one of ${steps.join(', ')}`);
  const registry = w.registry;
  const report = [];
  const run = (step) => !only || only === step;
  const registryCo = coordinate(w, 'GameRegistry'), paramsCo = coordinate(w, 'Params');
  if (!registryCo || !paramsCo) throw new Error('jobA.launch is required: wiring starts right after job A is recorded');
  const registryCodes = creationCodes(w, 'GameRegistry'), paramsCodes = creationCodes(w, 'Params');

  // 1. Desk.bind right after job A. v3.16: only the Desk's pinned binder (the project wallet) may call it, so the
  //    keeper key never sends this step. It simulates the call from the binder and prints the calldata to sign.
  //    Steps that need the Desk bound (bind-router, forward) wait until Desk.registry() is the wiring registry.
  let deskBound = await addr(w.desk, 'registry()');
  if (run('bind-desk')) {
    if (same(deskBound, ZERO)) {
      if (!w.tokenLaunch) throw new Error('wiring.tokenLaunch (the L2 token launch number) is required: v3.15 bind proves the hook against LaunchFactory.positionOf');
      const r = await bindCalldata(w, registry, registryCodes, paramsCodes, registryCo, paramsCo);
      report.push(r);
      if (!r.ok) { print(report); throw new Error(`Desk.bind does not simulate from the binder: ${r.reason}. Do not continue wiring.`); }
      report.push({ label: 'Desk.registry() check', ok: false, reason: 'unbound until the binder sends the printed transaction' });
    } else {
      report.push({ label: 'SwarmDesk.bind', ok: true, skipped: `already bound to ${deskBound}` });
      if (!same(deskBound, registry)) { print(report); throw new Error(`STOP: Desk.registry() is ${deskBound}, not ${registry}. The Desk is bound to another registry; do not forward the endowment.`); }
      report.push({ label: 'Desk.registry() check', ok: true, registry: deskBound });
    }
  }
  // 2. Register every role whose job is recorded (A first, then B).
  if (run('register')) {
    for (let role = 0; role < 14; role++) {
      const name = ROLE_NAMES[role];
      const current = await addr(registry, 'registeredModule(uint256)', [role]);
      if (!same(current, ZERO)) { report.push({ label: `register ${name}`, ok: true, skipped: `already ${current}` }); continue; }
      const co = coordinate(w, name);
      if (!co) { report.push({ label: `register ${name}`, ok: false, reason: 'its job is not recorded yet' }); continue; }
      report.push(await attemptWithCode(`register ${name} (role ${role})`, registry, 'register(uint256,uint64,uint256,bytes)',
        { codes: creationCodes(w, name), args: (code) => [BigInt(role), co.launch, co.index, code] }));
    }
  }
  // 3. Hook <- FeeRouter (needs role 6 registered and the Desk bound).
  if (run('bind-router') && !same(deskBound, registry)) report.push({ label: 'V4Market.bindFeeRouter', ok: false, reason: `Desk.registry() is ${deskBound}; the binder has not bound ${registry} yet` });
  else if (run('bind-router')) {
    const hook = await addr(registry, 'market()');
    const router = await addr(registry, 'registeredModule(uint256)', [6]);
    const boundRouter = await addr(hook, 'fees()');
    if (!same(boundRouter, ZERO)) report.push({ label: 'V4Market.bindFeeRouter', ok: true, skipped: `already ${boundRouter}` });
    else if (same(router, ZERO)) report.push({ label: 'V4Market.bindFeeRouter', ok: false, reason: 'FeeRouter not registered yet' });
    else report.push(await attempt('V4Market.bindFeeRouter', hook, null, [], encodeFunction('bindFeeRouter(address,uint64,uint256)', [router, registryCo.launch, registryCo.index])));
  }
  // 4. Escrow -> RewardPool (needs role 0 registered, the Desk bound to this registry).
  if (run('forward')) {
    if (!/^0x[0-9a-fA-F]{40}$/.test(w.escrow || '')) report.push({ label: 'EndowmentEscrow.forward', ok: false, reason: 'wiring.escrow missing' });
    else if (!same(deskBound, registry)) report.push({ label: 'EndowmentEscrow.forward', ok: false, reason: `Desk.registry() is ${deskBound}; never forward before the binder has bound ${registry}` });
    else if ((await uint(w.escrow, 'forwarded()')) === 1n) report.push({ label: 'EndowmentEscrow.forward', ok: true, skipped: 'already forwarded' });
    else {
      const poolCo = coordinate(w, 'RewardPool');
      const poolCodes = creationCodes(w, 'RewardPool');
      report.push(await attemptWithCode('EndowmentEscrow.forward', w.escrow, 'forward(address,uint64,uint256,bytes,uint64,uint256,bytes)', {
        codes: registryCodes.map((rc, i) => ({ dir: rc.dir, code: [rc.code, (poolCodes[i] || poolCodes[0]).code] })),
        args: ([rCode, pCode]) => [registry, registryCo.launch, registryCo.index, rCode, poolCo.launch, poolCo.index, pCode],
      }));
    }
  }
  // 5. Start the endowment drip.
  if (run('fund')) {
    const pool = await addr(registry, 'registeredModule(uint256)', [0]);
    if (same(pool, ZERO)) report.push({ label: 'RewardPool.fundEndowment', ok: false, reason: 'RewardPool not registered yet' });
    else if ((await uint(pool, 'endowed()')) === 1n) report.push({ label: 'RewardPool.fundEndowment', ok: true, skipped: 'already endowed' });
    else report.push(await attempt('RewardPool.fundEndowment', pool, 'fundEndowment()'));
  }
  // 6. Platform fee claim for the paying wallet (permissionless).
  if (run('claim-fees')) {
    if (!w.launchFactory || !w.tokenLaunch) report.push({ label: 'LaunchFactory.claimFees', ok: false, reason: 'wiring.launchFactory / tokenLaunch missing' });
    else report.push(await attempt(`LaunchFactory.claimFees(${w.tokenLaunch})`, w.launchFactory, null, [], encodeFunction('claimFees(uint64)', [BigInt(w.tokenLaunch)])));
  }
  print(report);
}
/// v3.16: SwarmDesk.bind is restricted to the Desk's pinned binder. Build the calldata, simulate it with
/// `from: binder` for each artifact toolchain, and print the first that simulates; nothing is sent from this key.
function bindArgs(w, registry, rCode, pCode, registryCo, paramsCo) {
  return [registry, rCode, pCode, registryCo.launch, registryCo.index, paramsCo.launch, paramsCo.index, BigInt(w.tokenLaunch)];
}
const BIND_SIGNATURE = 'bind(address,bytes,bytes,uint64,uint8,uint64,uint8,uint64)';
async function bindCalldata(w, registry, registryCodes, paramsCodes, registryCo, paramsCo) {
  const binder = await addr(w.desk, 'binder()');
  if (same(binder, ZERO)) return { label: 'SwarmDesk.bind', ok: false, reason: 'Desk.binder() is zero: not a v3.16 Desk' };
  if (keeper && same(binder, keeper)) log('note: the keeper key is the binder; still not sending, sign the printed calldata deliberately');
  const chainId = CHAIN ?? Number(BigInt(await rpc('eth_chainId')));
  let last = 'no artifact';
  for (const [i, rc] of registryCodes.entries()) {
    const pc = (paramsCodes[i] || paramsCodes[0]).code;
    const data = encodeFunction(BIND_SIGNATURE, bindArgs(w, registry, rc.code, pc, registryCo, paramsCo));
    try {
      await rpc('eth_call', [{ from: binder, to: w.desk, data }, 'latest']);
    } catch (e) { last = `${rc.dir}: ${e.rpc?.data || e.message}`; continue; }
    let gas = null;
    try { gas = Number(BigInt(await rpc('eth_estimateGas', [{ from: binder, to: w.desk, data }]))); } catch { gas = null; }
    console.log('');
    console.log('SwarmDesk.bind: sign and send this transaction FROM THE BINDER WALLET (the keeper does not send it)');
    console.log(`  from:     ${binder}   (Desk.binder())`);
    console.log(`  to:       ${w.desk}   (SwarmDesk)`);
    console.log(`  value:    0`);
    console.log(`  chainId:  ${chainId}`);
    console.log(`  gas:      ${gas === null ? 'estimate failed; use the simulation gas plus margin' : `${gas} (estimated from the binder; add margin)`}`);
    console.log(`  args:     bind(${registry}, <${rc.dir} GameRegistry creation code>, <${rc.dir} Params creation code>, ${registryCo.launch}, ${registryCo.index}, ${paramsCo.launch}, ${paramsCo.index}, ${w.tokenLaunch})`);
    console.log(`  data:     ${data}`);
    console.log('  then re-run `wire` (or `wire --step bind-desk`) to verify Desk.registry() before any further step.');
    console.log('');
    return { label: 'SwarmDesk.bind', ok: true, skipped: `calldata printed for the binder ${binder} to sign [${rc.dir}]; simulated from the binder` };
  }
  return { label: 'SwarmDesk.bind', ok: false, reason: last };
}
function print(report) {
  for (const r of report) console.log(`${r.ok ? 'OK  ' : 'SKIP'} ${r.label}${r.skipped ? ` (${r.skipped})` : ''}${r.reason ? ` - ${r.reason}` : ''}${r.hash ? ` ${r.hash}` : ''}${r.dry ? ' [dry-run]' : ''}`);
}

async function pass(m, state) {
  const results = [];
  await scanCommits(m, state);
  const relay = await relayDuties(m, state, results);
  const oracle = await oracleDuties(m, state, results);
  const epoch = await epochDuties(m, results);
  await entropyDuties(m, state, results);
  const season = await seasonDuties(m, results);
  const fees = await feeDuties(m, results);
  const flags = await phaseDuties(m, results);
  const claims = await claimDuties(m, state, results);
  saveState(state);
  return { epoch, season, fees, flags, oracle, relay, claims, results };
}

const FEATURE_NAMES = ['district war', 'grid collapse', 'weekly lots', 'enhancement', 'locks/stake/lobby', 'billboards', 'season pot', 'reserved events'];
async function status() {
  const m = await modules();
  const state = loadState();
  const out = await pass(m, state);
  const now = Math.floor(Date.now() / 1000);
  console.log(`keeper ${keeper || '(no key, read-only)'} chain ${Number(BigInt(await rpc('eth_chainId')))}`);
  if (keeper) console.log(`balance ${Number(BigInt(await rpc('eth_getBalance', [keeper, 'latest']))) / 1e18} ETH`);
  console.log(`epoch ${out.epoch.epoch} live=${out.epoch.live === 1n} ends in ${Number(out.epoch.end) - now}s; week ${out.season.week}`);
  console.log(`fees: hook holds ${out.fees.held} wei, sell batch ${out.fees.sellBatch} tokens, reward ETH ${out.fees.rewardETH}, pot ETH ${out.fees.potETH}`);
  for (const f of out.flags) console.log(`feature ${f.feature} ${FEATURE_NAMES[f.feature]}: ${f.enabled ? 'ENABLED' : f.noticeAt ? `announced, opens ${new Date(f.noticeAt * 1000).toISOString()}` : 'disabled'}`);
  console.log(`SwarmDesk ${m.desk} bound registry ${await addr(m.desk, 'registry()')}`);
  for (const a of out.oracle) console.log(`oracle ${a.stream===0?'event':'regulator'}: last=${a.issuedAt?new Date(a.issuedAt*1000).toISOString():'none'} validUntil=${a.validUntil} pending=${a.pending} slot=${a.slot}`);
  for (const s of out.relay.schedules || []) console.log(`relay ${s.stream===0?'event':'regulator'} schedule ${s.id}: ${s.status}, ${s.runsRemaining} runs left, next ${s.nextRunAt}`);
  if (!SCHEDULES.some(Boolean)) console.log('relay: no SCHEDULE_EVENT / SCHEDULE_REGULATOR configured (backup asks only)');
  const { asset } = await deskQuestions(m.desk);
  console.log(`backup IMD balance ${await uint(asset,'balanceOf(address)',[m.desk])}; last failure ${await call(m.desk,'lastFailure()')}`);
  console.log(`claimFees: ${out.claims ? JSON.stringify(out.claims) : 'LAUNCH_FACTORY / TOKEN_LAUNCH not configured'}`);
  console.log(`pending entropy commits: ${Object.keys(state.pending).length}`);
  const due = out.results.filter((r) => r.ok);
  console.log(due.length ? `due now: ${due.map((r) => r.label).join(', ')}` : 'nothing due');
}

async function main() {
  if (command === 'status') return status();
  if (command === 'wire') return wire();
  const m = await modules();
  if(command==='ask-backup') {
    const name=flag('--stream','event');if(!['event','regulator'].includes(name))throw Error('--stream event|regulator');
    const body=readFileSync(flag('--body',`docs/oracle-v37/${name}.json`));
    const result=await attempt(`paid backup ${name}`,m.desk,'askBackup(uint8,bytes)',[],bytesCall('askBackup(uint8,bytes)',name==='event'?0:1,'0x'+body.toString('hex')));
    console.log(result);return;
  }
  if (command === 'relay') {
    const id = flag('--request', null);
    if (!id) throw Error('relay needs --request UUID');
    const state = loadState();
    const result = await relayOne(m, state, id, `relay ${id}`);
    saveState(state);
    console.log(result);
    return;
  }
  if(!['once','run'].includes(command))throw Error('Command: status, once, run, wire, relay, ask-backup');
  log(`keeper ${keeper || '(dry-run, unsigned)'} registry ${REGISTRY} rpc ${new URL(RPC).host}${dryRun ? ' DRY-RUN' : ''}`);
  const state = loadState();
  do {
    try {
      const out = await pass(m, state);
      const sent = out.results.filter((r) => r.ok && !r.dry).length;
      if (sent) log(`${sent} transaction(s) sent`);
    } catch (e) {
      log('pass failed:', e.message);
    }
    if (command === 'run') await new Promise((r) => setTimeout(r, interval));
  } while (command === 'run');
}
main().catch((e) => { console.error(e.message); process.exit(1); });
