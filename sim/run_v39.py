#!/usr/bin/env python3
"""v3.9 Balanced launch-core simulation: 10 ETH initial FDV and the swarm's 10% claimable one hour after launch.

Reuses the v3.5 city model with the v3.6 launch-core flags (no enhancement, locks, lobby, billboards or pot)
and changes exactly these inputs:
- Opening price: the IMD policy opens an ETH pair at a 10 ETH fully diluted valuation, so the 700M-token pool
  is seeded at 7 ETH of virtual depth (v3.5/v3.6 used 70/9 ETH, an 11.1 ETH FDV);
- Swarm sell pressure: the platform's 10% (100M tokens) goes to contributor wallets claimable from hour one
  (`contributorLockSeconds 3600`). A fraction of it is sold from epoch 0, either within the first day or spread
  over the first week. Proceeds leave the game (they are not reinvested);
- Optional launch-window buys: ETH bought inside the 30-minute stepped tax window (90/50/25%); the tax funds
  reward buys. Zero by default because nothing in the model predicts sniping volume.
Fees are the v3.9 model: 1.25% LP fee (1% to the paying wallet via LaunchFactory.claimFees = team swap income,
0.25% IMD network) plus the hook's 1% to rewards on every swap after the window and the progressive sell
surcharge. The totals (2.25% per swap, 1% of volume to the team) are the same as v3.6 modeled, so every
difference from the v3.6 core rows comes from the opening valuation and the swarm unlock.
Five seeds, 35 days, medians. Conditional model outputs, not promised returns.
"""
import json, statistics, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import run_v35 as base
import run_v36 as phased

CORE = dict(enhance=False, lobby=False, billboards=False, locks=False, pot=False)
SWARM_TOKENS = 100e6
FDV_ETH = 10.0
POOL_SHARE = 0.7
V36_CORE = {  # artifacts/v36/simulation-phases.md, Balanced core rows (medians of five seeds)
    'steady': dict(team_eth=3.579, drawdown=0.018, week1_payback_days=3.75, maintain_profit_tokens=58_067_690),
    'weak': dict(team_eth=0.917, drawdown=0.007, week1_payback_days=4.25, maintain_profit_tokens=31_323_367),
    'hype': dict(team_eth=4.996, drawdown=0.019, week1_payback_days=3.50, maintain_profit_tokens=128_131_439),
}


class V39(phased.Phased):
    def __init__(self, profile, scenario, seed, sell_fraction, pace_epochs, launch_buys_eth=0.0):
        super().__init__(profile, scenario, seed, dict(CORE))
        self.amm_eth = FDV_ETH * POOL_SHARE
        self.initial_amm_eth = self.amm_eth
        self.peak = self.price()
        self.sell_fraction = sell_fraction
        self.pace_epochs = pace_epochs
        self.swarm_sold = 0.
        self.swarm_eth = 0.
        self.launch_tax_eth = 0.
        self.price_floor = self.price()
        self.launch_buys_eth = launch_buys_eth

    def launch_window(self):
        """Stepped buy tax 90/50/25% on three equal thirds of the window volume; the tax buys rewards."""
        if not self.launch_buys_eth:
            return
        for bps in (.9, .5, .25):
            gross = self.launch_buys_eth / 3
            tax = gross * bps
            net = gross - tax
            out = self.amm * net / (self.amm_eth + net)
            self.amm -= out
            self.amm_eth += net
            self.nonplayer_wallet += out
            reward = tax / self.price()
            self.amm -= reward
            self.pool += reward
            self.amm_eth += tax
            self.launch_tax_eth += tax

    def settle_system(self):
        if self.epoch == 0:
            self.launch_window()
        if self.epoch < self.pace_epochs and self.sell_fraction:
            amount = SWARM_TOKENS * self.sell_fraction / self.pace_epochs
            amount = min(amount, self.swarm)
            if amount > 0:
                self.swarm -= amount
                self.swarm_sold += amount
                self.swarm_eth += self.sell(amount)
        self.price_floor = min(self.price_floor, self.price())
        super().settle_system()

    def run(self):
        out = super().run()
        out.update(swarm_sold_tokens=self.swarm_sold, swarm_eth=self.swarm_eth, launch_tax_eth=self.launch_tax_eth,
                   price_floor=self.price_floor, opening_price=self.initial_amm_eth / 700e6,
                   final_price=self.price(), sell_fraction=self.sell_fraction, pace_epochs=self.pace_epochs,
                   launch_buys_eth=self.launch_buys_eth)
        return out


def summarize(rs):
    s = phased.summarize(rs)
    s.update(swarm_eth=statistics.median(r['swarm_eth'] for r in rs),
             swarm_sold_tokens=statistics.median(r['swarm_sold_tokens'] for r in rs),
             launch_tax_eth=statistics.median(r['launch_tax_eth'] for r in rs),
             price_floor_vs_open=statistics.median(r['price_floor'] / r['opening_price'] for r in rs),
             final_vs_open=statistics.median(r['final_price'] / r['opening_price'] for r in rs))
    return s


