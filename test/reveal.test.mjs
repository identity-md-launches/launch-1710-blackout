import {readFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const source = readFileSync(new URL('../ui/reveal.js',import.meta.url),'utf8');
const {revealReceipt} = await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const abi = ns => '0x'+ns.map(n=>BigInt(n).toString(16).padStart(64,'0')).join('');
for (const expired of [false,true]) {
  let opened=0, sent=0, rearmed=false;
  const provider={request:async ({method,params})=>{
    if(method==='eth_requestAccounts')return ['0x1234'];
    if(method==='eth_chainId')return '0x7a69';
    if(method==='eth_blockNumber')return '0x190';
    if(method==='eth_call')return abi([1,102,1,opened,0,0,1,expired?0:1,0]);
    if(method==='eth_sendTransaction'){
      assert.equal(params[0].data.slice(0,10),'0xd1691a6f');sent++;
      if(expired&&!rearmed)rearmed=true;else opened=1;
      return '0xabc';
    }
    if(method==='eth_getTransactionReceipt')return {status:'0x1'};
    throw Error(method);
  }};
  await revealReceipt({provider,contract:'0x5678',receipt:1,pollMs:1});
  assert.equal(sent,expired?2:1);assert.equal(opened,1);
}
console.log('Reveal: captured receipt and expired/rearmed receipt complete from one invocation.');
