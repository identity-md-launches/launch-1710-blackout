# v3.9 launch-core simulation (Balanced, 10 ETH FDV, swarm 10% claimable after 1 hour)

Five seeds, 35 days, six-hour epochs, medians. Launch core only (no enhancement, locks, lobby, billboards, pot).
Opening price 1e-8 ETH per token (10 ETH FDV, 700M tokens in the pool at 7 ETH virtual depth). Swarm sales
start in epoch 0 (hour 1 is inside it) and are sold at the normal fee schedule; proceeds leave the game.

| Case | Week-1 cash payback (days) | Week-1 token payback (days) | Team ETH | Max drawdown | Lowest price / open | Final price / open | Swarm ETH realized | Maintain-only mining profit (tokens) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| steady / no swarm sales | 3.75 | 3.75 | 3.582 | 1.9% | 1.00 | 3.08 | 0.000 | 61,141,112 |
| steady / 25% in day 1 | 3.75 | 3.75 | 3.584 | 2.0% | 0.99 | 2.96 | 0.237 | 63,814,921 |
| steady / 50% in day 1 | 3.75 | 3.75 | 3.586 | 7.5% | 0.93 | 2.85 | 0.458 | 66,536,955 |
| steady / 100% in day 1 | 3.50 | 3.75 | 3.589 | 18.4% | 0.82 | 2.66 | 0.860 | 72,119,903 |
| steady / 50% over week 1 | 3.75 | 3.75 | 3.579 | 2.0% | 1.00 | 2.83 | 0.543 | 65,353,079 |
| steady / 100% over week 1 | 3.75 | 3.75 | 3.577 | 2.0% | 1.00 | 2.61 | 1.016 | 69,705,005 |
| steady / 50% in day 1 + 2 ETH window buys | 4.75 | 5.50 | 3.803 | 6.4% | 1.00 | 3.71 | 0.754 | 78,087,496 |
| weak / 50% in day 1 | 4.25 | 4.00 | 0.914 | 11.2% | 0.89 | 1.28 | 0.447 | 35,063,806 |
| weak / 100% over week 1 | 4.75 | 4.00 | 0.914 | 13.6% | 0.86 | 1.15 | 0.879 | 36,535,990 |
| hype / 50% in day 1 | 3.25 | 4.00 | 5.008 | 2.2% | 1.00 | 3.21 | 0.490 | 145,195,055 |
| hype / 100% over week 1 | 3.50 | 4.00 | 4.982 | 2.1% | 1.00 | 2.89 | 1.452 | 150,616,373 |

## Against the v3.6 launch-core rows (11.1 ETH FDV, no swarm sales)

| Scenario | v3.6 team ETH | v3.9 team ETH (50% in day 1) | v3.6 drawdown | v3.9 drawdown (50% in day 1) | v3.6 week-1 payback | v3.9 week-1 payback (50% in day 1) |
|---|---:|---:|---:|---:|---:|---:|
| steady | 3.579 | 3.586 | 1.8% | 7.5% | 3.75d | 3.75d |
| weak | 0.917 | 0.914 | 0.7% | 11.2% | 4.25d | 4.25d |
| hype | 4.996 | 5.008 | 1.9% | 2.2% | 3.50d | 3.25d |

Reading: team ETH is 1% of swap volume (platform `claimFees`) plus 10% of pack sales and 10% of the sell surcharge, exactly as v3.6 modeled it, so the fee rework itself does not move team income; the lower opening valuation and the swarm unlock do. The drawdown column is the largest peak-to-trough move of the model price inside 35 days; the swarm sales set it in the first day. Payback is the Balanced-profile maintenance cohort of week 1 (cash: realized sales plus marked tokens after fees). Lowest price / open is the model price floor relative to the 10 ETH FDV opening. Numbers are conditional model outputs; see `sim/run_v39.py`, `sim/run_v36.py` and the v3.5 assumptions. No launch-window sniping volume is predicted: the "+2 ETH window buys" row only shows the mechanics (the stepped tax buys rewards).
