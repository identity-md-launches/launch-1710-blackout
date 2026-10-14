#!/usr/bin/env python3
"""Stress the best funded 42-day allocation, keeping the earlier 25% stresses too."""
import json
import multiprocessing
from pathlib import Path
from heartbeat_sweep_v31 import run


if __name__ == '__main__':
    cases = [(s, .20, 42, 3100, lock, autonomous, 4.5)
             for s in ('steady', 'hype', 'weak')
             for lock, autonomous in [(0, False), (7, False), (2, True)]]
    target = Path('artifacts/v31/candidate-stress/simulation.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    results = []
    with multiprocessing.Pool(3) as pool:
        for r in pool.imap_unordered(run, cases):
            results.append(r)
            target.write_text(json.dumps(results, indent=2, allow_nan=False) + '\n')
            print(r['scenario'], r['claim_lock_days'], r['autonomous'],
                  min(x['headroom'] for x in r['heartbeat_flows']), flush=True)
