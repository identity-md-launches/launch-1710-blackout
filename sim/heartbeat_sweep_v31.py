#!/usr/bin/env python3
"""Replay all base economic paths at 1-bps resolution, then fully re-simulate candidates.
Replay holds behavior fixed: final recommendations require the full rerun, not just this estimate.
"""
import argparse,json,math,multiprocessing
from pathlib import Path
from blackout_sim_v3 import Model

def replay(r,bps,cap=1.):
    balance=income=0.;prev_gross=prev_due=0.;minimum=1e9
    for row in r['heartbeat_flows']:
        gross=row['routed_eth']-prev_gross;due=row['bounties_due']-prev_due
        credit=min(cap-balance,gross*bps/10000);balance+=credit;income+=credit
        balance=max(0,balance-due)
        minimum=min(minimum,income-row['bounties_due']-row['runs_eth'])
        prev_gross=row['routed_eth'];prev_due=row['bounties_due']
    return minimum

def run(case):
    s,share,drip,bps,lock,auto,cap=case
    return Model(s,'custom',endowment=share,drip_days=drip,single_sided=True,heartbeat_bps=bps,claim_lock_days=lock,autonomous=auto,heartbeat_cap=cap).run()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--base',default='artifacts/v31/final/simulation.json');p.add_argument('--output',default='artifacts/v31/heartbeat');p.add_argument('--bps',type=int);p.add_argument('--cap',type=float,default=4.);p.add_argument('--all',action='store_true');p.add_argument('--stress',action='store_true');a=p.parse_args()
    base=json.loads(Path(a.base).read_text());out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
    candidates=[]
    for r in base:
        low,high=200,5000
        while low<high:
            mid=(low+high)//2
            if replay(r,mid,a.cap)>=-1e-10:high=mid
            else:low=mid+1
        b=low if replay(r,low,a.cap)>=-1e-10 else None
        candidates.append(dict(scenario=r['scenario'],endowment=r['endowment'],drip_days=r['drip_days'],minimum_replay_bps=b))
    (out/'replay.json').write_text(json.dumps(candidates,indent=2)+'\n')
    bps=a.bps or max(x['minimum_replay_bps'] or 5001 for x in candidates)
    print('Replay minimum:',max(x['minimum_replay_bps'] or 5001 for x in candidates),'rerun:',bps,flush=True)
    source=base if a.all else [r for r in base if r['endowment']==.25 and r['drip_days']==42]
    cases=[(r['scenario'],r['endowment'],r['drip_days'],bps,2,False,a.cap) for r in source]
    if a.stress:
        cases += [(s,.25,42,bps,lock,auto,a.cap) for s in ('steady','hype','weak') for lock,auto in [(0,False),(7,False),(2,True)]]
    results=[]
    with multiprocessing.Pool(3) as pool:
        for r in pool.imap_unordered(run,cases):
            results.append(r);(out/'simulation.json').write_text(json.dumps(results,indent=2,allow_nan=False)+'\n')
            print(r['scenario'],r['endowment'],r['drip_days'],r['claim_lock_days'],r['autonomous'],'min headroom',min(x['headroom'] for x in r['heartbeat_flows']),flush=True)
