#!/usr/bin/env python3
"""Permissionless entropy keeper. Stdlib + Foundry cast; defaults to dry-run.
Polls every two seconds, scans commit events, and captures even when inventories are full.
No private key support: --send uses an explicitly supplied unlocked RPC signer.
"""
import argparse, json, subprocess, time, urllib.request
from pathlib import Path

SELECTORS={'pack':'c7c4a615','starter':'a888c2cd','captured':'6700ba85','capture':'46758fb6','enhancement':'42b343a3','enhanceCapture':'b5c3e81a'}

def calldata(selector, receipt):
    return '0x'+selector+format(receipt,'064x')

def words(data):
    raw=data.removeprefix('0x')
    if len(raw)%64:raise ValueError('malformed ABI response')
    return [int(raw[n:n+64],16) for n in range(0,len(raw),64)]

class Keeper:
    def __init__(self, transport, contracts, from_block, state=None):
        self.rpc=transport;self.contracts=contracts
        self.state=state or {'nextBlock':from_block,'pending':{}}
    def tick(self):
        head=int(self.rpc.request('eth_blockNumber',[]),16)
        # Re-read 16 blocks after restart/reorg; duplicate commit IDs are harmless.
        start=max(0,self.state['nextBlock']-16)
        for low in range(start,head+1,2000):
            for kind,address in self.contracts.items():
                logs=self.rpc.request('eth_getLogs',[{'address':address,'fromBlock':hex(low),'toBlock':hex(min(head,low+1999)),'topics':[self.rpc.topic(kind)]}])
                for log in logs:
                    if log.get('removed'):continue
                    receipt=int(log['topics'][1],16)
                    self.state['pending'][f'{kind}:{receipt}']=[kind,receipt]
        self.state['nextBlock']=head+1
        native=self.rpc.native_block()
        actions=[]
        for key,(kind,receipt) in list(self.state['pending'].items()):
            address=self.contracts[kind]
            data=words(self.rpc.call(address,calldata(SELECTORS[kind],receipt)))
            if not data or data[0]==0:
                del self.state['pending'][key];continue
            captured=bool(data[5]) if kind=='enhancement' else bool(data[7]) if kind=='pack' else bool(words(self.rpc.call(address,calldata(SELECTORS['captured'],receipt)))[0])
            target=data[2] if kind=='enhancement' else data[1]
            if captured:
                del self.state['pending'][key];continue
            if native<=target:continue
            # Expired capture itself rearms. On the next eligible block, this loop captures the new target.
            if kind=='enhancement': self.rpc.send_enhancement(address,receipt)
            else: self.rpc.send(address,receipt)
            actions.append((kind,receipt,'rearm' if native>target+256 else 'capture'))
        return actions

class Transport:
    def __init__(self,url,send=False,sender=None):
        self.url=url;self.broadcast=send;self.sender=sender
        self.topics={k:subprocess.check_output(['cast','keccak',sig],text=True).strip() for k,sig in {'pack':'PackCommitted(uint256,address,uint256,uint256,bool)','starter':'StarterCommitted(uint256,address,uint256)','enhancement':'EnhancementCommitted(uint256,address,uint256,uint256,uint256,uint256)'}.items()}
    def request(self,method,params):
        request=urllib.request.Request(self.url,json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode(),{'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=15) as response:result=json.load(response)
        if 'error' in result:raise RuntimeError(result['error'])
        return result['result']
    def topic(self,kind):return self.topics[kind]
    def call(self,address,data):return self.request('eth_call',[{'to':address,'data':data},'latest'])
    def native_block(self):
        chain=int(self.request('eth_chainId',[]),16)
        if chain in (4663,46630):
            result=words(self.call('0x0000000000000000000000000000000000000064','0xa3b1b31d'))
            if not result:raise RuntimeError('native ArbSys clock unavailable')
            return result[0]
        return int(self.request('eth_blockNumber',[]),16)
    def send(self,address,receipt):
        if self.broadcast:
            subprocess.run(['cast','send','--rpc-url',self.url,'--unlocked','--from',self.sender,address,'captureEntropy(uint256)',str(receipt)],check=True,capture_output=True,text=True,timeout=45)
        else:print(json.dumps({'to':address,'data':calldata(SELECTORS['capture'],receipt),'dryRun':True}),flush=True)

    def send_enhancement(self,address,receipt):
        if self.broadcast:
            subprocess.run(['cast','send','--rpc-url',self.url,'--unlocked','--from',self.sender,address,'capture(uint256)',str(receipt)],check=True,capture_output=True,text=True,timeout=45)
        else:print(json.dumps({'to':address,'data':calldata(SELECTORS['enhanceCapture'],receipt),'dryRun':True}),flush=True)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['rpc-url','packs','starter']:p.add_argument('--'+name,required=True)
    p.add_argument('--enhancement',help='Pinned Enhancement module; include for v3.5 receipts')
    p.add_argument('--from-block',type=int,required=True);p.add_argument('--state',type=Path,required=True)
    p.add_argument('--interval',type=float,default=2);p.add_argument('--send',action='store_true');p.add_argument('--sender');p.add_argument('--once',action='store_true')
    a=p.parse_args()
    if a.interval<=0 or a.interval>10:p.error('interval must be 0 < seconds <= 10')
    if a.send and not a.sender:p.error('--send requires explicit --sender on an unlocked RPC')
    transport=Transport(a.rpc_url,a.send,a.sender)
    state=json.loads(a.state.read_text()) if a.state.exists() else None
    identity={'chain':transport.request('eth_chainId',[]),'contracts':{'pack':a.packs,'starter':a.starter}}
    if a.enhancement: identity['contracts']['enhancement']=a.enhancement
    if state and state.get('identity')!=identity:p.error('state belongs to different contracts/chain')
    bot=Keeper(transport,identity['contracts'],a.from_block,state)
    bot.state['identity']=identity
    while True:
        try:
            print(json.dumps({'actions':bot.tick()}),flush=True)
            tmp=a.state.with_suffix('.tmp');tmp.write_text(json.dumps(bot.state));tmp.replace(a.state)
        except Exception as error:
            print(json.dumps({'error':str(error)}),flush=True)
            if a.once:raise
        if a.once:break
        time.sleep(a.interval)
if __name__=='__main__':main()
