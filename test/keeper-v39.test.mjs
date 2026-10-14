import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {encodeFunction, encodeTuple, isDynamic} from '../keeper/lib/abi.mjs';
import {encodeSubmit, attestationValues, scheduleRequestIds, SUBMIT_SIGNATURE, answerTypeCode} from '../keeper/lib/oracle.mjs';
import {keccak256, utf8} from '../keeper/lib/eth.mjs';
const v = JSON.parse(readFileSync('test/fixtures/keeper-v39-vectors.json', 'utf8'));
// The relay must reproduce `cast calldata` byte for byte for the live protocol attestation shape.
const doc = {primaryType: 'OracleAttestation', domain: {name: 'IdentityMD Oracle', version: '2', chainId: 4663, verifyingContract: '0x00000000000000000000000000000000000000AA'},
  types: {OracleAttestation: ['requestId','chainId','questionHash','answerType','answer','figure','fromBlock','toBlock','blockHash','panelJobId','panelSize','quorum','agreed','issuedAt','expiresAt'].map((name) => ({name}))},
  message: v.attestation, signature: v.signature};
const values = attestationValues(doc, {desk: '0x00000000000000000000000000000000000000aa', chainId: 4663});
assert.equal(encodeSubmit(values, v.signature), v.submitCalldata);
assert.equal(keccak256(utf8(SUBMIT_SIGNATURE)).slice(0, 10), '0x4b663b87');
assert.equal(answerTypeCode('bytes32[]'), 5n);
assert.throws(() => attestationValues(doc, {desk: '0x00000000000000000000000000000000000000bb'}), /not the Desk/);
assert.throws(() => attestationValues(doc, {chainId: 1}), /chain/);
assert.throws(() => attestationValues({...doc, domain: {...doc.domain, version: '1'}}, {}), /domain/);
assert.throws(() => attestationValues({...doc, types: {OracleAttestation: doc.types.OracleAttestation.slice(0, 12)}}, {}), /struct/);
assert.throws(() => encodeSubmit(values, '0x1234'));
// Wiring encoders.
assert.equal(encodeFunction('register(uint256,uint64,uint256,bytes)', v.register.args), v.register.calldata);
assert.equal(encodeFunction('bind(address,bytes,bytes,uint64,uint8,uint64,uint8,uint64)', v.bind.args), v.bind.calldata);
assert.equal(encodeFunction('forward(address,uint64,uint256,bytes,uint64,uint256,bytes)', v.forward.args), v.forward.calldata);
assert.equal(encodeFunction('claimFees(uint64)', [1316]).slice(0, 10), '0xe0d0eac4');
assert.equal(encodeFunction('bindFeeRouter(address,uint64,uint256)', [v.bind.args[0], 1401, 1]).slice(0, 10), '0x66777422');
assert.equal(encodeTuple(['bool', 'bytes4'], [true, '0x510379c7']), '0'.repeat(63) + '1' + '510379c7' + '0'.repeat(56));
assert.ok(isDynamic('(bytes32,bytes)') && !isDynamic('(bytes32,uint8)') && isDynamic('bytes32[]'));
assert.throws(() => encodeFunction('f(uint8)', [256]));
assert.throws(() => encodeFunction('f(address)', ['0x12']));
// Schedule run selection: opened oracle runs only, newest first.
const schedule = {latest: [{status: 'skipped', result: null}, {status: 'opened', result: {kind: 'oracle', id: 'b'}}, {status: 'failed'}, {status: 'opened', result: {kind: 'oracle', id: 'a'}}]};
assert.deepEqual(scheduleRequestIds(schedule), ['b', 'a']);
assert.deepEqual(scheduleRequestIds(schedule, 1), ['b']);
console.log('keeper v3.9 relay and wiring encoders match cast vectors; attestation document checks pass.');
