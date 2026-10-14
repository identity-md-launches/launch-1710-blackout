#!/usr/bin/env python3
"""Reproducible parameter-policy and explicit initial-funding sensitivity. No transactions."""
import json
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor
from blackout_sim_v3 import Model

def one(args):
    capital,scenario,path=args
    r=Model(scenario,path,bootstrap=capital).run()
    return {k:v for k,v in r.items() if k!='rows'}
if __name__=='__main__':
    jobs=[(capital,'steady','custom') for capital in (0,5,10,20,40)]
    with ProcessPoolExecutor(max_workers=3) as executor:results=list(executor.map(one,jobs))
    Path('artifacts/funding-sensitivity-v3.json').write_text(json.dumps(results,indent=2)+'\n')
    for r in results:print(json.dumps(dict(bootstrap_eth=r['bootstrap_eth'],week1=r['cohorts'][0],stall=r['stall_day'],loss=r['max_weekly_event_loss'])))
