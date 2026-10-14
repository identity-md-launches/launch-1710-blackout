# BLACKOUT v3 implementation report

This assignment replaces the v2 mechanics from job **80dc62dc** with an immutable v3 implementation, tests, a dry-run regulator and a reproducible 35-day simulation. **No contract or token was deployed, no transaction was broadcast, and no live funds were spent.** Existing build settings, dependency sources, lockfiles and remappings are unchanged.

The technical deliverable is implemented and locally checked. The final suite reports 86 passing tests, one offline-only fork skip, and one separately passing live fork smoke; build and formatting checks pass. **The zero-endowment economic baseline does not meet all requested tuning targets:** steady week-1 whole-cohort payback exceeds 10 days and hype stalls before 21 days under the stated model. Event loss meets the 10% threshold in the tuned, timely-plan scenario. Funded sensitivities are labeled hypothetical and are not silently assumed launch resources. These are material economic open items, not a passing-result claim.

## Changes from 80dc62dc

| Area | Previous design | v3 result |
|---|---|---|
| Epochs | Half-day checkpoint/daily settlement | Six-hour call-triggered epochs, no gap accrual, one pull bounty, batched bounded settlement. |
| Token sinks | BurnVault and Generator-related mechanics | Both contracts removed; all game token spends recycle to pool. Withdrawal tax is fully reserved for active farms next epoch. |
| ETH | Prior revenue routing/team-change behavior | Fixed 85/13/2 pack/lobby/surcharge splits, fixed team, 1 ETH heartbeat cap, excess pool buy. |
| Swap fees | Prior standard fee/custom surcharge integration | Preferred 2% project +0.25% network + capped sell surcharge; fallback 1% project +0.25%, no surcharge. Executable reference and existing-hook adapter both tested. |
| Packs | Beta/daily quantity limits and previous price curve | Unlimited marginal VRGDA purchases, 30-minute TWAP token packs with 10% discount, 3 future-block items, specified rarities. |
| Items/rooms | Six equipment types, room keys, standalone slots | Twelve soulbound types, room-only placement, 6 unique-type slots, specified combos, level/age room gates. |
| Progression | Previous maintenance/room rules |15-slot inventory, scrap/merge/expansion, XP/level equip gates, durability, 5 overclock levels. |
| Mining | Prior whale cap/daily accounting | No whale cap; per-epoch raw/productive hash, pool-only emission, bounded vintage tax and 5% internal purchasing bonus. |
| Events | Previous grid/tick selection | Next-two-epoch plans, future-block districts/farms, full fallback table, rolling caps, lobbying, automatic supply drops. |
| Seasons | Prior inspection mechanism | Weekly district packs, weighted three-distinct-farm lottery, best spend/yield farm prize. |
| Holders | Previous starter/perk behavior | Exactly one snapshot entitlement per tokenId, hour 48–day 16, Rare 92/Epic 8, half mining until a paid pack; no other holder perk. |
| Operations | Prior environment/broadcast script and guide | Explicit-config local construction helpers; no broadcast path; dry-run regulator and deployment responsibility table. |

The existing v4 hook/oracle integration, chain-clock abstraction, vendored libraries and Merkle tooling were retained and adapted. New FarmEngine separates bounded room/event calculation from FarmCore so all application runtimes remain deployable under EIP-170 without changing compiler settings. Historical evidence is preserved under `artifacts/v2/`; it does not describe this version.

## Params and immutable limits

Only immutable swarmWallet can call `Params.set`. Every change needs a nonempty herald letter, hard bounds and at most `floor(old/10)` relative movement per key per 24 hours, including the first change after construction. There is no owner, upgrade, pause, team-change setter or administrative asset withdrawal. Baseline percentages below are fractions of the relevant yield/price unless described as coefficients. Token prices assume 18 decimals.

