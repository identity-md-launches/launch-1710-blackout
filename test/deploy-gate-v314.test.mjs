import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkDeployGate,protocolAddresses} from '../tools/check_deploy_gate.mjs';
import {swarmConstructorArgs} from '../tools/swarm_constructor_args.mjs';
const plan = JSON.parse(readFileSync(new URL('../docs/launch-v314-plan.json',import.meta.url)));
test('four launches, correct order, named references, and no forbidden constructor literals', () => {
  assert.equal(plan.launches.length,4);
  assert.deepEqual(plan.launches[0].contracts.map(c=>c.name),['SwarmDesk','EndowmentEscrow']);
  assert.deepEqual(plan.launches[0].contracts[1].constructorArgs,['$contract:SwarmDesk']);
  assert.equal(plan.launches[1].onchain,'univ4_hook');
  assert.equal(plan.launches[1].pairWith,'eth');
  assert.equal(plan.launches[1].economics.poolBps,7000);
  assert.equal(checkDeployGate(plan),19);
});
test('every forbidden address is rejected in every launch, including padded and decimal words', () => {
  for (let launch=0;launch<4;launch++) for (const addr of Object.values(protocolAddresses)) {
    for (const word of [addr,addr.toUpperCase(),`0x${addr.slice(2).padStart(64,'0')}`,BigInt(addr).toString(),` ${addr} `]) {
      const bad=structuredClone(plan);
      bad.launches[launch].contracts.at(-1).constructorArgs.push(word);
      assert.throws(()=>checkDeployGate(bad),/forbidden IMD protocol address/);
    }
  }
});
test('allowed platform references pass; empty plans fail closed',()=>{
  assert.equal(checkDeployGate({constructorArgs:['$poolManager','$token','$factory','$contract:Params']}),1);
  assert.throws(()=>checkDeployGate({launches:[]}),/No constructor/);
});
test('Desk launch words match the offline encoder and reject endpoint drift',()=>{
  const o=JSON.parse(readFileSync(new URL('../docs/oracle-v37/oracle-config.json',import.meta.url)));
  const binder='0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007'; // v3.16 word 8: the project wallet, not a protocol address
  const b={factory:protocolAddresses.ProjectFactory,heartbeatBps:200,heartbeatCap:'1000000000000000000',gameConfigHash:plan.gameConfigHash,binder};
  const words=swarmConstructorArgs(o,b);
  assert.equal(words.length,8);
  assert.deepEqual(words,plan.launches[0].contracts[0].constructorArgs);
  assert.equal(words[7],binder);
  assert.throws(()=>swarmConstructorArgs(o,{...b,binder:undefined}),/binder is required/);
  assert.throws(()=>swarmConstructorArgs(o,{...b,binder:'0x'+'0'.repeat(40)}),/Invalid binder/);
  assert.throws(()=>swarmConstructorArgs(o,{...b,binder:protocolAddresses.LaunchFactory}),/protocol address/);
  assert.throws(()=>swarmConstructorArgs({...o,signer:protocolAddresses.Intake},b),/Fixed Robinhood/);
  assert.throws(()=>swarmConstructorArgs(o,{...b,factory:protocolAddresses.LaunchFactory}),/Fixed Robinhood/);
});
