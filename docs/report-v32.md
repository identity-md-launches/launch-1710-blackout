# BLACKOUT v3.2 — lazy accounting and economic rerun

Implemented as a source update to v3.1. **No deployment, broadcast, token replacement or mint occurred.** The selected configuration remains **20% token endowment, poolBps 7000, 42-day drip**, with heartbeat restored to **200 bps and a fixed 1 ETH cap**. The custom hook, one-time team binding, GameRegistry, 8+4 application launches and team address `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007` are retained.

**The 2% heartbeat covers every modeled baseline bounty.** At 20% endowment, steady keeper cost falls to **0.20185 ETH over 35 days**, against **1.19941 ETH retained heartbeat income**. Player economics still miss fast-payback goals: the steady week-1 cohort repays in **28.5 days**, while hype and weak do not repay half the cohort within 35 days. Lazy accounting moves work to owners and preserves inactive allocations; it does not eliminate the work or its economic cost.

## Implemented accounting

`advanceEpoch` closes and snapshots global state without visiting farms. Epochs preserve the reward-per-hash rate and cumulative index, allocation hash, emission, tariff, audit threshold, combo parameters and resolved event kind/district/severity/seed. Its work does not grow with farm count or inactivity. Events are replayed from the saved seed and permanent player-address farm identity; no keeper chooses victims. Durability, theft, destruction and combo protections apply during replay.

`settle(player,1..8)` is permissionless and unpaid. Claims settle up to eight closed epochs and can withdraw credited funds even while more history remains. Core mutations settle up to eight and require completion; a stale action reverts atomically with `CatchUpRequired`, so owners persist longer catch-up through explicit chunks first. Purchase, install, repair, overclock and removal retain next-epoch snapshots. Audit now charges exactly 10% of that epoch's gross mining when pre-event raw hash is strictly above the epoch's frozen `AuditHashThreshold` (default 100000; bounded 10000–10000000).

The O(1) global denominator is a committed full-health hash envelope. Owner configuration changes update it for the next epoch. Settlement alone cannot rewrite that commitment; damage reduces realized output and releases unused attribution. **Inactive farms retain committed allocation until a Core configuration interaction updates it; exhausted installed equipment must be unplaced to remove its full-health commitment. Outstanding reward reservations resolve when the farm settles, either through its owner or a volunteer. Plain claims and voluntary settlement do not update allocation weights.** This changes the v3.1 eager denominator and is included in the simulation. Rewards never expire and nobody can confiscate an absent farm's reserve.

Mining reserves 117% of the base emission: at most 110% Green gross, 5% of gross referral, and a 1% seasonal prize. Per-farm attribution uses the same integer reward-rate rounding as gross; this avoids a one-wei shortfall that could otherwise permanently block catch-up. Unused settled attribution is recycled or funds the bounded existing scrap allowance. Final dust remains reserved until all positive allocation weight settles. Claims age from the original epoch end; sparse old vintages are consumed before younger, higher-tax credits.

Season activity and yield accrue during settlement. Only a farm that finishes the entire week before **week end + seven days** enters its score and tickets. This prevents partially settled yield from inflating spend/yield scores. Late settlement still pays mining. Preparation is constant and unpaid; finalization examines eight districts and at most three bounded ticket-tree paths, then pays one small nonempty-season bounty. The deadline makes completion independent of absent farms.

The [accounting specification](docs/lazy-accounting-v32.md) gives exact rounding and client semantics. Only new paid PackSale purchases can be paused by the swarm, for at most 72 hours with automatic expiry and the retained 72-hour live interval. Claims, withdrawals, global advancement and keeper calls have no pause path. No upgrade, owner recovery or replacement authority was added; the hook's sole privileged action remains the team's one-time FeeRouter binding.

## Simulation definition

Six baseline cases cover steady/hype/weak demand at 20% and 25% endowment, all with a 42-day drip. Sixty-six additional runs test eleven behavioral/parameter changes across the same allocations and scenarios. Every run lasts 35 days / 140 six-hour epochs, uses deterministic seed 20261011, and starts with **zero actual AMM ETH and zero reward-buy capital**. Existing token supply is one billion: 10% contributors, 70%/65% single-sided pool, 20%/25% endowment. Virtual AMM reserves normalize the opening capitalization to 11.111111111 ETH; they cannot pay an ETH sale. Unsold tokens never count as cash recovery.