| Key | Default | Bounds | Meaning |
|---|---:|---:|---|
| EmissionBps | 3.5% / day | 2–6% / day | Nominal pool-funded mining; 116% reservation headroom. |
| TariffBps | 15% | 10–30% | Electricity recycled from yield. |
| PriceStepBps | 1% | 0.5–2% | Marginal pack increase above pace. |
| PriceFloor | 0.006 ETH | 0.004–0.010 ETH | VRGDA floor. |
| PriceCeiling | 0.030 ETH | 0.020–0.050 ETH | VRGDA ceiling. |
| PriceStart | 0.010 ETH | 0.008–0.015 ETH | VRGDA reference price. |
| DemandTarget | 20 packs/hour | 10–40 packs/hour | Pace and epoch supply-drop threshold. |
| PriceDecayBps | 2% / hour behind | 1–4% | Below-pace decay. |
| RepairBps | 250 | 150–400 | Repair-price coefficient; formula in design. |
| LobbyKBps | 5000 | 2500–10000 | Lobby reduction-strength coefficient. |
| LobbyMinWeight | 0.40 | 0.40–0.70 | Minimum district negative weight. |
| FullSetBps | 15% | 5–15% | All five tags. |
| ComputePairBps | 10% | 5–10% | GPU+ASIC. |
| TripleCoreBps | 20% | 10–20% | GPU+ASIC+FPGA, replaces pair. |
| AirflowBps | 5% | 2.5–5% | Fan+Rack hash bonus. |
| ElectricityPairBps | 15% | 5–15% | PSU+Liquid electricity saving. |
| OffgridBps | 20% | 10–20% | Solar+Battery electricity saving. |
| RareSetBps | 5% | 2.5–5% | Three Rare, highest rarity set only. |
| EpicSetBps | 10% | 5–10% | Three Epic. |
| LegendarySetBps | 20% | 10–20% | Three Legendary. |
| MythicSetBps | 30% | 15–30% | Three Mythic. |
| SetCapBps | 40% | 30–40% | Total additive hash-bonus cap. |
| BuyBatch | 0.5 ETH | 0.1–1 ETH | Maximum per pool-buy transaction, not a minimum. |
| SlippageBps | 3% | 2.5–5% | Maximum shortfall against thirty-minute TWAP. |
| SellHourBps | 500 | 200–600 | Custom rolling-hour pressure coefficient. |
| SellDayBps | 400 | 100–500 | Custom rolling-day pressure coefficient. |
| SellDeviationBps | 5000 | 2000–5000 | Custom spot/TWAP deviation coefficient. |
| Bounty | 0.001 ETH | 0.0005–0.003 ETH | Per successful shift, limited by heartbeat balance. |
| ExpansionPrice | 100 tokens | 50–500 tokens | Expansion base; cost rises quadratically. |
| MergePrice | 50 tokens | 25–250 tokens | Merge base; also cable repair price. |
| OverclockPrice | 100 tokens | 50–500 tokens | Per next overclock level coefficient. |
| PositiveWeight | 25% | 20–50% | Extra positive fallback substitution probability. |

Other fixed rules include 6-hour epochs, 1 ETH heartbeat cap, 15 initial inventory slots, 5 slots per expansion, 4 rooms ×6 slots, 0.5 durability wear/epoch, 5 overclock levels, 5% referral, 5% internal spending bonus, 5–20% withdrawal tax over 7 days, 10% token-pack discount, 3-day lobby half-life, 2-day outage district cooldown, 32 reward-vintage slots, up to 8 farms per processing call and 64 participants per season scoring call. Event severity is 5000–10000 basis points, submitted per plan; fixed fee splits cannot be changed by Params.

## Simulation results

The baseline starts with 900M AMM tokens/10 ETH and 100M held by approximately 900 snapshot holders, **zero initial game pool funding**,140 six-hour steps and deterministic seed 20261011. Holder sales are 35/50/65% of their 100M in the first 14 days. See [model assumptions](docs/simulation-assumptions.md) for demand, repair/churn, cashout and AMM approximations. The operating case submits low-severity negative plans on time; unattended fallback is a separate, harsher case.

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day 35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 22.25d | 61.8% | >35 | 13.4992 | 0.9995 / 0.1400 | 3.45% |
| steady | standard | 35% | 22.25d | 61.9% | >35 | 11.9588 | 0.9995 / 0.1400 | 3.26% |
| hype | custom | 50% | not reached | 25.6% | 19.0 | 17.9693 | 0.9993 / 0.1400 | 3.15% |
| hype | standard | 50% | not reached | 26.0% | 17.25 | 15.7229 | 0.9993 / 0.1400 | 2.14% |
| weak | custom | 65% | not reached | 18.8% | >35 | 2.4898 | 0.1824 / 0.1400 | 3.21% |
| weak | standard | 65% | not reached | 20.5% | >35 | 2.2694 | 0.1792 / 0.1400 | 3.30% |

The headline medians include the entire joining cohort, treating unrepaid farms as right-censored. A median is not reached when half or more remain unpaid within 35 days. The detailed tables also report conditional medians among repaid farms and the fraction repaid within 10 days; neither estimates a universal return. [All five joining-week cohorts and per-epoch data](artifacts/simulation-v3.md) report realized and explicitly projected figures separately; [JSON](artifacts/simulation-v3.json) includes conservation checks, prices, active population and weekly event losses.

