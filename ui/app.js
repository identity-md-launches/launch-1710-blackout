import {revealReceipt} from './reveal.js';
const $ = id => document.getElementById(id);
const address = value => /^0x[0-9a-fA-F]{40}$/.test(value) && BigInt(value) !== 0n;
const word = value => BigInt(value).toString(16).padStart(64,'0');
const words = value => (value.slice(2).match(/.{64}/g)||[]).map(x=>BigInt('0x'+x));
const units = value => { if(!/^\d+(\.\d{1,18})?$/.test(value)) throw Error('Enter a positive decimal amount.'); const [a,b='']=value.split('.'); return BigInt(a)*10n**18n+BigInt(b.padEnd(18,'0')); };
const format = value => (Number(value)/1e18).toLocaleString(undefined,{maximumFractionDigits:3});
const status = text => { $('status').textContent=text; };
const stringHex = value => {const bytes=new TextEncoder().encode(value);return word(bytes.length)+[...bytes].map(x=>x.toString(16).padStart(2,'0')).join('').padEnd(Math.ceil(bytes.length/32)*64,'0');};
const decodeString = value => {const offset=Number(BigInt('0x'+value.slice(2,66)))*2+2; const length=Number(BigInt('0x'+value.slice(offset,offset+64))); return new TextDecoder().decode(Uint8Array.from(value.slice(offset+64,offset+64+length*2).match(/../g)||[],x=>parseInt(x,16)));};
let provider, wallet, modules={}, token, list, desk, market, registryAddress, busy=false;
// Generated once from the public Solidity ABI; no remote JavaScript dependency.
const selectors = {
  'enabled(uint256)':'0x76e5c0de',
  'planAt(uint256)':'0x6e922252',
  'lastLetterHash()':'0xe24b9bc9',
  'lastAnswer(uint8)':'0x1b7f4a70',
  'swarmWallet()':'0x82d9f46f',
  'market()':'0x80f55605',
  'registry()':'0x7b103999',
  'fees()':'0x9af1d35a',
  'endowed()':'0xaacd584c',
  'currentBuyTaxBps()':'0x72aba4a9',
  'launchTaxTimeLeft()':'0x1fb8c3bc',
  'params()':'0xcff0ab96',
  "ready()": "0x6defbf80",
  "place(uint256,uint256,uint256)": "0x52121153",
  "unplace(uint256,uint256)": "0xb1a6418e",
  "scrap(uint256,uint256)": "0x84292e79",
  "allowance(address,address)": "0xdd62ed3e",
  "approve(address,uint256)": "0x095ea7b3",
  "bidBillboard(uint256,uint256,string,string)": "0xa7842bf3",
  "billboard(uint256,uint256)": "0x3d73314e",
  "buyPacksFor(address,uint256,uint256)": "0x37356368",
  "buyRoom(uint256,bool)": "0xd15e1e36",
  "buyWithETH(address,uint256,uint256,uint256)": "0xcf50f67f",
  "claim(uint256)": "0x379607f5",
  "claimBest(uint256)": "0xc86c16ee",
  "claimDistrict(uint256)": "0x015e9676",
  "claimFree(uint256,bytes32[])": "0x4c39ee76",
  "claimLottery(uint256)": "0x03c868bb",
  "commit(uint256,uint256,bool)": "0x46cc4ee1",
  "enhanceQuote(uint256)": "0x89d87917",
  "epoch()": "0x900cf0cf",
  "farmDaily(address)": "0x1c93a01f",
  "freeClaimedBy(address)": "0xdaaae4d8",
  "freeRoot()": "0x4df34e78",
  "gridStability(uint256)": "0x64e5a6a5",
  "isOpen()": "0x47535d7b",
  "item(uint256)": "0x898e6219",
  "itemsByOwner(address,uint256,uint256)": "0xe5bbce7b",
  "lobby(uint256,bool)": "0xd0a3e98d",
  "lobbyQuote(address)": "0x27254038",
  "lock(uint256,uint256)": "0x1338736f",
  "lockQuote(address,uint256)": "0xc724f4b0",
  "module(uint256)": "0x430f75da",
  "pending(address)": "0x5eebea20",
  "potRemaining(uint256)": "0x28e59591",
  "price()": "0xa035b1fe",
  "repair(uint256,bool)": "0xb067fd8d",
  "repairQuote(uint256)": "0x8dce33d7",
  "resolve(uint256)": "0x4f896d4f",
  "roomQuote(address,uint256)": "0x80d795a2",
  "setAutoRepair(bool,uint16)": "0x565ce2ac",
  "sync()": "0xfff6cae9",
  "table(uint256)": "0xbafff8c0",
  "token()": "0xfc0c546a",
  "unlock()": "0xa69df4b5",
  "uri(uint256)": "0x0e89341c",
  "week()": "0x4995b458",
  "withdrawRefund()": "0x110f8874"
};
function encode(signature,args=[]) {
 const types=signature.slice(signature.indexOf('(')+1,-1).split(',').filter(Boolean);
 let tail='',head='';
 types.forEach((type,i)=>{if(type==='string'){head+=word(types.length*32+tail.length/2);tail+=stringHex(args[i]);}else head+=word(args[i]===true?1:args[i]===false?0:args[i]);});
 return selectors[signature]+head+tail;
}
async function call(to,signature,args=[]) { return provider.request({method:'eth_call',params:[{to,data:encode(signature,args)},'latest']}); }
async function uint(to,signature,args=[]) {return words(await call(to,signature,args))[0];}
async function send(to,signature,args=[],value=0n,data) {
 const hash=await provider.request({method:'eth_sendTransaction',params:[{from:wallet,to,data:data||encode(signature,args),...(value?{value:'0x'+value.toString(16)}:{})}]});
 status('Transaction submitted. Waiting for confirmation…');
 for(;;) {const receipt=await provider.request({method:'eth_getTransactionReceipt',params:[hash]});if(receipt){if(BigInt(receipt.status)!==1n)throw Error('Transaction reverted. Refresh the quote and check farm gates.');status('Confirmed: '+hash);return receipt;}await new Promise(r=>setTimeout(r,1500));}
}
async function approve(spender,amount) { if(await uint(token,'allowance(address,address)',[wallet,spender])<amount) await send(token,'approve(address,uint256)',[spender,amount]); }
function action(id,fn) { $(id).addEventListener('click',async()=>{if(busy)return;busy=true;$(id).disabled=true;try{if(!wallet)throw Error('Connect your wallet first.');await fn();await refresh();}catch(e){status(e.message||String(e));}finally{busy=false;$(id).disabled=false;}}); }
async function connect() {
 provider=window.ethereum;if(!provider)throw Error('An Ethereum wallet is required.');
 const chain=Number(BigInt(await provider.request({method:'eth_chainId'})));if(chain!==4663&&chain!==46630)throw Error('Select the published BLACKOUT Robinhood network in your wallet.');
 wallet=(await provider.request({method:'eth_requestAccounts'}))[0];
 const registry=$('registry').value.trim();if(!address(registry))throw Error('Enter the published game registry in Game connection.');
 registryAddress=registry;
 for(const role of [0,1,2,3,4,5,6,7,8,10,11,12,13]) {const result=await call(registry,'module(uint256)',[role]);modules[role]='0x'+result.slice(-40);}
 token='0x'+(await call(registry,'token()')).slice(-40);market='0x'+(await call(registry,'market()')).slice(-40);
 const params='0x'+(await call(registry,'params()')).slice(-40);desk='0x'+(await call(params,'swarmWallet()')).slice(-40);
 $('connect').textContent=wallet.slice(0,6)+'…'+wallet.slice(-4);
 try{const response=await fetch('./allowlist.json',{cache:'no-store'});if(response.ok)list=await response.json();}catch{list=null;}
 await refresh();status('Connected. Quotes use the last settled mining rate.');
}
const phases={};
// v3.6 phased release: enabled features show; disabled ones are a "coming soon" teaser; dormant modules never appear.
async function applyPhases() {
 for(const el of document.querySelectorAll('[data-feature]')) {const f=Number(el.dataset.feature);phases[f]=Boolean(await uint(modules[12],'enabled(uint256)',[f]));
  if(phases[f]){el.hidden=false;el.querySelector('.teaser')?.remove();for(const c of Array.from(el.children))c.hidden=false;}
  else{el.hidden=false;if(!el.querySelector('.teaser')){const t=document.createElement('p');t.className='teaser';t.textContent=el.dataset.teaser;for(const c of Array.from(el.children))c.hidden=true;el.append(t);}}}
}
const EVENT_NAMES=['Calm','Outage','Surge','Fire','Theft','Audit','Green','Cheap','Heatwave','Festival'];
async function refreshSwarm() {
 if(!desk)return;
 const [event,regulator,epoch,letter]=await Promise.all([call(desk,'lastAnswer(uint8)',[0]),call(desk,'lastAnswer(uint8)',[1]),uint(modules[1],'epoch()'),call(desk,'lastLetterHash()')]);
 const entries=[['Event',words(event)],['Regulator',words(regulator)]];
 const summaries=await Promise.all(entries.map(async([label,a])=>{
  if(!a[2])return `${label}: no answer yet`;
  const block='0x'+a[6].toString(16);
  let logs=[];try{logs=await provider.request({method:'eth_getLogs',params:[{address:desk,fromBlock:block,toBlock:block,topics:['0xd2ea08b0365395dc0170ec82f63022befc31a673700c0106372066335219b63f',null,'0x'+word(a[1])]}]});}catch{/* Receipt metadata still renders if this RPC does not serve logs. */}
  const log=logs.find(x=>!x.removed);let detail='';
  if(log){const raw=words(log.data);const v=raw.slice(5);detail=label==='Event'?` · base epoch ${v[1]}, kind ${v[2]}, severity ${v[3]}, district hint ${v[4]}`:` · feature code ${v[9]}, cap step ${v[10]}`;}
  return `${label}: ${new Date(Number(a[2])*1000).toLocaleString()}${detail}${a[5]===1n?' · awaiting execution':''}`;
 }));
 $('swarmAnswer').textContent=summaries.join(' | ');
 const p=words(await call(modules[7],'planAt(uint256)',[epoch+1n]));
 // A dynamic Plan tuple has an outer offset, then kind,severity,number,letter offset,submitted.
 $('nextPlan').textContent=p[5]===1n?`Epoch ${epoch+1n}: ${EVENT_NAMES[Number(p[1])]} · severity ${p[2]} / 10000`:`Epoch ${epoch+1n}: autonomous fallback (no submitted plan)`;
 $('swarmLetter').textContent=BigInt(letter)!==0n?`Last applied letter hash: ${letter}`:'No off-chain letter attached to the last applied answer.';
}
// v3.9: the wiring every player can verify: the Desk bound to this registry, the hook bound to this FeeRouter, the endowment funded.
async function refreshWiring() {
 if(!desk||!market)return;
 const same=(a,b)=>a.toLowerCase()===b.toLowerCase();
 const [bound,router,endowed,tax,left]=await Promise.all([call(desk,'registry()'),call(market,'fees()'),uint(modules[0],'endowed()'),uint(market,'currentBuyTaxBps()'),uint(market,'launchTaxTimeLeft()')]);
 const parts=[`Swarm desk bound to this registry: ${same('0x'+bound.slice(-40),registryAddress)?'yes':'NO'}`,`Hook fee router bound: ${same('0x'+router.slice(-40),modules[6])?'yes':'NO'}`,`Endowment funded: ${endowed?'yes':'not yet'}`];
 $('wiring').textContent=parts.join(' · ');
 $('hookFee').textContent=left>0n?`Launch window: buys pay ${Number(tax)/100}% to the mining pool for another ${Number(left)} s (steps 90/50/25%), then 1%. The pool's 1.25% fee is the platform's.`:'Swap fees: 1.25% pool fee (platform) plus the hook\'s 1% to the mining pool on every swap; sells add the progressive surcharge.';
}
async function refresh() {
 if(!wallet||!modules[4])return;
 await applyPhases();
 await refreshSwarm();
 await refreshWiring();
 const [price,daily,pending,open,epoch]=await Promise.all([uint(modules[4],'price()'),uint(modules[10],'farmDaily(address)',[wallet]),uint(modules[1],'pending(address)',[wallet]),uint(modules[4],'ready()'),uint(modules[1],'epoch()')]);
 $('packPrice').textContent=format(price)+' tokens';$('daily').textContent=format(daily)+' tokens';$('pending').textContent=format(pending)+' tokens';$('saleStatus').textContent=open?'Open · epoch '+epoch:'Closed / paused';
 const listed=list?.claims?.[wallet.toLowerCase()];const root=await call(modules[5],'freeRoot()');const claimed=await uint(modules[5],'freeClaimedBy(address)',[wallet]);
 $('free').hidden=!(listed&&list.root.toLowerCase()===root.toLowerCase()&&!claimed);$('freeLink').hidden=!$('free').hidden;
 $('items').replaceChildren();const ids=words(await call(modules[3],'itemsByOwner(address,uint256,uint256)',[wallet,0,100])).slice(2);
 for(const id of ids) {const uri=decodeString(await call(modules[3],'uri(uint256)',[id]));if(!uri.startsWith('data:application/json;base64,'))continue;const metadata=JSON.parse(atob(uri.split(',')[1]));const card=document.createElement('div');card.className='machine';const img=document.createElement('img');if(metadata.image.startsWith('data:image/svg+xml;base64,'))img.src=metadata.image;img.alt=metadata.name;const text=document.createElement('div');text.textContent="#"+id+" · "+metadata.name;card.append(img,text);const details=document.createElement('small');details.textContent=metadata.attributes.filter(a=>['Rarity','Durability bps','Output tier bps','Starter'].includes(a.trait_type)).map(a=>a.trait_type+': '+a.value).join(' · ');card.append(details);$('items').append(card);}
 $('grid').replaceChildren();for(let d=0;d<8;d++){const stable=await uint(modules[7],'gridStability(uint256)',[d]);const card=document.createElement('div');card.className='district';const title=document.createElement('strong');title.textContent='DISTRICT '+d;const value=document.createElement('span');value.textContent='Grid stability '+(Number(stable)/10000).toFixed(2)+'×';card.append(title,value);$('grid').append(card);}
 if(phases[5])await loadBoards();
}
async function loadBoards(){const w=await uint(modules[13],'week()');$('boards').replaceChildren();for(let d=0;d<8;d++){const raw=await call(modules[13],'billboard(uint256,uint256)',[w,d]);const base=Number(words(raw)[0])*2+2;const tuple='0x'+raw.slice(base);const parts=words(tuple);const read=index=>{const at=Number(parts[index])*2+2,len=Number(BigInt('0x'+tuple.slice(at,at+64)));return new TextDecoder().decode(Uint8Array.from(tuple.slice(at+64,at+64+len*2).match(/../g)||[],x=>parseInt(x,16)));};const row=document.createElement('div');row.className='board';row.textContent='District '+d+' · '+(parts[0]?read(2)+' @'+read(3):'Open for your message');$('boards').append(row);}}
$('registry').value=localStorage.getItem('blackout.registry')||'';
$('save').onclick=()=>{if(!address($('registry').value.trim()))return status('Enter a valid, nonzero registry address.');localStorage.setItem('blackout.registry',$('registry').value.trim());status('Connection saved. Connect your wallet.');};
$('connect').onclick=()=>connect().catch(e=>status(e.message));
action('buy',async()=>{const recipient=$('recipient').value.trim()||wallet;if(!address(recipient))throw Error('Invalid recipient.');const price=await uint(modules[4],'price()');await approve(modules[4],price);await send(modules[4],'buyPacksFor(address,uint256,uint256)',[recipient,1,price]);});
action('zap',async()=>{const recipient=$('recipient').value.trim()||wallet;if(!address(recipient))throw Error('Invalid recipient.');const price=await uint(modules[4],'price()');await send(modules[4],'buyWithETH(address,uint256,uint256,uint256)',[recipient,1,units($('minTokens').value),price],units($('eth').value));});
action('free',async()=>{const claim=list.claims[wallet.toLowerCase()];const data=selectors['claimFree(uint256,bytes32[])']+word(claim.index)+word(64)+word(claim.proof.length)+claim.proof.map(x=>x.slice(2)).join('');const receipt=await send(modules[5],'claimFree(uint256,bytes32[])',[],0n,data);$('receipt').value=((1n<<255n)|BigInt(claim.index)).toString();$('starterReceipt').checked=true;status('Free pack claimed. Reveal receipt '+$('receipt').value);});
action('sync',()=>send(modules[2],'sync()'));
action('claim',async()=>send(modules[1],'claim(uint256)',[await uint(modules[1],'pending(address)',[wallet])]));
action('auto',()=>send(modules[2],'setAutoRepair(bool,uint16)',[true,Number($('threshold').value)*100]));
action('autoOff',()=>send(modules[2],'setAutoRepair(bool,uint16)',[false,8000]));
action('roomBuy',async()=>{const room=BigInt($('room').value),price=await uint(modules[10],'roomQuote(address,uint256)',[wallet,room]);await approve(modules[2],price);await send(modules[2],'buyRoom(uint256,bool)',[room,true]);});
action('repairQuote',async()=>{const id=$('item').value;const repair=await uint(modules[10],'repairQuote(uint256)',[id]);let text='Repair '+format(repair)+' tokens';if(phases[3])text+=' · Enhance '+format(await uint(modules[10],'enhanceQuote(uint256)',[id]))+' tokens';$('quotes').textContent=text;});
action('repair',async()=>{const id=$('item').value;await approve(modules[2],await uint(modules[10],'repairQuote(uint256)',[id]));await send(modules[2],'repair(uint256,bool)',[id,true]);});
action('enhance',async()=>{const id=$('item').value,price=await uint(modules[10],'enhanceQuote(uint256)',[id]);const state=words(await call(modules[3],'item(uint256)',[id])),target=state[4]+1n;const table=words(await call(modules[11],'table(uint256)',[target]));if(!confirm('Enhance to +'+target+' for '+format(price)+' tokens? Success '+table[0]+'%. Burn chance on failure '+table[1]+'%.'))return;await approve(modules[2],price);const receipt=await send(modules[11],'commit(uint256,uint256,bool)',[id,price,true]);const log=receipt.logs.find(l=>l.address.toLowerCase()===modules[11].toLowerCase()&&l.topics.length===4);if(log)$('enhanceReceipt').value=BigInt(log.topics[1]).toString();});
action('enhanceResolve',()=>send(modules[11],'resolve(uint256)',[$('enhanceReceipt').value]));
action('lock',async()=>{const days=$('lockDays').value,amount=words(await call(modules[10],'lockQuote(address,uint256)',[wallet,days]))[0];await approve(modules[10],amount);await send(modules[10],'lock(uint256,uint256)',[amount,days]);});
action('unlock',()=>send(modules[10],'unlock()'));
action('lobby',async()=>{const amount=await uint(modules[10],'lobbyQuote(address)',[wallet]);await approve(modules[2],amount);await send(modules[2],'lobby(uint256,bool)',[amount,true]);});
action('reveal',()=>revealReceipt({provider,contract:modules[$('starterReceipt').checked?5:4],receipt:$('receipt').value,starter:$('starterReceipt').checked,onStatus:status}));
action('pot',async()=>{$('potValue').textContent=format(await uint(modules[8],'potRemaining(uint256)',[$('week').value]))+' unclaimed tokens';});
for(const [id,signature]of[['best','claimBest(uint256)'],['lottery','claimLottery(uint256)'],['districtPrize','claimDistrict(uint256)']])action(id,()=>send(modules[8],signature,[$('week').value]));
action('billboardBid',async()=>{const amount=units($('bid').value);await approve(modules[13],amount);await send(modules[13],'bidBillboard(uint256,uint256,string,string)',[$('billboardDistrict').value,amount,$('billboardText').value,$('handle').value]);});
action('refund',()=>send(modules[13],'withdrawRefund()'));
window.ethereum?.on?.('accountsChanged',()=>location.reload());window.ethereum?.on?.('chainChanged',()=>location.reload());

action('install',()=>send(modules[2],'place(uint256,uint256,uint256)',[$('item').value,Number($('installRoom').value)-1,Number($('installSlot').value)-1]));
action('uninstall',()=>send(modules[2],'unplace(uint256,uint256)',[Number($('installRoom').value)-1,Number($('installSlot').value)-1]));
action('scrap',()=>{if(confirm('Permanently scrap this unequipped item for its current token quote?'))return send(modules[2],'scrap(uint256,uint256)',[$('item').value,0]);});