Week-1 payback is the median elapsed time from joining to cash recovery across **all** paid farms joining during the first seven days, including quit/unpaid farms as censored observations. Cash is net of claim tax, market fees and price impact. Costs include paid packs, lobby spending and the modeled gas for owner settlement. A missing median means fewer than half repaid within the run. It does not mean zero farms earned cash. Stall is the first modeled day after day 3 with active farms below 25% of their peak or the active median forward payback estimate above 60 days. Drawdown is the largest peak-to-subsequent-trough price fall, including opening price, not merely opening-to-ending change.

The model retains v3 demand/churn, 900 separate NFT starter entitlements, 900 contributor sellers, two-day contributor claim-lock assumption, 35%/50%/65% contributor sale intent in steady/hype/weak, and 40% referral adoption. Active farms interact/maintain each epoch; quit farms leave their committed weight and unpaid envelopes behind. Prizes are delayed through the settlement grace period. A per-farm hash chooses events independently of settlement order. The simulator uses floating-point economics and a constant-product virtual-reserve approximation, not an EVM or concentrated-liquidity replay. Transaction ordering, exact integer dust, actual installed-loadout choice, maintenance spending and human attendance remain approximations.

Base gas is the retained v3.1 assumption of 0.02 gwei; stress uses the 0.05 gwei reimbursement ceiling. Owner settlement is charged at `(850000 + 70000 × equipped items)` gas per active farm-epoch, a conservative proxy around measured typical/full-farm costs. It affects payback and churn. Other player transaction gas, L1 posting, failed keeper races and credit withdrawals are not included. These are scenario assumptions, not refreshed network quotes or profitability forecasts.

## Six-case results

| Endowment / poolBps | Scenario | Week-1 median payback | Repaid cohort | Stall day | Price drawdown | Team gross / after policy runs, ETH |
|---|---|---:|---:|---:|---:|---:|
| 20% / 7000 | steady | 28.5d | 53.2% | >35 | 15.8% | 13.22039 / 12.97882 |
| 20% / 7000 | hype | not reached | 20.8% | 17.25 | 91.7% | 18.47975 / 18.23818 |
| 20% / 7000 | weak | not reached | 15.2% | 29.25 | 28.2% | 2.45285 / 2.21128 |
| 25% / 6500 | steady | 25.25d | 55.6% | >35 | 17.8% | 13.37943 / 13.13786 |
| 25% / 6500 | hype | not reached | 20.3% | 17.5 | 92.5% | 18.71289 / 18.47132 |
| 25% / 6500 | weak | not reached | 13.8% | 31.0 | 31.5% | 2.52835 / 2.28678 |

[Full baseline table](artifacts/v32/verified-baseline/comparison.md) and [all cohorts/epoch data](artifacts/v32/verified-baseline/simulation.json) preserve the complete results. At 25% endowment, steady improves by 3.25 days but price drawdown deepens; the delivered choice remains the requested 20%. Neither allocation fixes hype or weak payback.

Gross team ETH includes the retained 13% pack/lobby/surcharge share plus half of project base fees. The external policy schedule remains separate: 140 runs × 0.5 IMD = 70 IMD, illustrated by the prior job's 0.003451 ETH/IMD valuation as **0.24157 ETH**, before acquisition/payment/bridge costs. Team net in the table subtracts that illustrative expense only when the team pays. Heartbeat ETH cannot purchase these runs or be withdrawn administratively.

| Endowment | Scenario | Owner settlement gas, ETH | Unsettled envelopes + dust at day 35, million tokens | Maximum weekly event loss |
|---|---|---:|---:|---:|
| 20% | steady | 6.2016 | 176.37 | 2.74% |
| 20% | hype | 7.4363 | 228.28 | 3.68% |
| 20% | weak | 2.8896 | 136.72 | 4.36% |
| 25% | steady | 6.3033 | 170.09 | 4.29% |
| 25% | hype | 7.4212 | 235.68 | 4.58% |
| 25% | weak | 2.9579 | 140.61 | 4.58% |

