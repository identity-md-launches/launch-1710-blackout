// v3.10: `schedule.create` bodies for the two recurring questions. Offline; never pays or creates anything.
// Schedules are bought on Ethereum and cannot deliver to another chain: `schedule.create` refuses a `deliver`
// key (research job b94e6839, finding C1). The input instead pins `consumer {chainId: 4663, verifyingContract:
// Desk}` so the attestation is signed in the Desk's own EIP-712 domain, and a keeper relays it with
// SwarmDesk.submit. `consumer` is not part of questionHash, so the Desk's pinned question commitments still hold.
export const CADENCE={event:{cron:'5 */6 * * *',tz:'UTC',runs:28},regulator:{cron:'5 0 * * 4',tz:'UTC',runs:4}};

export function scheduleBody(name,body,desk,consumerChain=4663) {
  if(!(name in CADENCE))throw Error(`Unknown stream ${name}`);
  if(typeof desk!=='string'||!/^0x[0-9a-fA-F]{40}$/.test(desk)||BigInt(desk)===0n)throw Error('Supply the real deployed SwarmDesk');
  if(!Number.isSafeInteger(consumerChain)||consumerChain<=0)throw Error('Invalid consumer chain');
  if('deliver' in body||'consumer' in body)throw Error('Committed body must not carry routing');
  const {cron,tz,runs}=CADENCE[name];
  const input={...body,consumer:{chainId:consumerChain,verifyingContract:desk}};
  return {action:'schedule.create',input:{label:`BLACKOUT v3.10 ${name}`,action:'oracle.request',cadence:{cron,tz},runs,input}};
}
