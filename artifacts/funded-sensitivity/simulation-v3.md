# BLACKOUT v3 simulation — 35 days, 140 six-hour epochs

Explicit initial reward-pool buy capital: 40.0 ETH; pace policy: reduce. This is a scenario input, not an authorized or funded transaction.

Deterministic seed 20261011. Initial AMM: 900M tokens / 10 ETH; remaining 100M held by approximately 900 NFT holders. Each run explicitly reports its initial game reward-pool buy capital. Numbers are scenario outcomes, not promised returns.

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 9.25d | 89.3% | >35 | 14.5387 | 0.9995 / 0.1400 | 3.87% |
| steady | standard | 35% | 9.00d | 88.9% | >35 | 12.3716 | 0.9995 / 0.1400 | 3.22% |
| hype | custom | 50% | not reached | 44.0% | 20.25 | 20.4358 | 0.9993 / 0.1400 | 5.26% |
| hype | standard | 50% | not reached | 44.3% | 20.75 | 17.3573 | 0.9993 / 0.1400 | 5.05% |
| weak | custom | 65% | 5.62d | 89.6% | >35 | 3.9501 | 0.2701 / 0.1400 | 3.72% |
| weak | standard | 65% | 5.50d | 90.4% | >35 | 2.9928 | 0.2250 / 0.1400 | 1.32% |

Payback is cash withdrawn after tax and market fees. Whole-cohort medians treat unrepaid farms as right-censored; not reached means at least half have not repaid within the run. Conditional realized medians include only farms repaid and must be read with their fraction. Estimated medians combine realized results with constant-last-day-yield projections for surviving unpaid farms; they exclude quitters without payback and are **not** realized results. Week 5 is heavily right-censored.

| Scenario / path | Join week | Paid farms | Whole-cohort median days | Conditional realized median days | Repaid fraction | Repaid within10d | Estimated median days |
|---|---:|---:|---:|---:|---:|---:|---:|
| steady / custom | 1 | 769 | 9.25 | 8.00 | 89.3% | 55.0% | 8.25 |
| steady / custom | 2 | 560 | 19.75 | 15.50 | 63.0% | 4.3% | 16.75 |
| steady / custom | 3 | 560 | n/a | 16.00 | 3.9% | 0.0% | 90.16 |
| steady / custom | 4 | 536 | n/a | n/a | 0.0% | 0.0% | 103.09 |
| steady / custom | 5 | 469 | n/a | n/a | 0.0% | 0.0% | 70.52 |
| steady / standard | 1 | 769 | 9.00 | 7.75 | 88.9% | 55.1% | 8.00 |
| steady / standard | 2 | 560 | 20.00 | 15.25 | 60.9% | 4.1% | 16.75 |
| steady / standard | 3 | 560 | n/a | 16.75 | 4.8% | 0.0% | 85.20 |
| steady / standard | 4 | 538 | n/a | n/a | 0.0% | 0.0% | 101.54 |
| steady / standard | 5 | 457 | n/a | n/a | 0.0% | 0.0% | 76.45 |
| hype / custom | 1 | 2490 | n/a | 8.00 | 44.0% | 28.2% | 9.75 |
| hype / custom | 2 | 745 | n/a | 15.62 | 7.5% | 1.5% | 126.18 |
| hype / custom | 3 | 225 | n/a | n/a | 0.0% | 0.0% | 352.06 |
| hype / custom | 4 | 101 | n/a | n/a | 0.0% | 0.0% | 79.99 |
| hype / custom | 5 | 77 | n/a | n/a | 0.0% | 0.0% | 125.52 |
| hype / standard | 1 | 2490 | n/a | 8.00 | 44.3% | 29.0% | 9.62 |
| hype / standard | 2 | 743 | n/a | 14.75 | 6.6% | 1.2% | 138.47 |
| hype / standard | 3 | 234 | n/a | n/a | 0.0% | 0.0% | 192.75 |
| hype / standard | 4 | 109 | n/a | n/a | 0.0% | 0.0% | 73.03 |
| hype / standard | 5 | 84 | n/a | n/a | 0.0% | 0.0% | 108.71 |
| weak / custom | 1 | 260 | 5.62 | 4.75 | 89.6% | 72.3% | 5.00 |
| weak / custom | 2 | 181 | n/a | 15.75 | 41.4% | 3.9% | 20.50 |
| weak / custom | 3 | 123 | n/a | 14.00 | 3.3% | 0.0% | 56.96 |
| weak / custom | 4 | 88 | n/a | n/a | 0.0% | 0.0% | 74.36 |
| weak / custom | 5 | 56 | n/a | n/a | 0.0% | 0.0% | 114.46 |
| weak / standard | 1 | 261 | 5.50 | 5.00 | 90.4% | 75.1% | 5.00 |
| weak / standard | 2 | 173 | n/a | 15.75 | 46.8% | 3.5% | 18.50 |
| weak / standard | 3 | 121 | n/a | 12.75 | 2.5% | 0.0% | 51.86 |
| weak / standard | 4 | 85 | n/a | n/a | 0.0% | 0.0% | 73.42 |
| weak / standard | 5 | 54 | n/a | n/a | 0.0% | 0.0% | 111.85 |

Full per-epoch data and conservation errors: `artifacts/simulation-v3.json`. Event loss is measured against a parallel no-event item-health counterfactual under the same policy, budget and prices; accumulated damage and destruction remain in that counterfactual. Churn, repair and lottery timing are scenario assumptions.