Emission was tuned from default 3.5% toward 6% within daily steps and tariff toward 10%, with pace and positive mix adjustments. This preserves a conservative instantaneous 14.37-day gross-commitment runway at maximum emission. A lower event severity removes the prior full-severity event-loss breach. It does not solve insufficient ETH inflow. The [funding sweep](artifacts/funding-sensitivity-v3.json) examines 0/5/10/20/40 ETH of explicit extra pool-buy capital; [pace-policy sensitivity](artifacts/policy-sensitivity-v3.json) compares holding pace and raising pace under severe payback deterioration against the baseline's reduction.

A 40 ETH **hypothetical upfront buy and donation**, under the same baseline policy, produces:

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day 35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 9.25d | 89.3% | >35 | 14.5387 | 0.9995 / 0.1400 | 3.87% |
| steady | standard | 35% | 9.00d | 88.9% | >35 | 12.3716 | 0.9995 / 0.1400 | 3.22% |
| hype | custom | 50% | not reached | 44.0% | 20.25 | 20.4358 | 0.9993 / 0.1400 | 5.26% |
| hype | standard | 50% | not reached | 44.3% | 20.75 | 17.3573 | 0.9993 / 0.1400 | 5.05% |
| weak | custom | 65% | 5.62d | 89.6% | >35 | 3.9501 | 0.2701 / 0.1400 | 3.72% |
| weak | standard | 65% | 5.50d | 90.4% | >35 | 2.9928 | 0.2250 / 0.1400 | 1.32% |

This sensitivity improves steady week-1 payback but still does not establish all targets across hype paths. It requires capital the requester has not supplied and changes initial price/liquidity exposure. The full funded cohorts are in [the funded report](artifacts/funded-sensitivity/simulation-v3.md). No contract depends on an invented funding source. Realized payback and stall estimates remain behavioral scenarios, not promises.

## Explicitly funded, tuned policy

The policy sweep found that holding target pace at 20/hour performs better for the funded hype case than reducing or later raising it. The full 40 ETH upfront-capital, `--pace-policy hold` rerun gives:

| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day 35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | custom | 35% | 9.00d | 87.9% | >35 | 12.9072 | 0.9995 / 0.1400 | 3.17% |
| steady | standard | 35% | 9.00d | 86.9% | >35 | 10.8620 | 0.9995 / 0.1400 | 2.34% |
| hype | custom | 50% | not reached | 40.2% | 22.25 | 19.9587 | 0.9994 / 0.1400 | 5.31% |
| hype | standard | 50% | not reached | 39.6% | 21.0 | 16.8038 | 0.9993 / 0.1400 | 3.98% |
| weak | custom | 65% | 5.62d | 89.6% | >35 | 3.9501 | 0.2701 / 0.1400 | 3.72% |
| weak | standard | 65% | 5.50d | 90.4% | >35 | 2.9928 | 0.2250 / 0.1400 | 1.32% |

Target checks for this explicitly funded case: steady whole-cohort median ≤10d: **True**; steady/hype alive ≥21d: **True**; maximum weekly event loss: **5.31%** of counterfactual gross mining. A conservative after-electricity bound at the maximum 30% tariff is **7.59%**, also below 10%. [All five cohorts and epoch data](artifacts/tuned-funded/simulation-v3.md) remain available.

This is a conditional parameter/funding result, not the unfunded baseline. It explicitly needs 40 ETH extra initial capital and timely low-severity event plans. The standard hype case reaches the 21-day threshold without a large safety margin, and fewer than half its week-1 farms recover cost within the run. Thus the requested median steady payback/alive/event thresholds can coexist in this model, but the implementation does not guarantee returns or provide the assumed funding.

## Verification

Final command results and sizes are recorded in `artifacts/verification-v3.json`, `build-v3.txt`, `foundry-v3.txt`, `fmt-v3.txt`, `runtime-sizes-v3.json` and `gas-actions-v3.txt`. The default offline suite includes a deliberately skipped live-chain smoke test; the separately selected Robinhood fork run passes. Solidity is exactly the existing pinned 0.8.26; no build/dependency changes, FFI, environment mutation in tests, or external downloads are needed for local compilation/tests.

