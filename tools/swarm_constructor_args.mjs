#!/usr/bin/env node
// Offline packing for the launcher's eight-word SwarmDesk constructor (v3.14 policy word, v3.16 binder). No RPC or signing.
// Word 8 is the binder: the project wallet that signs the one bind call. It must be a nonzero address and never an IMD protocol address.
// policyWord = chainId[0:32] | fromBlock[32:80] | toBlock[80:128] | maxPrice[128:224] | heartbeatBps[224:240].
import {protocolAddresses} from './check_deploy_gate.mjs';
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';

function uint(value,bits,name,min=0n) {
  if(typeof value==='number'&&!Number.isSafeInteger(value))throw Error(`Use a decimal string for ${name}`);
  let n;try{n=BigInt(value);}catch{throw Error(`Invalid ${name}`);}
  if(n<min||n>=(1n<<BigInt(bits)))throw Error(`Out of range ${name}`);
  return n;
}
function address(value,name) {
  if(!/^0x[0-9a-fA-F]{40}$/.test(value)||BigInt(value)===0n)throw Error(`Invalid ${name}`);
  return value;
}
function hash(value,name) {
  if(!/^0x[0-9a-fA-F]{64}$/.test(value)||BigInt(value)===0n)throw Error(`Invalid ${name}`);
  return value;
}
export function policyWord(o,b) {
  const chain=uint(o.questionChain,32,'questionChain',1n),from=uint(o.fromBlock,48,'fromBlock'),to=uint(o.toBlock,48,'toBlock');
  if(to<from)throw Error('Reversed context window');
  const price=uint(o.maxPrice,96,'maxPrice',1n);
  const rl=uint(b.registryLaunch??0,64,'registryLaunch'),ri=uint(b.registryIndex??0,3,'registryIndex');
  const pl=uint(b.paramsLaunch??0,64,'paramsLaunch'),pi=uint(b.paramsIndex??0,3,'paramsIndex');
  if(rl!==0n||ri!==0n||pl!==0n||pi!==0n)throw Error('Launch coordinates are proven at bind time, not in the constructor');
  const bps=uint(b.heartbeatBps,16,'heartbeatBps');
  if(bps<200n||bps>5000n||BigInt(b.heartbeatCap)!==10n**18n)throw Error('Invalid heartbeat configuration');
  return chain|(from<<32n)|(to<<80n)|(price<<128n)|(bps<<224n);
}
export function binderWord(b) {
  if(b.binder===undefined||b.binder===null)throw Error('binder is required (v3.16): the project wallet that signs bind');
  const value=address(b.binder,'binder');
  for (const [name,fixed] of Object.entries(protocolAddresses)) {
    if(value.toLowerCase()===fixed) throw Error(`binder must not be an IMD protocol address (${name})`);
  }
  return value;
}
export function swarmConstructorArgs(o,b) {
  if(o.intake.toLowerCase()===o.delivery.toLowerCase())throw Error('Duplicate callback endpoints');
  if(o.questions[0].toLowerCase()===o.questions[1].toLowerCase())throw Error('Duplicate question commitments');
  for (const [key,name] of [['intake','Intake'],['delivery','IntakeDelivery'],['signer','attester'],['asset','IMD']]) {
    if(address(o[key],key).toLowerCase()!==protocolAddresses[name]) throw Error(`Fixed Robinhood endpoint: ${key}`);
  }
  if(address(b.factory,'factory').toLowerCase()!==protocolAddresses.ProjectFactory) throw Error('Fixed Robinhood ProjectFactory');
  return [hash(o.action,'action'),policyWord(o,b).toString(),
    hash(o.questions[0],'eventQuestion'),hash(o.questions[1],'regulatorQuestion'),hash(o.bodies[0],'eventBody'),hash(o.bodies[1],'regulatorBody'),
    hash(b.gameConfigHash,'gameConfigHash'),binderWord(b)];
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  if(process.argv.length!==4)throw Error('Usage: node tools/swarm_constructor_args.mjs oracle-config.json approved-binding.json');
  const [o,b]=process.argv.slice(2).map(p=>JSON.parse(readFileSync(p,'utf8')));
  console.log(JSON.stringify({constructorArgs:swarmConstructorArgs(o,b)},null,2));
}
