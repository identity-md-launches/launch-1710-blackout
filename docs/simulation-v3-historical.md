# Simulation provenance and limits

`sim/blackout_sim_v3.py` is a new standard-library-only, deterministic scenario model for the v3 contracts. The previous job's `sim/blackout_sim_v2.py` and archived artifacts remain as historical evidence; they are not v3 verification. No original external v2 simulator is claimed to have been recovered. The prior repository's assumed initial constant-product liquidity (900M tokens /10 ETH),100M swarm allocation, and steady/hype/weak arrival shapes are retained as modeling assumptions, not verified launch commitments.

## Reproduce

```sh
python3 sim/blackout_sim_v3.py --check
python3 sim/blackout_sim_v3.py
python3 sim/blackout_sim_v3.py --bootstrap-eth 40 --output artifacts/funded-sensitivity
python3 sim/blackout_sim_v3.py --bootstrap-eth 40 --pace-policy hold --output artifacts/tuned-funded
python3 sim/tune_v3.py
python3 sim/policy_sensitivity_v3.py
```

These programs do no network calls or transactions. `--bootstrap-eth` represents a hypothetical additional ETH-funded pool token purchase and donation before play. It is external capital, not a token mint, fee income or a supplied deployment value. The main run uses **zero** initial reward-pool endowment. Do not silently adopt the funded sensitivity as the launch budget.

## Scenario inputs

- 35 days, 140 six-hour steps, seed 20261011. All 140 shifts and settlement batches occur on time. Costs of keeper gas and latency are not modeled.
- Approximately 900 Identity MD holders share the existing 100M allocation. The model sells 35%/50%/65% of that allocation over the first 14 days in steady/hype/weak. Exactly 900 starter claims arrive uniformly between hour 48 and day 16. Snapshot ownership is assumed valid.
- Steady new paid farms/day:150 for the first 3 days, then 80. Hype: `600*exp(-day/5)+25`. Weak: `40*exp(-day/15)+5`. Joining demand scales down by `min(1,sqrt(21/currentPaybackForecast))`. These behavioral curves are assumptions, not forecasts derived from users.
- New farms purchase about `3*(0.010/currentPackPrice)^0.7` packs, rounded to at least one. Inventory capacity limits actual opening. Equipment is selected greedily by standalone hash across unlocked rooms; it does not globally optimize combinations. Unequipped excess is retained. No speculative item resale exists because items are soulbound.
- Sale intent is **65%** of available internal holdings at each step, with 35% retained/reinvested. Requested withdrawals wait 0/3/7 days with weights 40/30/30; immediate intent executes on the next six-hour step. Vintage-age taxes are applied at modeled execution. The queue approximates per-epoch vintages and can include older retained rewards; it is not an exact EVM replay.
- 40% referral adoption is modeled as an aggregate 5% gross reward on top. Attribution is aggregated to the earning farm for token conservation; actual on-chain referrals pay the inviter. This affects individual payback interpretation.
- Maintenance recycles 3% of net yield and restores 0.6 durability points per step, with identical restoration in the no-event shadow. This is a behavioral approximation, not the exact discrete repair price/action. Token pack attempt probability is 0.75% per epoch; ETH lobby is 0.00001 per active farm/epoch. Expansion, overclock purchases, merging, and scrap *behavior* are not simulated; the global scrap reserve is modeled. Contract tests cover their actual accounting.
- Churn probability/day is 1.5% when recent daily yield is at least 2% of paid cost, otherwise 7.5%, sampled per epoch. Quitters retain tokens/items and can finish queued withdrawals; new mining stops. The same externally sampled participation is used for event-loss comparison.
- External round-trip volume is 50% of pack ETH volume. Trades conserve token inventory. Pool buys and swaps include project/network fees; progressive custom surcharge is a capped aggregate pressure proxy rather than the contract's exact rolling-hour/day/TWAP formula. Price impact follows an unconcentrated constant-product AMM, not a full v4 liquidity distribution.
- Spot price approximates a thirty-minute TWAP within a six-hour step. The simulation does not model oracle attacks, slippage rejection, liquidity withdrawal, sequencer manipulation or MEV. Foundry separately tests actual TWAP and v4 settlement behavior.
- Weekly district packs, ticket-weighted distinct lottery winners and 1% season emission are included; a lottery item can wait for inventory in the real contract, while the model records its entitlement as owned. Weekly lottery uses the model's ordinary Epic+ draw approximation; contract lottery is explicitly 90% Epic/10% Legendary.

## Policy and outcomes

Default emission starts 3.5%, rises only in 10% daily steps toward 6% when payback is poor and conservative runway permits; tariff starts 15%, falls toward 10%. Target pace 20/hour reduces toward 10 under the baseline policy; this slows item issuance but can worsen demand in a decaying hype scenario. Positive mix starts 25% and can rise toward 50%. Hard Params values and the contract's rolling caps remain binding.

The model assumes timely swarm plans following the fallback-shaped event schedule, with minimum permitted negative severity 50% and full positive severity. It is a tuned operating case. Autonomous missing-plan/expired-hash behavior uses severity 100% on-chain and is covered by contract tests; do not project the tuned loss result onto an unattended deployment. Event loss is a parallel no-negative-event health/destruction counterfactual using the same prices, emission policy, participants and budget. It includes lasting damage; it does not count price changes caused by a different hypothetical whole-economy path. Loss is expressed against counterfactual gross mining before electricity. Dividing the reported loss ratio by 0.70 gives a conservative after-tariff bound at the maximum 30% tariff; the tuned case remains below 10% on that stricter denominator. Per-farm positive differences are clipped to zero before summing, so one farm's Green gain cannot hide another's damage.

Realized payback means cash received after withdrawal tax, trading fees and market price impact reaches cumulative modeled pack/lobby cost. The main table reports the median across the **whole joining cohort**, treating unrepaid farms as right-censored; it is not reached when half or more are still unrepaid. Detailed tables additionally show conditional medians among only repaid farms, fractions repaid and fractions repaid within ten days. None implies every joiner recovers cost. Estimated medians additionally project surviving unpaid farms at constant last-day yield and exclude unrepaid quitters. Later joining weeks are right-censored; week 5 often has no realized payback. Those estimates are labeled separately.

Stall is the first day from day 3 when either active farms fall below 25% of their prior peak or the median live-farm forward cost / recent daily mining exceeds 60 days. It is an explicit economic-health definition, not a contract halt or pool exhaustion. Thus weak growth can remain mechanically alive despite poor payback. Runway is available tokens divided by conservative gross daily commitments; percentage emission can keep that ratio healthy while ETH purchasing power falls.

All 1B tokens reconcile each epoch across AMM, swarm, pool, reservations, internal holdings and pending withdrawals. Floating-point tolerance is 0.02 token in 1B; actual recorded errors are much smaller. This checks accounting, not economic truth. ETH tables include team receipts, heartbeat balance and bounties paid; they exclude gas, taxes outside the game and recipient investment returns.

The zero-endowment main outcomes do **not** satisfy all requested economic targets. The explicitly funded 40 ETH, hold-pace scenario reaches a 9-day whole-cohort steady median, 22.25/21-day hype stall and≤5.32% gross weekly event losses in the two fee paths. The report states the shortfall and separates conditional funded sensitivities. Parameter tuning cannot create external ETH or guarantee a return; a funding/liquidity/demand decision and a new simulation are required before an economic go decision.
