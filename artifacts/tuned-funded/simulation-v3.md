# BLACKOUT v3 simulation — 35 days, 140 six-hour epochs

Explicit initial reward-pool buy capital: 40.0 ETH; pace policy: hold. This is a scenario input, not an authorized or funded transaction.

Deterministic seed 20261011. Initial AMM: 900M tokens / 10 ETH; remaining 100M held by approximately 900 NFT holders. Each run explicitly reports its initial game reward-pool buy capital. Numbers are scenario outcomes, not promised returns.

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 9.00d | 87.9% | >35 | 12.9072 | 0.9995 / 0.1400 | 3.17% |
| steady | standard | 35% | 9.00d | 86.9% | >35 | 10.8620 | 0.9995 / 0.1400 | 2.34% |
| hype | custom | 50% | not reached | 40.2% | 22.25 | 19.9587 | 0.9994 / 0.1400 | 5.31% |
| hype | standard | 50% | not reached | 39.6% | 21.0 | 16.8038 | 0.9993 / 0.1400 | 3.98% |
| weak | custom | 65% | 5.62d | 89.6% | >35 | 3.9501 | 0.2701 / 0.1400 | 3.72% |
| weak | standard | 65% | 5.50d | 90.4% | >35 | 2.9928 | 0.2250 / 0.1400 | 1.32% |

Payback is cash withdrawn after tax and market fees. Whole-cohort medians treat unrepaid farms as right-censored; not reached means at least half have not repaid within the run. Conditional realized medians include only farms repaid and must be read with their fraction. Estimated medians combine realized results with constant-last-day-yield projections for surviving unpaid farms; they exclude quitters without payback and are **not** realized results. Week 5 is heavily right-censored.

| Scenario / path | Join week | Paid farms | Whole-cohort median days | Conditional realized median days | Repaid fraction | Repaid within10d | Estimated median days |
|---|---:|---:|---:|---:|---:|---:|---:|
| steady / custom | 1 | 769 | 9.00 | 7.75 | 87.9% | 55.0% | 8.00 |
| steady / custom | 2 | 560 | n/a | 16.00 | 42.7% | 2.7% | 20.38 |
| steady / custom | 3 | 560 | n/a | 15.50 | 6.8% | 0.2% | 47.11 |
| steady / custom | 4 | 513 | n/a | n/a | 0.0% | 0.0% | 61.69 |
| steady / custom | 5 | 443 | n/a | n/a | 0.0% | 0.0% | 85.32 |
| steady / standard | 1 | 769 | 9.00 | 7.75 | 86.9% | 55.5% | 7.75 |
| steady / standard | 2 | 560 | n/a | 16.25 | 40.5% | 2.5% | 20.75 |
| steady / standard | 3 | 560 | n/a | 15.25 | 5.9% | 0.0% | 48.17 |
| steady / standard | 4 | 495 | n/a | n/a | 0.0% | 0.0% | 60.74 |
| steady / standard | 5 | 437 | n/a | n/a | 0.0% | 0.0% | 86.97 |
| hype / custom | 1 | 2490 | n/a | 7.75 | 40.2% | 27.3% | 9.25 |
| hype / custom | 2 | 744 | n/a | 15.75 | 10.6% | 1.5% | 52.23 |
| hype / custom | 3 | 247 | n/a | 18.25 | 0.4% | 0.0% | 72.71 |
| hype / custom | 4 | 113 | n/a | n/a | 0.0% | 0.0% | 93.42 |
| hype / custom | 5 | 91 | n/a | n/a | 0.0% | 0.0% | 142.44 |
| hype / standard | 1 | 2490 | n/a | 7.50 | 39.6% | 28.0% | 9.00 |
| hype / standard | 2 | 742 | n/a | 15.25 | 10.8% | 0.9% | 49.91 |
| hype / standard | 3 | 240 | n/a | n/a | 0.0% | 0.0% | 79.23 |
| hype / standard | 4 | 108 | n/a | n/a | 0.0% | 0.0% | 95.64 |
| hype / standard | 5 | 87 | n/a | n/a | 0.0% | 0.0% | 143.68 |
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