Coverage includes token conservation/no burns, reserve backing, split/cap accounting, unauthorized and failed transfers, callback/reentrancy attempts, level/room gates, soulbound custody, inventory pressure, unlimited pack receipts, VRGDA boundaries/marginal pricing, early/delayed epoch calls, one bounty, fallback/event quotas, snapshot timing, supply drops, exact top-decile audit, tax redistribution, season duplicate/late/expiry handling, starter windows and both swap paths. Stateful invariants use 128 runs ×64 calls; fuzz tests use 256 runs. Real local PoolManager tests cover custom system buys/sells and existing-standard-hook adapter settlement without an extra fee layer.

The Robinhood smoke uses chain 4663 and public RPC `https://rpc.mainnet.chain.robinhood.com`, consistent with the official [network documentation](https://docs.robinhood.com/chain/add-network-to-wallet/). It reads live ArbSys native block number/hash and replays them into Foundry's non-ArbOS EVM. [Fork output](artifacts/robinhood-fork-v3.txt) is evidence of this narrow smoke, not full application deployment against an as-yet-unspecified token/market.

`advanceEpoch` is tested with both an empty roster and 1,000 actually equipped farms; measured gas remains approximately 0.82M in both cases. Eight full 24-item farms require approximately 14.5M for measurement and 3.1M for credit; small 1–4 farm batches are recommended. The action gas artifact records pack purchase/open, equip/unequip, repair, overclock, expansion, internal token pack and withdrawal. Measurements are local EVM gas deltas/gas-report figures, not Robinhood ETH transaction-cost quotations. Total batch count still grows with farms; audit heap work is logarithmic per selected/inserted farm.

Python checks cover price/tax/combos/controller steps and Merkle/regulator behavior. Foundry lint warnings are retained in `artifacts/build-lint-v3.txt`; they include bounded external-call loops, legitimate time comparisons, explicit casts and guarded callback patterns. A successful build is not a claim of zero lint findings. No Slither/Mythril result or independent test execution by the reviewer is claimed.

## Fresh review and repairs

A second contributor with fresh context conducted read-only adversarial review and follow-up inspection. Reported high findings were unlimited stale-rate scrap draining and unsigned cable-repair interpolation potentially blocking settlement. Medium findings covered buy-cooldown griefing, predictable seed fallback, first-window positive quotas, retroactive snapshot changes and ineffective cable repair. A final spec check also fixed paid XP bypassing the room 2 age gate, and the fresh reviewer verified that repair. All were fixed, regression-tested and cleared by the contributor's final inspection. [The complete findings and residual assumptions](docs/security-review.md) distinguish that review from a formal third-party audit.

## Assumptions, launch inputs and responsibilities

[README](README.md) lists every constructor/deployment input, the immutable graph, external market selection and after-launch responsibilities. [Design](docs/design.md) specifies timing/accounting, prices and weekly lottery transitions. [Regulator](regulator.md) supplies the dry-run rule table and keeper loop. No runtime configuration is fabricated, and no owner setter is added to bypass the ownerless brief.

Open questions for a future launch decision:

1. Does IMD explicitly allow the custom combined 2% hook? If not, choose the standard 1% path, verify its actual project-fee forwarding and provide the exact compatible 30-minute oracle/adapter inputs. Neither path is asserted to have been approved by the launch platform.
2. What actual token, swarm wallet, launch timestamp, snapshot root/block, pool manager, network recipient, pool/tick spacing and standard oracle (if needed) will be used? All are constructor inputs; team is already fixed. Verify no additional pool/protocol fee breaks the disclosed total cap.
3. What real reward-pool endowment, liquidity depth and demand assumptions are authorized? The unfunded baseline misses steady payback and hype longevity; the tuned funded sensitivity below is not an authorization or a guaranteed outcome. Choose resources/policy and rerun before treating those targets as satisfied.
4. Who operates and funds entropy resolution, settlement, buybacks and weekly finalization? Only epoch shifting receives the specified bounty. A missing operator cannot stop claims already credited, but incomplete settlement delays new gameplay.
5. Is the specified future-block randomness risk acceptable for valuable rewards? This implementation is transparent about sequencer influence, expiry choice, lottery rearm and deterministic district/address grinding. A stronger randomness integration would need a separate specified design and verified external inputs.
6. Confirm the published Identity MD snapshot collection/chain and how its launch-block snapshot corresponds to the token launch. The immutable Merkle root is an attestation, not a live cross-chain ownership proof.

These are explicit launch prerequisites and economic limitations of a NO DEPLOY assignment. They do not justify invented addresses, hidden external capital or a claim that all economic acceptance targets have passed.
