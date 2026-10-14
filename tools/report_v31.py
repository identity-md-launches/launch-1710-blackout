#!/usr/bin/env python3
"""Render v3.1 report tables from complete simulation runs; does not execute transactions."""
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'sim'))
from blackout_sim_v31 import table
BASE=Path('artifacts/v31')
def drawdown(r):
    peak=10/900e6;worst=0.
    for row in r['rows']:
        peak=max(peak,row['price']);worst=max(worst,1-row['price']/peak)
    return worst

def number(v):return 'not reached' if v is None else f'{v:.3f}'.rstrip('0').rstrip('.')+'d'
def alive(r):return '>35' if r['stall_day'] is None else str(r['stall_day'])
def headroom(r):return min(x['headroom'] for x in r['heartbeat_flows'])

def tables():
    base=json.loads((BASE/'final/simulation.json').read_text());assert len(base)==48
    funded=json.loads((BASE/'funded/simulation.json').read_text());assert len(funded)==57
    candidateStress=json.loads((BASE/'candidate-stress/simulation.json').read_text());assert len(candidateStress)==9
    funded+=candidateStress
    improved=[r for r in funded if r['claim_lock_days']==2 and not r['autonomous']];assert len(improved)==48
    stress=[r for r in funded if r['claim_lock_days']!=2 or r['autonomous']];assert len(stress)==18
    ordered=sorted(improved,key=lambda r:(r['endowment'],r['drip_days'],['steady','hype','weak'].index(r['scenario'])))
    (BASE/'funded/comparison.md').write_text('# 31% heartbeat share, 4.5 ETH cap, no external ETH capital\n\n'+table(ordered))
    by={(r['endowment'],r['drip_days'],r['scenario']):r for r in base}
    lines=['| Endowment / poolBps | Steady instant | Steady14d | Steady42d | Steady56d | Hype alive,42d | Price drawdown steady / hype,42d |','|---|---:|---:|---:|---:|---:|---:|']
    for share in [.1,.15,.2,.25]:
        steadies=[by[share,d,'steady'] for d in [0,14,42,56]];h=by[share,42,'hype']
        lines.append(f"| {share:.0%} / {round((.9-share)*10000)} | "+' | '.join(number(r['cohorts'][0]['all_farms_median']) for r in steadies)+f" | {alive(h)} | {drawdown(steadies[2]):.1%} / {drawdown(h):.1%} |")
    (BASE/'allocation-summary.md').write_text('\n'.join(lines)+'\n')
    lines=['| Endowment | Scenario | Repaid week-1 farms | Team gross ETH | HB receipts | Bounties due / paid ETH | Combined deficit incl runs | Weekly loss |','|---|---|---:|---:|---:|---:|---:|---:|']
    for share in [.1,.15,.2,.25]:
        for s in ['steady','hype','weak']:
            r=by[share,42,s]
            lines.append(f"| {share:.0%} | {s} | {r['cohorts'][0]['realized_fraction']:.1%} | {r['team_eth']:.4f} | {r['heartbeat_income']:.4f} | {r['bounties_due']:.4f} / {r['bounties_eth']:.4f} | {r['heartbeat_income']-r['bounties_due']-r['swarm_runs_eth']:.4f} | {r['max_weekly_event_loss']:.2%} |")
    (BASE/'baseline-budget.md').write_text('\n'.join(lines)+'\n')
    lines=['| Scenario | HB share / cap | Week-1 payback | Hype/steady stall day | Team gross / after IMD ETH | HB receipts | Bounties due / paid | Minimum combined headroom | Reward buy ETH diverted vs baseline |','|---|---|---:|---:|---:|---:|---:|---:|---:|']
    for s in ['steady','hype','weak']:
        original=by[.20,42,s]
        for r in [original,next(x for x in improved if x['endowment']==.20 and x['drip_days']==42 and x['scenario']==s)]:
            # Direct routed-ETH effect on the same enhanced fee base; team fixed13%, base fees unchanged.
            divert=r['heartbeat_income']-r['routed_eth']*.02 if r['heartbeat_bps']!=200 else 0.
            lines.append(f"| {s} | {r['heartbeat_bps']/100:.0f}% / {r['heartbeat_cap']:g}ETH | {number(r['cohorts'][0]['all_farms_median'])} | {alive(r)} | {r['team_eth']:.4f} / {r['team_eth']-r['swarm_runs_eth']:.4f} | {r['heartbeat_income']:.4f} | {r['bounties_due']:.4f} / {r['bounties_eth']:.4f} | {headroom(r):.5f} | {divert:.4f} |")
    (BASE/'funding-comparison.md').write_text('\n'.join(lines)+'\n')
    lines=['| Endowment | Scenario | Claim lock | Swarm plans | Week-1 payback | Alive days | Team gross ETH | Minimum combined headroom ETH | Weekly gross loss |','|---|---|---:|---|---:|---:|---:|---:|---:|']
    for r in sorted(stress,key=lambda x:(x['endowment'],x['scenario'],x['claim_lock_days'],x['autonomous'])):
        lines.append(f"| {r['endowment']:.0%} | {r['scenario']} | {r['claim_lock_days']}d | {'absent' if r['autonomous'] else 'timely'} | {number(r['cohorts'][0]['all_farms_median'])} | {alive(r)} | {r['team_eth']:.4f} | {headroom(r):.5f} | {r['max_weekly_event_loss']:.2%} |")
    (BASE/'stress-comparison.md').write_text('\n'.join(lines)+'\n')
    summary=dict(baseCases=len(base),enhancedCases=len(improved),stressCases=len(stress),enhancedFailures=[dict(scenario=r['scenario'],endowment=r['endowment'],drip=r['drip_days'],lock=r['claim_lock_days'],autonomous=r['autonomous'],headroom=headroom(r)) for r in funded if headroom(r)<-1e-9],baseMaxConservationError=max(r['token_conservation_max_error'] for r in base),enhancedMaxConservationError=max(r['token_conservation_max_error'] for r in funded),baseMaxWeeklyLoss=max(r['max_weekly_event_loss'] for r in base),enhancedMaxWeeklyLoss=max(r['max_weekly_event_loss'] for r in improved),stressMaxWeeklyLoss=max(r['max_weekly_event_loss'] for r in stress),minimumEnhancedHeadroom=min(headroom(r) for r in improved),minimumStressHeadroom=min(headroom(r) for r in stress))
    (BASE/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
if __name__=='__main__':tables()