CASES = [  # (label, scenario, sell fraction, pace epochs, launch buys ETH)
    ('steady / no swarm sales', 'steady', 0.0, 4, 0.0),
    ('steady / 25% in day 1', 'steady', 0.25, 4, 0.0),
    ('steady / 50% in day 1', 'steady', 0.5, 4, 0.0),
    ('steady / 100% in day 1', 'steady', 1.0, 4, 0.0),
    ('steady / 50% over week 1', 'steady', 0.5, 28, 0.0),
    ('steady / 100% over week 1', 'steady', 1.0, 28, 0.0),
    ('steady / 50% in day 1 + 2 ETH window buys', 'steady', 0.5, 4, 2.0),
    ('weak / 50% in day 1', 'weak', 0.5, 4, 0.0),
    ('weak / 100% over week 1', 'weak', 1.0, 28, 0.0),
    ('hype / 50% in day 1', 'hype', 0.5, 4, 0.0),
    ('hype / 100% over week 1', 'hype', 1.0, 28, 0.0),
]


def main():
    balanced = base.PROFILES[1]
    results = {}
    for label, scenario, fraction, pace, buys in CASES:
        rs = [V39(balanced, scenario, seed, fraction, pace, buys).run() for seed in base.SEEDS]
        results[label] = dict(scenario=scenario, **summarize(rs))
    out = Path('artifacts/v39')
    out.mkdir(parents=True, exist_ok=True)
    (out / 'simulation.json').write_text(json.dumps(dict(cases=CASES, fdv_eth=FDV_ETH, pool_share=POOL_SHARE,
                                                       swarm_tokens=SWARM_TOKENS, v36_core=V36_CORE,
                                                       results=results), indent=2) + '\n')
    lines = ['# v3.9 launch-core simulation (Balanced, 10 ETH FDV, swarm 10% claimable after 1 hour)', '',
             'Five seeds, 35 days, six-hour epochs, medians. Launch core only (no enhancement, locks, lobby, billboards, pot).',
             'Opening price 1e-8 ETH per token (10 ETH FDV, 700M tokens in the pool at 7 ETH virtual depth). Swarm sales',
             'start in epoch 0 (hour 1 is inside it) and are sold at the normal fee schedule; proceeds leave the game.', '',
             '| Case | Week-1 cash payback (days) | Week-1 token payback (days) | Team ETH | Max drawdown | Lowest price / open | Final price / open | Swarm ETH realized | Maintain-only mining profit (tokens) |',
             '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for label, s in results.items():
        lines.append(f"| {label} | {s['week1_payback_days']:.2f} | {s['week1_token_payback_days']:.2f} | {s['team_eth']:.3f} | {s['drawdown']:.1%} | {s['price_floor_vs_open']:.2f} | {s['final_vs_open']:.2f} | {s['swarm_eth']:.3f} | {s['maintain_profit_tokens']:,.0f} |")
    lines += ['', '## Against the v3.6 launch-core rows (11.1 ETH FDV, no swarm sales)', '',
              '| Scenario | v3.6 team ETH | v3.9 team ETH (50% in day 1) | v3.6 drawdown | v3.9 drawdown (50% in day 1) | v3.6 week-1 payback | v3.9 week-1 payback (50% in day 1) |',
              '|---|---:|---:|---:|---:|---:|---:|']
    for scenario in ('steady', 'weak', 'hype'):
        s = results[f'{scenario} / 50% in day 1']
        v = V36_CORE[scenario]
        lines.append(f"| {scenario} | {v['team_eth']:.3f} | {s['team_eth']:.3f} | {v['drawdown']:.1%} | {s['drawdown']:.1%} | {v['week1_payback_days']:.2f}d | {s['week1_payback_days']:.2f}d |")
    lines += ['', 'Reading: team ETH is 1% of swap volume (platform `claimFees`) plus 10% of pack sales and 10% of the sell surcharge, '
              'exactly as v3.6 modeled it, so the fee rework itself does not move team income; the lower opening valuation and the swarm '
              'unlock do. The drawdown column is the largest peak-to-trough move of the model price inside 35 days; the swarm sales set it in the '
              'first day. Payback is the Balanced-profile maintenance cohort of week 1 (cash: realized sales plus marked tokens after fees). '
              'Lowest price / open is the model price floor relative to the 10 ETH FDV opening. Numbers are conditional model outputs; see '
              '`sim/run_v39.py`, `sim/run_v36.py` and the v3.5 assumptions. No launch-window sniping volume is predicted: the "+2 ETH window buys" '
              'row only shows the mechanics (the stepped tax buys rewards).', '']
    (out / 'simulation.md').write_text('\n'.join(lines))
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
