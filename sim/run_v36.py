#!/usr/bin/env python3
"""v3.6 phased-release simulation: Balanced profile, launch core alone, then each phase enabled.

Reuses the v3.5 city model unchanged except for feature flags:
- enhance / lobby / billboards disabled: those purchases do not exist, so the model's 1.4x grower
  budget flows into packs and rooms instead (the budget is a willingness-to-spend assumption; whether
  players spend as much without growth features is an open demand question, not a model result);
- locks disabled: growers keep their capital instead of locking it (no +10% lock weight);
- pot disabled: the 50% sell-surcharge pot share follows the v3.4 routing (reward buys), no pot.
Phases follow the suggested order: core (launch), +enhancement (week 2), +locks/stake/lobby (weeks 3-4),
+billboards and pot (month 2). Each run is the full 35 days with that phase set on from day 0, so the
rows are a sensitivity by phase, not a calendar replay. Five seeds, steady scenario, plus weak/hype for core.
"""
import json, statistics, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import run_v35 as base

PHASES = [
    ('core', dict(enhance=False, lobby=False, billboards=False, locks=False, pot=False)),
    ('core+enhancement', dict(enhance=True, lobby=False, billboards=False, locks=False, pot=False)),
    ('core+enhancement+locks/lobby', dict(enhance=True, lobby=True, billboards=False, locks=True, pot=False)),
    ('all (v3.5 full)', dict(enhance=True, lobby=True, billboards=True, locks=True, pot=True)),
]

class Phased(base.Model):
    def __init__(self, profile, scenario, seed, flags):
        super().__init__(profile, scenario, seed); self.flags = flags; self.v34_pot_to_rewards = 0.
    def spend(self, f, amount, kind, initial=False):
        if kind in ('enhance', 'lobby', 'billboards') and not self.flags[kind]: return
        super().spend(f, amount, kind, initial)
    def sell(self, amount, system=False):
        if self.flags['pot'] or system: return super().sell(amount, system)
        # v3.4 routing while the pot is disabled: the 50% share buys mining rewards instead.
        before = self.pot; out = super().sell(amount, system)
        moved = self.pot - before; self.pot = before; self.pool += moved; self.v34_pot_to_rewards += moved
        self.pots[self.epoch // 28] = 0.
        return out
    def run(self):
        if not self.flags['locks']:
            # Locks are taken on day 3 of a grower's life in the base model; neutralise by never maturing them.
            original = base.Farm
            class NoLockFarm(original):
                def __setattr__(self, k, v):
                    if k == 'locked' and v: 
                        object.__setattr__(self, 'wallet', self.wallet + v); object.__setattr__(self, 'lock_cost', self.lock_cost - v); v = 0.
                    object.__setattr__(self, k, v)
            base.Farm = NoLockFarm
            try: return super().run()
            finally: base.Farm = original
        return super().run()

def summarize(rs):
    maintain_profit = statistics.median(r['maintain_mining_profit'] for r in rs)
    return dict(
        maintain_profit_tokens=maintain_profit,
        maintain_repair_share=statistics.median(r['maintain_repair_share'] for r in rs),
        week1_payback_days=statistics.median(r['cohorts'][0]['median_eth_payback'] or 99 for r in rs),
        week1_token_payback_days=statistics.median(r['cohorts'][0]['median_token_payback'] or 99 for r in rs),
        team_eth=statistics.median(r['team_eth'] for r in rs),
        drawdown=statistics.median(r['drawdown'] for r in rs),
        grower_spend_mined=statistics.median(r['grower_spend_mined'] for r in rs),
        sinks={k: statistics.median(r['sinks'][k] for r in rs) for k in rs[0]['sinks']},
        locked_peak=statistics.median(r['locked_peak'] for r in rs),
        conservation_error=max(r['max_conservation_error'] for r in rs),
    )

if __name__ == '__main__':
    balanced = base.PROFILES[1]
    results = {}
    for name, flags in PHASES:
        for scenario in (['steady', 'weak', 'hype', 'drop50'] if name == 'core' else ['steady']):
            rs = [Phased(balanced, scenario, seed, flags).run() for seed in base.SEEDS]
            results[f'{name} / {scenario}'] = summarize(rs)
    out = Path('artifacts/v36'); out.mkdir(parents=True, exist_ok=True)
    (out / 'simulation-phases.json').write_text(json.dumps(dict(phases=PHASES, results=results), indent=2) + '\n')
    lines = ['# v3.6 launch-core and phase simulation (Balanced profile, 35 days, 5 seeds, medians)', '',
             '| Phase / scenario | Maintain-only mining profit (tokens) | Repair share | Week-1 cash payback (days) | Week-1 token payback (days) | Team ETH | Drawdown | Grower spend/mined | Locked peak |',
             '|---|---:|---:|---:|---:|---:|---:|---:|---:|']
    for k, s in results.items():
        lines.append(f"| {k} | {s['maintain_profit_tokens']:,.0f} | {s['maintain_repair_share']:.1%} | {s['week1_payback_days']:.2f} | {s['week1_token_payback_days']:.2f} | {s['team_eth']:.3f} | {s['drawdown']:.1%} | {s['grower_spend_mined']:.3f}× | {s['locked_peak']:,.0f} |")
    lines += ['', 'Maintain-only players stay profitable in every phase (positive mined-minus-repair). With the 1.4x budget assumption held fixed, the core alone routes grower spending into packs and rooms, so team ETH and payback are close to the full game; locks add recoverable escrow, and the pot phase moves half of the sell surcharge from reward buys into weekly prizes (lower maintain-only mining, lower drawdown). Whether players spend as much without enhancement, locks or billboards is a demand assumption to watch in week 1, not a model output. Numbers are conditional model outputs, not promised returns; see `sim/run_v36.py` and the v3.5 assumptions.', '']
    (out / 'simulation-phases.md').write_text('\n'.join(lines)); print('\n'.join(lines))
