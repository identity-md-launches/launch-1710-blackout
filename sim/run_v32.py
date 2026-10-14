#!/usr/bin/env python3
"""Reproducible six-case v3.2 baseline and behavioral/parameter levers. Standard library only."""
import argparse,json,multiprocessing,hashlib
from pathlib import Path
from blackout_sim_v32 import Model
MODEL_SHA256=hashlib.sha256(Path(__file__).with_name("blackout_sim_v32.py").read_bytes()).hexdigest()

def run(case):
    name,scenario,share,settings=case
    settings=dict(settings)
    drip=settings.pop('drip_days',42)
    r=Model(scenario,'custom',endowment=share,drip_days=drip,single_sided=True,**settings).run()
    peak=10/900e6;drawdown=0
    for row in r['rows']:
        peak=max(peak,row['price']);drawdown=max(drawdown,1-row['price']/peak)
    r.update(model_source_sha256=MODEL_SHA256,case=name,max_drawdown=drawdown,min_bounty_headroom=min(x['headroom'] for x in r['heartbeat_flows']))
    return r

def table(results):
    out=['| Case | Endowment | Scenario | Week-1 payback | Repaid | Stall day | Drawdown | Team ETH | Bounties due / paid | HB income | Min HB headroom |', '|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for r in results:
        c=r['cohorts'][0];p=c['all_farms_median']
        out.append(f"| {r['case']} | {r['endowment']:.0%} | {r['scenario']} | {p if p is not None else 'not reached'} | {c['realized_fraction']:.1%} | {r['stall_day'] or '>35'} | {r['max_drawdown']:.1%} | {r['team_eth']:.5f} | {r['bounties_due']:.5f} / {r['bounties_eth']:.5f} | {r['heartbeat_income']:.5f} | {r['min_bounty_headroom']:.5f} |")
    return '\n'.join(out)+'\n'

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--levers',action='store_true');p.add_argument('--output',default='artifacts/v32/baseline');args=p.parse_args()
    variants={'baseline':{}}
    if args.levers:variants={'price -20%':{'pack_scale':.8},'price -33%':{'pack_scale':2/3},'emit 6% tariff10%':{'emission_start':.06,'tariff_start':.10},'emit 6%':{'emission_start':.06},'tariff10%':{'tariff_start':.10},'cashout80%':{'sale_fraction':.80},'pace hold':{'pace_policy':'hold'},'no plans':{'autonomous':True},'gas ceiling':{'gas_price':50_000_000},'drip14d':{'drip_days':14},'team5%':{'team_share':.05}}
    cases=[(name,scenario,share,settings) for name,settings in variants.items() for share in (.20,.25) for scenario in ('steady','hype','weak')]
    with multiprocessing.Pool(4) as pool:results=pool.map(run,cases)
    out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    (out/'simulation.json').write_text(json.dumps(results,indent=2,allow_nan=False)+'\n')
    (out/'comparison.md').write_text(table(results));print(table(results))
