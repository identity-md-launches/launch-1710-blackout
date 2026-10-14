import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const elements = new Map();
const document = {getElementById(id) {
  if (!elements.has(id)) elements.set(id, {value:'',hidden:false,disabled:false,textContent:'',addEventListener(){}});
  return elements.get(id);
}};
const source = fs.readFileSync(new URL('../ui/app.js', import.meta.url),'utf8').replace(/^import .*;\n/, '');
const context = vm.createContext({document,window:{},localStorage:{getItem(){return null;}},TextEncoder,TextDecoder,Uint8Array,BigInt,Number,Error,JSON,Map,Promise,console,confirm(){return false;}});
vm.runInContext(source, context);
const run = code => vm.runInContext(code, context);
const w = n => BigInt(n).toString(16).padStart(64,'0');
assert.equal(run("units('1.000000000000000001')"), 1000000000000000001n);
assert.throws(()=>run("units('1.0000000000000000001')"));
assert.throws(()=>run("units('-1')"));
assert.equal(run("address('0x0000000000000000000000000000000000000000')"), false);
assert.equal(run("encode('repair(uint256,bool)',[7,true])"), '0xb067fd8d'+w(7)+w(1));
const encoded = run("encode('bidBillboard(uint256,uint256,string,string)',[3,123,'HI','x'])");
assert.equal(encoded, '0xa7842bf3'+w(3)+w(123)+w(128)+w(192)+w(2)+'4849'.padEnd(64,'0')+w(1)+'78'.padEnd(64,'0'));
const uri = 'data:application/json;base64,eyJuYW1lIjoiKzcgQVNJQyJ9';
const bytes = Buffer.from(uri);
const response='0x'+w(32)+w(bytes.length)+bytes.toString('hex').padEnd(Math.ceil(bytes.length/32)*64,'0');
assert.equal(run('decodeString('+JSON.stringify(response)+')'),uri);
assert.ok(!source.includes('startWar(') && !source.includes('buyLot(') && !source.includes('fundCollapse('));
console.log('v3.5 UI: precise amounts, address validation, static/dynamic ABI encoding and metadata decoding passed.');
