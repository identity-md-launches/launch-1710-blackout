#!/usr/bin/env node
// Offline IMD manifest preflight. This file reads launch plans; it never submits a launch.
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
export const protocolAddresses = Object.freeze({
  ProjectFactory: '0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e',
  ProjectRegistry: '0xf52bbe066b7ad2d28c2195d066ea08dcbca88406',
  Intake: '0xa43e6f75ee006411f79ac1c84120606c2330de82',
  IntakeDelivery: '0xce0e6a670aa75e161d02aca3c7f00b94ca428ccb',
  attester: '0x5598aa9146215bc13eb26f2c692ad1461fd32982',
  IMD: '0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127',
  LaunchFactory: '0xa25b02a1e93903b790e6aaf7da1b8b8d50294645',
  PoolManager: '0x8366a39cc670b4001a1121b8f6a443a643e40951',
});
const forbidden = new Map(Object.entries(protocolAddresses).map(([name,value]) => [BigInt(value).toString(),name]));
export function checkDeployGate(plan) {
  let count = 0;
  function checkWord(word, path) {
    if (Array.isArray(word)) { word.forEach((v,i)=>checkWord(v,`${path}[${i}]`)); return; }
    if (word && typeof word === 'object') { Object.entries(word).forEach(([k,v])=>checkWord(v,`${path}.${k}`)); return; }
    if (typeof word === 'number' && !Number.isSafeInteger(word)) throw Error(`${path}: unsafe numeric constructor word`);
    const text = String(word).trim();
    if (/^(0x[0-9a-f]+|[0-9]+)$/i.test(text)) {
      const name = forbidden.get(BigInt(text).toString());
      if (name) throw Error(`${path}: forbidden IMD protocol address (${name}); use compiled constants or allowed platform references`);
    }
  }
  function walk(node,path) {
    if (!node || typeof node !== 'object') return;
    for (const [key,value] of Object.entries(node)) {
      if (/^constructor(Args|Arguments|Words)?$/i.test(key)) {
        if (!Array.isArray(value)) throw Error(`${path}.${key}: expected constructor words array`);
        count++;
        checkWord(value,`${path}.${key}`);
      } else walk(value,`${path}.${key}`);
    }
  }
  walk(plan,'launches');
  if (count === 0) throw Error('No constructor words found: refusing an empty preflight');
  return count;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const files = process.argv.slice(2);
  for (const file of files.length ? files : ['docs/launch-v314-plan.json']) {
    const count = checkDeployGate(JSON.parse(readFileSync(file,'utf8')));
    console.log(`${file}: PASS — ${count} constructors contain no literal IMD protocol addresses`);
  }
}
