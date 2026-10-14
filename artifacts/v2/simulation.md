# Reconstructed BLACKOUT economy simulation

Original v2 source was absent from the supplied workspace and linked research trees. This is an independently rebuilt model from the reports, with six-type items and room sets. It does **not** reproduce or certify their numerical claims.

Seed 20261010; 35 days; virtual reserve 10 ETH; sell intent 65%. All quantities below are simulation outputs.

Daily behaviour, claim delays and fee splits follow v2. Discrete items, survivor churn, whole token packs, 40-item capacity, set bonuses and a greedy placement policy are explicit reconstruction choices. Payback is conditional on still-active paid farmers (as the source model conditions on active packs), includes subsequent purchases, and marks held/queued tokens at 95% of spot; projection uses the last seven daily yields, capped at 120 days. Never-paying farmers are reported separately; finite means are not guarantees.

## Steady

| Day | Active | Packs | Pack ETH | Reward tokens | Locked/burned | ETH / 1M tokens | Net ETH/pack/day | Total sell fee | Tariff | Team ETH |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 150 | 450 | 0.0100 | 194.56M | 26.36M | 0.0195 | 0.000169 | 1.25% | 0.135 | 0.691 |
| 3 | 441 | 297 | 0.0100 | 319.51M | 56.59M | 0.0332 | 0.000213 | 1.25% | 0.109 | 1.568 |
| 7 | 909 | 206 | 0.0100 | 379.74M | 96.36M | 0.0531 | 0.000293 | 1.25% | 0.100 | 2.727 |
| 14 | 1497 | 279 | 0.0085 | 412.37M | 161.01M | 0.0967 | 0.000333 | 1.25% | 0.100 | 5.198 |
| 21 | 1853 | 345 | 0.0072 | 392.89M | 217.56M | 0.1601 | 0.000359 | 1.25% | 0.100 | 7.878 |
| 28 | 2189 | 388 | 0.0061 | 352.31M | 265.53M | 0.2177 | 0.000302 | 1.25% | 0.100 | 10.508 |
| 35 | 2443 | 378 | 0.0060 | 308.98M | 307.26M | 0.2720 | 0.000266 | 1.25% | 0.100 | 13.134 |

| Join week | Active-farmer finite mean payback (days) | No projected payback by 120 days |
|---:|---:|---:|
| 1 | 26.8 | 0.7% |
| 2 | 32.6 | 3.1% |
| 3 | 34.5 | 6.1% |
| 4 | 34.9 | 7.6% |
| 5 | 37.8 | 32.9% |

Paid farmers that left by the horizon: 26.7%. They are excluded from the conditional payback table, not assumed profitable.


Reconstructed stall criterion: day 34. Team 13.134 ETH (14.97% of routed inflow); heartbeat 8.661 ETH. Starter packs 700; token packs 20; referrals 7.858M tokens; inspection 4.663M; withdrawal tax recycled 24.179M. Maximum token conservation error 3.69549e-06 tokens.

## Hype

| Day | Active | Packs | Pack ETH | Reward tokens | Locked/burned | ETH / 1M tokens | Net ETH/pack/day | Total sell fee | Tariff | Team ETH |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 625 | 1875 | 0.0100 | 474.19M | 38.89M | 0.0617 | 0.000317 | 1.25% | 0.150 | 2.881 |
| 3 | 1520 | 1184 | 0.0101 | 589.26M | 76.10M | 0.1933 | 0.000616 | 1.25% | 0.150 | 6.967 |
| 7 | 2805 | 710 | 0.0100 | 580.65M | 124.94M | 0.3745 | 0.000777 | 1.25% | 0.150 | 12.549 |
| 14 | 3482 | 331 | 0.0085 | 488.29M | 196.21M | 0.3205 | 0.000388 | 2.25% | 0.266 | 17.008 |
| 21 | 3356 | 212 | 0.0072 | 400.47M | 260.02M | 0.3111 | 0.000277 | 1.51% | 0.266 | 19.161 |
| 28 | 3019 | 182 | 0.0061 | 324.69M | 312.36M | 0.2966 | 0.000222 | 1.49% | 0.266 | 20.622 |
| 35 | 2673 | 150 | 0.0060 | 264.74M | 355.23M | 0.2918 | 0.000177 | 1.43% | 0.266 | 21.877 |

