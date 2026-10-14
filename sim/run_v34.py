#!/usr/bin/env python3
"""Offline, five seeds per scenario/drip. No chain access. Stdlib only."""
import json, statistics, multiprocessing
from pathlib import Path
from blackout_sim_v34 import Model
SEEDS=[20261011,20261012,20261013,20261014,20261015]

def run(case):
    scenario,drip,seed,fast,inflow=case
    r=Model(scenario,'custom',seed=seed,endowment=.2,drip_days=drip,single_sided=True,fast_entry=fast,inflow_rule=inflow).run()
    peak=r['rows'][0]['price'];drawdown=0
    for row in r['rows']:
        peak=max(peak,row['price']);drawdown=max(drawdown,1-row['price']/peak)
    return dict(buy_backlog_peak=r['buy_backlog_peak'],buy_backlog_end=r['buy_backlog_end'],buy_attempts=r['buy_attempts'],buy_skips=r['buy_skips'],scenario=scenario,drip=drip,seed=seed,fast_entry=fast,inflow_rule=inflow,cohorts=r['cohorts'][:3],stall_day=r['stall_day'],drawdown=drawdown,team_eth=r['team_eth'],team_net_eth=r['team_eth']-r['swarm_runs_eth'],pack_eth=r['pack_eth'],final_emission=r['final_emission'],max_conservation_error=r['token_conservation_max_error'],heartbeat_shortfall=r['bounty_shortfall'],rows=r['rows'])

def snipers():
    result=[]
    for minute,tax in [(1,.9),(15,.5),(25,.25)]:
        # Independent fresh-pool cases: isolates the tax at each timestamp, 5 ETH one transaction.
        x=10*.7/.9;y=700e6;net=5*(1-tax);out=y*net/(x+net);X=x+net;Y=y-out
        gross=X*out/(Y+out)
        result.append(dict(minute=minute,cost_eth=5,tax_bps=round(tax*10000),reward_pool_eth=5*tax,tokens=out,proceeds_normal_sell=gross*(1-.0225),proceeds_capped_sell=gross*.85,pnl_normal_sell=gross*(1-.0225)-5,pnl_capped_sell=gross*.85-5))
    return result

def spread(values):
    return f'{statistics.median(values):.3f} [{min(values):.3f}, {max(values):.3f}]'

def summarize(results):
    lines=['# v3.4 simulation: medians [minimum, maximum], five seeds','', '35 days; 20% endowment, zero external ETH bootstrap. Unrepaid cohorts remain censored, never counted as repaid.','', '| Scenario | Drip | Stall day | Drawdown | Gross team ETH | Net team ETH | Pack ETH |','|---|---:|---|---|---|---|---|']
    for scenario in ['steady','hype','weak']:
        for drip in [42,56]:
            rs=[r for r in results if r['scenario']==scenario and r['drip']==drip and r['fast_entry'] and r['inflow_rule']]
            lines.append(f'| {scenario} | {drip} | '+ ' | '.join(spread([r[k] if r[k] is not None else 35 for r in rs]) for k in ['stall_day','drawdown','team_eth','team_net_eth','pack_eth'])+' |')
    lines+=['','Stall >35 is represented as 35 in this table only; raw JSON retains null. Net team deducts the inherited explicit off-chain schedule budget; no heartbeat withdrawal exists.','', '| Scenario / drip | Join week | Whole-cohort payback days | Fraction repaid | Conditional payback (repaid only) |','|---|---:|---|---|---|']
    for scenario in ['steady','hype','weak']:
        for drip in [42,56]:
            rs=[r for r in results if r['scenario']==scenario and r['drip']==drip and r['fast_entry'] and r['inflow_rule']]
            for w in range(3):
                cs=[r['cohorts'][w] for r in rs];whole=[c['all_farms_median'] for c in cs];cond=[c['realized_median'] for c in cs if c['realized_median'] is not None]
                payback=spread(whole) if all(x is not None for x in whole) else f'not reached in {sum(x is None for x in whole)}/5 seeds'
                lines.append(f'| {scenario} / {drip} | {w+1} | {payback} | {spread([c["realized_fraction"] for c in cs])} | {spread(cond) if cond else "none repaid"} |')
    lines+=['','## Steady / 42-day lever comparison','', '| Current-epoch entry | Inflow regulator | Pack ETH | Repaid week 2 | Repaid week 3 |','|---|---|---|---|---|']
    for fast,inflow in [(True,True),(False,True),(True,False)]:
        rs=[r for r in results if r['scenario']=='steady' and r['drip']==42 and r['fast_entry']==fast and r['inflow_rule']==inflow]
        lines.append(f'| {fast} | {inflow} | {spread([r["pack_eth"] for r in rs])} | {spread([r["cohorts"][1]["realized_fraction"] for r in rs])} | {spread([r["cohorts"][2]["realized_fraction"] for r in rs])} |')
    return '\n'.join(lines)+'\n'

if __name__=='__main__':
    cases=[(s,d,n,True,True) for s in ['steady','hype','weak'] for d in [42,56] for n in SEEDS]+[('steady',42,n,f,i) for n in SEEDS for f,i in [(False,True),(True,False)]]
    with multiprocessing.Pool(4) as pool:results=pool.map(run,cases)
    out=Path('artifacts/v34');out.mkdir(parents=True,exist_ok=True)
    (out/'simulation.json').write_text(json.dumps(dict(seeds=SEEDS,results=results,snipers=snipers()),indent=2)+'\n')
    (out/'simulation.md').write_text(summarize(results))
    print(summarize(results))
