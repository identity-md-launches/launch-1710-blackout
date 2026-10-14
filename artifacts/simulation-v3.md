# BLACKOUT v3 simulation — 35 days, 140 six-hour epochs

Explicit initial reward-pool buy capital: 0.0 ETH; pace policy: reduce. This is a scenario input, not an authorized or funded transaction.

Deterministic seed 20261011. Initial AMM: 900M tokens / 10 ETH; remaining 100M held by approximately 900 NFT holders. Each run explicitly reports its initial game reward-pool buy capital. Numbers are scenario outcomes, not promised returns.

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 22.25d | 61.8% | >35 | 13.4992 | 0.9995 / 0.1400 | 3.45% |
| steady | standard | 35% | 22.25d | 61.9% | >35 | 11.9588 | 0.9995 / 0.1400 | 3.26% |
| hype | custom | 50% | not reached | 25.6% | 19.0 | 17.9693 | 0.9993 / 0.1400 | 3.15% |
| hype | standard | 50% | not reached | 26.0% | 17.25 | 15.7229 | 0.9993 / 0.1400 | 2.14% |
| weak | custom | 65% | not reached | 18.8% | >35 | 2.4898 | 0.1824 / 0.1400 | 3.21% |
| weak | standard | 65% | not reached | 20.5% | >35 | 2.2694 | 0.1792 / 0.1400 | 3.30% |

Payback is cash withdrawn after tax and market fees. Whole-cohort medians treat unrepaid farms as right-censored; not reached means at least half have not repaid within the run. Conditional realized medians include only farms repaid and must be read with their fraction. Estimated medians combine realized results with constant-last-day-yield projections for surviving unpaid farms; they exclude quitters without payback and are **not** realized results. Week 5 is heavily right-censored.

| Scenario / path | Join week | Paid farms | Whole-cohort median days | Conditional realized median days | Repaid fraction | Repaid within10d | Estimated median days |
|---|---:|---:|---:|---:|---:|---:|---:|
| steady / custom | 1 | 770 | 22.25 | 16.25 | 61.8% | 4.9% | 17.75 |
| steady / custom | 2 | 560 | n/a | 19.00 | 12.3% | 0.2% | 50.27 |
| steady / custom | 3 | 530 | n/a | 16.25 | 2.6% | 0.0% | 52.80 |
| steady / custom | 4 | 467 | n/a | 13.50 | 0.2% | 0.0% | 55.52 |
| steady / custom | 5 | 437 | n/a | n/a | 0.0% | 0.0% | 74.50 |
| steady / standard | 1 | 770 | 22.25 | 16.25 | 61.9% | 5.6% | 17.50 |
| steady / standard | 2 | 560 | n/a | 17.25 | 9.8% | 0.4% | 55.26 |
| steady / standard | 3 | 520 | n/a | 17.50 | 3.3% | 0.0% | 53.72 |
| steady / standard | 4 | 450 | n/a | n/a | 0.0% | 0.0% | 55.42 |
| steady / standard | 5 | 427 | n/a | n/a | 0.0% | 0.0% | 74.89 |
| hype / custom | 1 | 2490 | n/a | 10.25 | 25.6% | 12.3% | 14.25 |
| hype / custom | 2 | 721 | n/a | 20.25 | 1.7% | 0.0% | 219.45 |
| hype / custom | 3 | 208 | n/a | 14.00 | 0.5% | 0.0% | 69.45 |
| hype / custom | 4 | 93 | n/a | n/a | 0.0% | 0.0% | 83.04 |
| hype / custom | 5 | 78 | n/a | n/a | 0.0% | 0.0% | 133.13 |
| hype / standard | 1 | 2490 | n/a | 10.25 | 26.0% | 12.8% | 14.25 |
| hype / standard | 2 | 715 | n/a | 17.62 | 1.1% | 0.0% | 248.76 |
| hype / standard | 3 | 192 | n/a | 17.75 | 1.6% | 0.0% | 69.19 |
| hype / standard | 4 | 98 | n/a | n/a | 0.0% | 0.0% | 76.07 |
| hype / standard | 5 | 78 | n/a | n/a | 0.0% | 0.0% | 133.27 |
| weak / custom | 1 | 234 | n/a | 21.75 | 18.8% | 0.0% | 36.46 |
| weak / custom | 2 | 160 | n/a | 20.25 | 6.9% | 0.6% | 58.45 |
| weak / custom | 3 | 96 | n/a | n/a | 0.0% | 0.0% | 69.46 |
| weak / custom | 4 | 66 | n/a | n/a | 0.0% | 0.0% | 90.89 |
| weak / custom | 5 | 48 | n/a | n/a | 0.0% | 0.0% | 118.93 |
| weak / standard | 1 | 234 | n/a | 24.12 | 20.5% | 0.0% | 35.78 |
| weak / standard | 2 | 157 | n/a | 22.75 | 5.1% | 0.0% | 60.47 |
| weak / standard | 3 | 97 | n/a | n/a | 0.0% | 0.0% | 84.77 |
| weak / standard | 4 | 65 | n/a | n/a | 0.0% | 0.0% | 85.16 |
| weak / standard | 5 | 50 | n/a | n/a | 0.0% | 0.0% | 130.23 |

Full per-epoch data and conservation errors: `artifacts/simulation-v3.json`. Event loss is measured against a parallel no-event item-health counterfactual under the same policy, budget and prices; accumulated damage and destruction remain in that counterfactual. Churn, repair and lottery timing are scenario assumptions.
