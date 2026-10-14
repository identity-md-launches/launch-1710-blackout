# v3.6 launch-core and phase simulation (Balanced profile, 35 days, 5 seeds, medians)

| Phase / scenario | Maintain-only mining profit (tokens) | Repair share | Week-1 cash payback (days) | Week-1 token payback (days) | Team ETH | Drawdown | Grower spend/mined | Locked peak |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| core / steady | 58,067,690 | 10.4% | 3.75 | 3.75 | 3.579 | 1.8% | 1.390× | 0 |
| core / weak | 31,323,367 | 10.6% | 4.25 | 4.00 | 0.917 | 0.7% | 1.388× | 0 |
| core / hype | 128,131,439 | 10.6% | 3.50 | 4.00 | 4.996 | 1.9% | 1.391× | 0 |
| core / drop50 | 65,869,166 | 10.5% | 3.75 | 3.75 | 3.533 | 49.4% | 1.389× | 0 |
| core+enhancement / steady | 58,238,856 | 10.4% | 3.75 | 3.75 | 3.530 | 1.8% | 1.398× | 0 |
| core+enhancement+locks/lobby / steady | 57,023,812 | 10.4% | 3.75 | 3.75 | 3.572 | 1.8% | 1.400× | 25,881,767 |
| all (v3.5 full) / steady | 44,334,342 | 10.4% | 3.75 | 3.75 | 3.497 | 1.3% | 1.400× | 20,032,041 |

Maintain-only players stay profitable in every phase (positive mined-minus-repair). With the 1.4x budget assumption held fixed, the core alone routes grower spending into packs and rooms, so team ETH and payback are close to the full game; locks add recoverable escrow, and the pot phase moves half of the sell surcharge from reward buys into weekly prizes (lower maintain-only mining, lower drawdown). Whether players spend as much without enhancement, locks or billboards is a demand assumption to watch in week 1, not a model output. Numbers are conditional model outputs, not promised returns; see `sim/run_v36.py` and the v3.5 assumptions.
