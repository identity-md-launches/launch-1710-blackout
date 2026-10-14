#!/usr/bin/env python3
"""v3.1 supply-conserving, zero-ETH, single-sided launch sensitivity. Standard library only."""
import argparse, json, multiprocessing
from pathlib import Path
from blackout_sim_v3 import Model

def run(args):
    scenario,share,drip,bps=args
    return Model(scenario,'custom',endowment=share,drip_days=drip,single_sided=True,heartbeat_bps=bps).run()

def table(results):
    out=['| Endowment | poolBps | Drip days | Scenario | Week-1 cohort payback | Repaid | Stall day | Team ETH | Price / opening | Bounties due / paid ETH | HB income | Runs cost ETH | Max weekly loss |', '|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
    for r in results:
        c=r['cohorts'][0];pb=c['all_farms_median']
        out.append(f"| {r['endowment']:.0%} | {r['pool_bps']} | {r['drip_days']} | {r['scenario']} | {str(pb)+'d' if pb is not None else 'not reached'} | {c['realized_fraction']:.1%} | {r['stall_day'] or '>35'} | {r['team_eth']:.4f} | {r['final_price']/(10/900e6):.2f} | {r['bounties_due']:.4f} / {r['bounties_eth']:.4f} | {r['heartbeat_income']:.4f} | {r['swarm_runs_eth']:.4f} | {r['max_weekly_event_loss']:.2%} |")
    return '\n'.join(out)+'\n'

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',default='artifacts/v31');p.add_argument('--drips',default='0,14,42,56');p.add_argument('--shares',default='10,15,20,25');p.add_argument('--heartbeat-bps',type=int,default=200);args=p.parse_args()
    cases=[(s,int(share)/100,int(drip),args.heartbeat_bps) for share in args.shares.split(',') for drip in args.drips.split(',') for s in ('steady','hype','weak')]
    with multiprocessing.Pool(4) as pool:results=pool.map(run,cases)
    out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    (out/'simulation.json').write_text(json.dumps(results,indent=2,allow_nan=False)+'\n')
    (out/'comparison.md').write_text(table(results));print(table(results))
