#!/usr/bin/env python3
"""BLACKOUT v3.3 runs: steady/hype/weak at 20% endowment, 42-day drip, plus whale and sniper scenarios.
Standard library only. Usage: python3 sim/run_v33.py --output artifacts/v33"""
import argparse, json, multiprocessing, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from blackout_sim_v33 import Model

V32_STUCK = {'steady': 176.37e6, 'hype': 228.28e6, 'weak': 136.72e6}  # report.md v3.2, 20% endowment


def run(case):
    name, scenario, whale = case
    r = Model(scenario, 'custom', endowment=.20, drip_days=42, single_sided=True, whale_packs=whale).run()
    peak = 10 / 900e6; dd = 0
    for row in r['rows']:
        peak = max(peak, row['price']); dd = max(dd, 1 - row['price'] / peak)
    flows = r['heartbeat_flows']
    return dict(case=name, scenario=scenario, payback=r['cohorts'][0]['all_farms_median'],
                repaid=r['cohorts'][0]['realized_fraction'], stall_day=r['stall_day'], drawdown=dd,
                team_eth=r['team_eth'], bounties_due=r['bounties_due'], bounties_paid=r['bounties_eth'],
                heartbeat_income=r['heartbeat_income'], coverage=(r['bounties_eth'] / r['bounties_due']) if r['bounties_due'] else 1.,
                min_headroom=min(x['headroom'] for x in flows) if flows else None,
                stuck_tokens=r['lazy_reserved'], v32_stuck_tokens=V32_STUCK[scenario],
                returned_tokens=V32_STUCK[scenario] - r['lazy_reserved'], whale_share=r['whale_share'],
                whale_cost_eth=r['whale_cost_eth'], user_gas_eth=r['user_settlement_gas_eth'])


def snipers(liquidity=10., endowment=.20, bot_eth=5., chunk=.5, seconds=60, normal=.0225, launch=.90, decay=1800, sell_cap=.15):
    """Single-sided launch AMM (x virtual ETH, y tokens) as in the model. Bots split 5 ETH into max-buy chunks
    evenly over the first minute. Tax above the normal fee goes 100% to the reward pool."""
    x = liquidity * (.9 - endowment) / .9; y = 1e9 * (.9 - endowment); p0 = x / y
    def go(taxed):
        X, Y, tokens, pool_tax = x, y, 0., 0.
        n = int(bot_eth / chunk)
        for i in range(n):
            t = seconds * i / max(1, n - 1)
            tax = normal + (launch - normal) * max(0, decay - t) / decay if taxed else normal
            net = chunk * (1 - tax); pool_tax += chunk * (tax - normal)
            out = Y * net / (X + net); X += net; Y -= out; tokens += out
        price_after = X / Y
        # Dump at 30 or 60 minutes with no other flow: sells pay normal fee + surcharge, capped at 15%.
        gross = X * tokens / (Y + tokens); proceeds = gross * (1 - sell_cap)
        return dict(cost_eth=bot_eth, tokens=tokens, launch_tax_to_pool_eth=pool_tax, price_before=p0,
                    price_after_snipe=price_after, price_at_30m=price_after, price_at_60m=price_after,
                    price_change=price_after / p0 - 1, dump_proceeds_eth=proceeds, bot_pnl_eth=proceeds - bot_eth,
                    price_after_dump=(X - gross) / (Y + tokens))
    return dict(with_launch_tax=go(True), without_launch_tax=go(False))


if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('--output', default='artifacts/v33'); a = ap.parse_args()
    cases = [('steady', 'steady', 0), ('hype', 'hype', 0), ('weak', 'weak', 0), ('whale-steady', 'steady', 300)]
    with multiprocessing.Pool(4) as pool: results = pool.map(run, cases)
    out = Path(a.output); out.mkdir(parents=True, exist_ok=True)
    data = dict(results=results, snipers=snipers())
    (out / 'simulation.json').write_text(json.dumps(data, indent=2, default=str) + '\n')
    print(json.dumps(data, indent=2, default=str))
