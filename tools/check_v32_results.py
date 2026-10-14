#!/usr/bin/env python3
"""Validate the offline v3.2 economic artifacts; no network or dependencies."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / 'artifacts/v32'
MODEL_HASH = hashlib.sha256((ROOT / 'sim/blackout_sim_v32.py').read_bytes()).hexdigest()


def main():
    baseline = json.loads((ARTIFACTS / 'verified-baseline/simulation.json').read_text())
    sensitivities = json.loads((ARTIFACTS / 'verified-sensitivities/simulation.json').read_text())
    assert len(baseline) == 6 and len(sensitivities) == 66
    cases = baseline + sensitivities
    for result in cases:
        assert result['model_source_sha256'] == MODEL_HASH, 'stale simulation source'
        assert result['version'] == '3.2'
        assert result['initial_actual_amm_eth'] == result['bootstrap_eth'] == 0
        assert result['heartbeat_bps'] == 200 and result['heartbeat_cap'] == 1
        assert len(result['rows']) == len(result['heartbeat_flows']) == 140
        assert result['token_conservation_max_error'] < .02
        assert set(result['work_due']) <= {'advance', 'buy', 'plan_entropy', 'pack_entropy', 'season_finalize'}
        assert abs(sum(result['work_due'].values()) - result['bounties_due']) < 1e-8
        assert abs(sum(result['work_paid'].values()) - result['bounties_eth']) < 1e-8
        assert abs(result['heartbeat_income'] - result['bounties_eth'] - result['heartbeat_eth']) < 1e-8
        assert result['heartbeat_eth'] <= 1 + 1e-8
        assert result['bounty_shortfall'] < 1e-8 and result['first_bounty_shortfall'] is None
        assert result['min_bounty_headroom'] >= 0
    for result in baseline:
        assert result['drip_days'] == 42 and result['team_share'] == .13
        assert result['bounty_shortfall'] < 1e-8 and result['first_bounty_shortfall'] is None
        assert min(flow['headroom'] for flow in result['heartbeat_flows']) >= 0
    stress = [r for r in sensitivities if r['case'] in ('gas ceiling', 'no plans')]
    assert len(stress) == 12
    for result in stress:
        assert result['bounty_shortfall'] < 1e-8 and result['min_bounty_headroom'] >= 0
    summary = dict(
        model_sha256=MODEL_HASH, full_runs=len(cases), baseline_runs=len(baseline),
        sensitivity_runs=len(sensitivities), baseline_and_operating_stress_fully_paid=True,
        maximum_token_conservation_error=max(r['token_conservation_max_error'] for r in cases),
        minimum_baseline_headroom=min(r['min_bounty_headroom'] for r in baseline),
        minimum_operating_stress_headroom=min(r['min_bounty_headroom'] for r in stress),
        hypothetical_lever_shortfalls=[dict(case=r['case'], endowment=r['endowment'], scenario=r['scenario'], shortfall=r['bounty_shortfall']) for r in sensitivities if r['bounty_shortfall'] > 1e-8],
    )
    (ARTIFACTS / 'simulation-checks.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
