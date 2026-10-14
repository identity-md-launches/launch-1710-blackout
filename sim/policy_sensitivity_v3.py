#!/usr/bin/env python3
"""Compare daily pack-pace policies; explicit funding is hypothetical, never transacted."""
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
import blackout_sim_v3 as sim

def one(args):
    capital, scenario, path, policy = args
    r = sim.Model(scenario, path, bootstrap=capital, pace_policy=policy).run()
    return dict(policy=policy, **{k:v for k,v in r.items() if k!='rows'})

if __name__ == '__main__':
    jobs = [(capital, 'hype', path, policy) for capital in (0,40) for path in ('custom','standard') for policy in ('hold','adaptive')]
    with ProcessPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(one, jobs))
    Path('artifacts/policy-sensitivity-v3.json').write_text(json.dumps(results, indent=2)+'\n')
    for r in results:
        print(r['bootstrap_eth'],r['path'],r['policy'],r['stall_day'],r['cohorts'][0]['realized_median'],r['max_weekly_event_loss'])