These gas totals aggregate all active owners over the run; they are paid to the chain, not funded by heartbeat. Outstanding lazy reservations are liabilities, not losses or available reward capital. Weekly event loss compares gross production with the same committed denominator and an undamaged shadow; it excludes inactive-allocation dilution.

## Heartbeat funding

Only four work families remain: advance, entropy capture, successful buyback and nonempty season finalization. No measurement, credit, audit-selection, settlement or score bounty remains callable. The heartbeat holds at most 1 ETH; all excess routes to reward buying.

| Endowment | Scenario | Bounties due / paid, ETH | Retained HB income, ETH | Lowest post-revenue cumulative headroom, ETH | Ending HB balance, ETH |
|---|---|---:|---:|---:|---:|
| 20% | steady | 0.20185 / 0.20185 | 1.19941 | 0.02501 | 0.99755 |
| 20% | hype | 0.19051 / 0.19051 | 1.18844 | 0.09782 | 0.99793 |
| 20% | weak | 0.16342 / 0.16342 | 0.31741 | 0.00601 | 0.15399 |
| 25% | steady | 0.20216 / 0.20216 | 1.19987 | 0.02501 | 0.99771 |
| 25% | hype | 0.19113 / 0.19113 | 1.18909 | 0.09782 | 0.99796 |
| 25% | weak | 0.16425 / 0.16425 | 0.32680 | 0.00601 | 0.16255 |

The table counts heartbeat receipts **after** the 1 ETH cap; rejected excess already went to reward buys. Every baseline call is fully paid, including the weak paths. The 2% launch share is also the existing Params minimum, so no increase is needed for these scenarios. At 20%/steady, advance accounts for 0.14000 ETH, buybacks 0.01066, plan entropy 0.001015, paid/starter entropy 0.050105 and season finalize 0.000073. The measured keeper problem has fallen from the prior model's roughly 9 ETH to about 0.202 ETH; the comparison does not claim unchanged farm economics.

The twelve operating stresses (no swarm intervention and gas at the 0.05 gwei ceiling, both endowments and all three scenarios) also pay every bounty. Their minimum post-revenue prefix headroom is **0.005813 ETH**. At the ceiling, 20% steady / hype / weak bounty costs are **0.26221 / 0.24183 / 0.18223 ETH**, versus retained heartbeat receipts **1.25834 / 1.23786 / 0.31081 ETH**. Higher owner gas still prevents steady median payback within the horizon: funding keepers does not fund players.

All **72 completed runs**, including the proposed economic levers, have zero bounty shortfall at 2% / 1 ETH. The lowest headroom over that entire set is **0.003603 ETH** in a hypothetical price-cut weak case. [Sensitivity table](artifacts/v32/verified-sensitivities/comparison.md), [complete results](artifacts/v32/verified-sensitivities/simulation.json) and [machine checks](artifacts/v32/simulation-checks.json) are included. Every artifact matches the final model source hash. Maximum token conservation error was **0.00014210 token per billion-token system**. Reproduce and validate using the commands in README.md.

The advance pays at most 0.001 ETH, bounded by balance. Other work pays the minimum of the hard cap, measured gas plus an 80000-gas allowance at the capped gas price with 25% margin, and heartbeat balance. Default caps are 0.000010 ETH per entropy unit, 0.000150 ETH per 0.5 ETH bought (proportional), and 0.000040 ETH per nonempty season. Empty/replayed work pays nothing; partial funding creates no debt. The simulation includes paid/starter/plan entropy and four season finalizations in the 35-day window. The no-plan stress conservatively retains the plan-entropy budget even when plan intervention is absent.

The funding conclusion begins after fee revenue arrives. The first epoch-start transaction can earn zero with an empty heartbeat; it needs an operator's ordinary gas float. No percentage of zero revenue can pay that first bounty, and no fixed share guarantees participation indefinitely after sales stop or at arbitrary gas prices. These operational limits are unchanged by lazy accounting.

## Three strongest tested remaining payback levers, without ETH capital

