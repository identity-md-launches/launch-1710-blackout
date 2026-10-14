#!/usr/bin/env python3
"""Full-path checks immediately below the proposed initial heartbeat parameters."""
import json
import multiprocessing
from pathlib import Path
from heartbeat_sweep_v31 import run


if __name__ == '__main__':
    # A larger cap cannot cure weak-case total-income insufficiency. The second
    # path isolates the lower cap's discarded early revenue in unattended hype.
    cases = [
        ('weak', .25, 42, 3000, 2, True, 4.5),
        ('hype', .25, 42, 3100, 2, True, 4.0),
        ('weak', .25, 42, 2900, 2, False, 4.5),
    ]
    with multiprocessing.Pool(2) as pool:
        results = list(pool.imap(run, cases))
    target = Path('artifacts/v31/boundary-checks.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(results, indent=2, allow_nan=False) + '\n')
    for r in results:
        print(r['scenario'], r['heartbeat_bps'], r['heartbeat_cap'],
              'autonomous', r['autonomous'],
              'minimum headroom', min(x['headroom'] for x in r['heartbeat_flows']))
