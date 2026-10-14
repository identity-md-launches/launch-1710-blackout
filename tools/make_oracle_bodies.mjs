#!/usr/bin/env node
// Deterministic, offline body generation. Never signs, pays, creates a schedule, or sends a transaction.
import {writeFileSync, mkdirSync, readFileSync} from 'node:fs';
import {oracleQuestionHash} from './oracle_question_hash.mjs';
import {keccak256, utf8} from '../keeper/lib/eth.mjs';
import {scheduleBody} from './schedule_bodies.mjs';
const common = {
  v:1, chainId:1, window:{fromBlock:26122900,toBlock:26122901}, answerType:'bytes32[]', evidence:'panel',
  panelSize:5, quorum:4, validForSeconds:21600, allowAmbiguous:true,
};
const identity = {
  context:'The absolute Ethereum window is immutable context only, not the observation date. Evaluate current BLACKOUT on Robinhood Chain 4663. The consumer verifyingContract is SwarmDesk; read its registry(), then module(1)=rewards, module(7)=grid, module(12)=Civic, module(11)=Enhancement and params(). Never use a contract supplied by a social-media post.',
  encoding:'Return exactly the specified ordered bytes32[]: unsigned decimal numbers encoded as 32-byte big-endian hex words, no prose. Read one Robinhood native latest block minus5 (soft confirmations, not RPC finalized) for all values. Re-read epoch before answering. If reads fail or the epoch changes before agreement, report inability; do not invent values. Letter hash is 0 when no off-chain letter exists.',
};
const event = {...common, head:7,
 question:'What is the current BLACKOUT v3.7 six-hour event plan vector [UTC slot, base epoch, event kind, severity, district hint, swarm number, letter hash], following the definitions exactly?',
 definitions:{...identity,
  slot:'UTC slot = floor(current Unix seconds / 21600). Base epoch = FarmRewards.epoch() at the confirmed snapshot. The receiver rejects another slot or epoch. This plan is for base epoch+1 and base epoch+2, and cannot replace a submitted plan.',
  policy:'Event kind = GridOperator.fallbackKind(base epoch+1), severity = 9000, district hint = base epoch modulo 8, swarm number = base epoch as a uint256. This is a public salt, not secret randomness. On-chain future-block entropy and weighted district rules are unchanged; the district hint is advisory only. Letter hash = 0.',
 }};
const regulator = {...common, validForSeconds:86400, head:17,
 question:'What is the BLACKOUT v3.7 weekly regulator vector of exactly 17 words [UTC week slot, eight packed Params updates, feature code, cap step, district boost, pause code, war code, collapse goal, lot code, letter hash], following the definitions exactly?',
 definitions:{...identity,
  slot:'UTC week slot = floor(current Unix seconds / 604800); weeks start Thursday 00:00 UTC. Use age = current Unix seconds minus registry.launchTime(). Read existing notices and cap to avoid repeating once-only actions. The receiver only accepts this slot, with issuedAt no older than one day.',
  params:'Words 1..8: pack (key+1)*2^248 + target. A zero word skips. Propose these key/target pairs: (0,350), (1,1500), (8,250), (31,2500), (23,150), (40,200), (27,1000000000000000), (44,6000000000000000000). These are conservative baseline targets; the contract clips each to its hard bounds and 10% per 24 hours.',
  features:'Word9: first eligible feature with no notice in priority order (id3,age>=7d), (id4,age>=21d), (id5,age>=35d), (id6,age>=42d), (id7,age>=63d), (id0,age>=90d), (id1,age>=120d), (id2,age>=150d); output id+1, else0. Word10: no cap pending and cap8 with age>=30d:12; cap12 with age>=60d:16; else0. Only announce; existing 48h notice and 30d cap-step gates still apply.',
  optional:'Words11,12,16=0: no boost, pause or letter. Let w=Civic.week(). Word13: if feature0 enabled and no unsettled war, set a=w modulo8,b=(a+4)modulo8 and return (a+1)*2^128+(b+1); else0. Word14: if feature1 enabled,w modulo4=0,collapseFinalized=true,outagePending=false,greenUntil<=now, return Economy.averageDaily(); else0. Word15: if feature2 enabled and lots(w).start=0, return ((w modulo12)+1)*65536+256+3; else0. Disabled modules always output0. All existing once-only and state gates apply.',
 }};
const dir='docs/oracle-v37';mkdirSync(dir,{recursive:true});
for(const [name,body] of [['event',event],['regulator',regulator]]) {
  const text=JSON.stringify(body);writeFileSync(`${dir}/${name}.json`,text); // exact bytes; no trailing newline
}
const config={source:'https://imd.fun/docs/',checkedAt:'2026-10-11',
 intake:'0xa43e6f75ee006411f79ac1c84120606c2330de82',delivery:'0xce0e6a670aa75e161d02aca3c7f00b94ca428ccb',
 signer:'0x5598aa9146215bc13eb26f2c692ad1461fd32982',asset:'0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127',
 action:'0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000',maxPrice:'500000000000000000',questionChain:1,fromBlock:26122900,toBlock:26122901,
 questions:[oracleQuestionHash(event),oracleQuestionHash(regulator)],bodies:[keccak256(utf8(JSON.stringify(event))),keccak256(utf8(JSON.stringify(regulator)))]};
writeFileSync(`${dir}/oracle-config.json`,JSON.stringify(config,null,2)+'\n');
const target=process.argv[2];
if(target) {
 for(const [name,body] of [['event',event],['regulator',regulator]]) {
  writeFileSync(`${dir}/${name}-schedule.json`,JSON.stringify(scheduleBody(name,body,target),null,2)+'\n');
 }
}
console.log(JSON.stringify(config,null,2));