Ranked by isolated improvement to the **20% / 42-day steady baseline of 28.5 days** in this single-seed study. Endowment and drip rows are alternative launch choices; the committed candidate keeps 20% and 42 days. The ranking is not a statistically established optimum.

| Rank and lever | Steady payback | Improvement | Principal tradeoff |
|---|---:|---:|---|
| 1. Route 5% rather than 13% of pack/lobby/surcharge revenue to the team; redirect the eight percentage points to rewards | 20.875d | **7.625d / 26.8%** | Gross steady team proceeds fall **13.22039 → 6.73081 ETH**. Project base-fee sharing stays unchanged. Hype still has no median payback, stalls at 18.25d and draws down 92.4%. Requires a future source release because this split is fixed. |
| 2. Release the same 200M tokens over 14 days instead of 42 | 24.25d | **4.25d / 14.9%** | Steady drawdown rises **15.8% → 21.6%**; weak stalls **29.25 → 27.5d**. Hype still lacks median payback. Changes the release schedule, not the amount of ETH capital or token supply. |
| 3. Allocate 25% / 250M existing tokens to endowment, reducing poolBps from 7000 to 6500, while retaining 42 days | 25.25d | **3.25d / 11.4%** | Steady drawdown rises **15.8% → 17.8%**. Hype stalls at 17.5d with 92.5% drawdown; weak repaid fraction falls **15.2% → 13.8%**. Requires a different initial token allocation, not newly minted tokens or ETH. |

If 20% and 42 days are held fixed for every alternative, the strongest tested parameter-policy alternative is starting at **6% daily emission and 10% tariff**: steady **28.5 → 25.5d**, a **3-day / 10.5%** improvement. It increases the repaid steady fraction **53.2% → 56.8%**, but hype stalls earlier (**17.25 → 15.5d**) and weak repayment falls to **12.6%**. Emission alone reaches 25.75d; tariff alone reaches 28.25d. These comparisons make the revenue/price/retention tradeoff visible rather than assuming faster token emission always improves cash payback.

These are isolated counterfactuals, not additive improvements or changes silently applied to the delivered candidate. The committed release keeps the requested 20% endowment / 42-day drip and existing team economics. Higher emissions and lower tariffs must follow the existing maximum 10% per-key movement every 24 hours; runs initialized at different values represent a pre-launch setup or a proposed new default, not an immediate live jump. Endowment/drip choices freeze on funding/activation, and fixed routing changes need a separately reviewed source release before deployment.

Cheaper entry is not a successful lever in this model: reducing all pack prices by 20% leaves only **47.3%** of the 20%-endowment steady cohort repaid, versus 53.2%, and no cohort median within 35 days. A one-third price cut leaves **45.1%** repaid and would also violate the current minimum PriceStart (its 0.006667 ETH start is below the 0.008 ETH bound), so it is comparison-only. Cashing out 80% rather than 65% reaches **28.875d**, slightly slower than baseline. Holding demand pace leaves 38.1% repaid; removing swarm intervention leaves 26.2%. None of the tested levers reaches median hype or weak payback within the 35-day run. The full table includes both endowments, not only the favorable rows.

## Validation and independent review

- `forge build`: passed with the unchanged pinned Solidity 0.8.26 / viaIR / Cancun configuration.
- `forge test -vv`: **132 passed, 0 failed, 1 skipped**, across 26 suites. The skip is the existing optional network smoke fork.
- `forge fmt --check`, all ten creation-code pins and `git diff --check`: passed.
- Python: **20 unit tests** and **five model self-checks** passed. Simulation conservation and source-hash checks are linked in the heartbeat section.
- Fuzz tests: 256 cases; invariant campaigns: 128 runs × 64 calls.
- Largest application runtime: **FarmCore 24207 bytes**, below EIP-170's 24576-byte limit; FarmRewards 14960 bytes, hook 9954 bytes. [All sizes](artifacts/v32/contract-sizes.json).

[Build log](artifacts/v32/forge-build.log), [full suite log](artifacts/v32/forge-test.log), [validation record](artifacts/v32/validation.json) and [Python results](artifacts/v32/python-tests.log) are included. Existing compiler lint warnings are not an audit conclusion. No protected build configuration, dependency, repository metadata, CI, environment or node_modules path was changed. No new dependency or network access is needed to reproduce the ordinary checks.