| Join week | Active-farmer finite mean payback (days) | No projected payback by 120 days |
|---:|---:|---:|
| 1 | 39.1 | 16.1% |
| 2 | 45.7 | 21.0% |
| 3 | 51.3 | 32.1% |
| 4 | 50.7 | 20.3% |
| 5 | 50.8 | 45.4% |

Paid farmers that left by the horizon: 44.5%. They are excluded from the conditional payback table, not assumed profitable.


Reconstructed stall criterion: day 13. Team 21.877 ETH (14.97% of routed inflow); heartbeat 14.412 ETH. Starter packs 700; token packs 1; referrals 10.446M tokens; inspection 5.596M; withdrawal tax recycled 25.544M. Maximum token conservation error 8.70228e-06 tokens.

## Weak

| Day | Active | Packs | Pack ETH | Reward tokens | Locked/burned | ETH / 1M tokens | Net ETH/pack/day | Total sell fee | Tariff | Team ETH |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 45 | 135 | 0.0100 | 69.17M | 11.18M | 0.0133 | 0.000140 | 1.25% | 0.135 | 0.207 |
| 3 | 204 | 69 | 0.0100 | 123.76M | 25.11M | 0.0157 | 0.000124 | 1.25% | 0.109 | 0.424 |
| 7 | 549 | 64 | 0.0100 | 188.14M | 51.83M | 0.0201 | 0.000153 | 1.25% | 0.100 | 0.810 |
| 14 | 801 | 67 | 0.0085 | 248.15M | 99.88M | 0.0283 | 0.000225 | 1.25% | 0.100 | 1.518 |
| 21 | 797 | 75 | 0.0072 | 259.88M | 143.25M | 0.0376 | 0.000221 | 1.25% | 0.100 | 2.153 |
| 28 | 767 | 61 | 0.0061 | 240.31M | 180.05M | 0.0439 | 0.000219 | 1.25% | 0.100 | 2.626 |
| 35 | 719 | 53 | 0.0060 | 214.65M | 211.44M | 0.0484 | 0.000203 | 1.25% | 0.100 | 3.013 |

| Join week | Active-farmer finite mean payback (days) | No projected payback by 120 days |
|---:|---:|---:|
| 1 | 44.8 | 5.1% |
| 2 | 46.3 | 11.8% |
| 3 | 61.1 | 22.4% |
| 4 | 60.6 | 27.8% |
| 5 | 67.0 | 49.0% |

Paid farmers that left by the horizon: 38.5%. They are excluded from the conditional payback table, not assumed profitable.


Reconstructed stall criterion: day 16. Team 3.013 ETH (14.86% of routed inflow); heartbeat 1.981 ETH. Starter packs 700; token packs 0; referrals 3.012M tokens; inspection 2.818M; withdrawal tax recycled 14.422M. Maximum token conservation error 1.0252e-05 tokens.

## Set and liquidity sensitivity

| Case (steady) | Day-35 pool | Price ETH/1M | Team ETH | Stall |
|---|---:|---:|---:|---:|
| sets disabled | 309.17M | 0.2714 | 13.048 | 34 |
| sets enabled | 308.98M | 0.2720 | 13.134 | 34 |
| 3 ETH depth | 325.60M | 0.3605 | 14.904 | 35 |
| 5 ETH depth | 317.39M | 0.3418 | 14.363 | 35 |
| 90% sell intent | 326.92M | 0.1967 | 12.254 | 21 |
| no swarm sells | 289.78M | 0.3014 | 13.456 | 35 |

The behavioural coefficients are unmeasured. The pool staying positive does not imply profitable players. Virtual liquidity is not real redeemable ETH. No token price, yield, return, or launch liquidity is promised. Generator participation defaults to zero because the reports supply no adoption assumption.
