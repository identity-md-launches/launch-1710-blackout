import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {oracleQuestionHash} from '../tools/oracle_question_hash.mjs';
import {scheduleBody,CADENCE} from '../tools/schedule_bodies.mjs';
// v3.10 review M-1: schedule bodies pin the consumer and never carry `deliver` (refused by schedule.create).
const config=JSON.parse(readFileSync('docs/oracle-v37/oracle-config.json','utf8'));
const desk='0x1234567890123456789012345678901234567890'; // local encoder fixture only, never a launch value
for(const [i,name]of ['event','regulator'].entries()) {
 const body=JSON.parse(readFileSync(`docs/oracle-v37/${name}.json`,'utf8'));
 const s=scheduleBody(name,body,desk);
 assert.equal(s.action,'schedule.create');assert.equal(s.input.action,'oracle.request');
 assert.equal('deliver' in s.input.input,false);
 assert.deepEqual(s.input.input.consumer,{chainId:4663,verifyingContract:desk});
 assert.equal(s.input.runs,CADENCE[name].runs);assert.equal(s.input.cadence.cron,CADENCE[name].cron);
 assert.equal(oracleQuestionHash(s.input.input),config.questions[i]); // routing never moves the pinned question
 assert.throws(()=>scheduleBody(name,body,'0x0000000000000000000000000000000000000000'));
 assert.throws(()=>scheduleBody(name,body,'0x1234'));
 assert.throws(()=>scheduleBody(name,{...body,deliver:{chainId:4663}},desk));
}
assert.equal(CADENCE.event.cron,'5 */6 * * *');assert.equal(CADENCE.regulator.cron,'5 0 * * 4');
assert.throws(()=>scheduleBody('other',{},desk));
console.log('oracle-v310 ok');