The independent eager-reference test generates two randomized six-item farms, rarities, durability and overclocks and replays every event kind with random seeds, districts and severity. Its memory model does not call FarmEngine or roomStats. One farm settles each epoch; the other settles in chunks. It compares exact credits and durability under identical immutable global snapshots and verifies replay cannot credit twice. This does not claim that early and delayed recycling produce identical future global budgets.

Success/failure cases also cover long idle catch-up, stale mutation rollback, claims while PackSale is paused, frozen audit thresholds and exact 10% tax at half severity, fully exhausted redistribution, sparse aging across ring wrap, one-wei Green emissions, season deadlines/full-week eligibility, replay/authority checks, reserve backing, token and ETH conservation, exact registry enrollment, hook binding/escrow and real local v4 settlement. Invariants randomize advancement, settlement, purchases, claims and equipment actions. The retained local native-block clock tests run offline; the optional network smoke fork is skipped.

The following are measured local execution gas, not total transaction/L1 data costs. Common-action rows have no stale backlog; auto-catch-up adds its bounded cost. The full idle test advances 40 epochs without visiting the farm, processes eight in one call and then finishes the remaining chunks. Callers can select a smaller limit to fit chain transaction limits.

| Action | Gas |
|---|---:|
| Advance, zero farms | 985099 |
| Advance, 1000 farms | 975024 |
| Buy ETH pack / open one pack | 719243 / 374384 |
| Equip / unequip | 433011 / 308125 |
| Wallet repair / overclock | 389611 / 338663 |
| Expand / token pack using internal rewards | 287492 / 543476 |
| Claim credited rewards | 197423 |
| Three-item farm, one closed epoch | 941756 |
| Full 24-item farm, eight epochs after 40 idle | 11339205 |
| Paid / starter / plan entropy | 134284 / 136851 / 155141 |
| Real local v4 0.2 ETH buyback | 1837743 |
| Season finalize, three winners and prize | 586797 |

At 0.02 gwei the measured dense eight-epoch chunk costs approximately 0.000227 ETH in execution gas. Typical three-item one-epoch settlement costs approximately 0.0000188 ETH. Bounty margin tests include 21000 transaction gas and pass at the modeled base gas price; the separate 80000-gas reimbursement allowance is not a promise to cover every possible L1 data/race/withdrawal cost.

A second contributor started with fresh context and performed read-only adversarial review. All identified high/medium findings are resolved: sparse reward aging, exhausted-farm redistribution and tiny-allocation settlement liveness. Simulation discrepancies in destroyed-item combos, correlated lottery rarity/kind and lazy reserve/scrap timing were also corrected. The reviewer independently ran the targeted Solidity tests, the one-wei regression, Python checks and 505000 small integer allocation partitions. [Review record](docs/review-v32.md) distinguishes these checks from the primary contributor's full run. No Slither/Mythril or live deployment audit is claimed.

## Deployment and responsibilities

Use [launch-v31.md](launch-v31.md), which points to the updated detailed [8+4 launch procedure](docs/launch-v31.md). No launch manifest or guessed production address was created. Actual token/hook/factory inputs, NFT snapshot/root and swarm role remain inputs from the accepted future launch. The existing project's token is not redeployed by this assignment. The source update cannot upgrade an immutable live deployment.

The team verifies the graph, performs its one-time hook bind and publicly transfers the complete 200-million-token endowment. The operator verifies the 42-day activation receipt and starts the first epoch. Permissionless bots advance, preserve entropy, buy within TWAP/slippage limits and finalize seasons; owners or sponsors settle farm history and claim rewards. An external payer keeps policy runs funded. The frontend must expose catch-up progress and season deadlines. Future-block randomness retains v3's sequencer influence and timeout assumptions; it is not a VRF.

The remaining economic constraint is demand and collectible yield, including inactive allocation dilution and the user cost of settlement. Restoring the small keeper budget does not itself establish fast payback, sustained hype liquidity or profitable participation.
