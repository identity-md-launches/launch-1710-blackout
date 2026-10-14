# Simulation provenance and limits

The supplied workspace contained no earlier implementation. The linked research job trees contained report Markdown, but not either Python program mentioned in those reports. `sim/blackout_sim_v2.py` is therefore a **new reconstruction from report v2 and its carried v1 assumptions**, extended for the requested six equipment types and room sets. It is not the recovered original model and does not claim to reproduce its tables.

The retrieved report bytes matched the artifact identifiers:

| Source | SHA-256 |
|---|---|
| [v1, job b9e37680-814c-4f17-b4bc-68272b77304d](https://api.imd.fun/artifacts/dfbd6842bdf572b684b09c4e56d150483da21ccc8dfb14d05fb01409c4441c0b) | `dfbd6842bdf572b684b09c4e56d150483da21ccc8dfb14d05fb01409c4441c0b` |
| [v2, job 10d225a6-92cb-4cde-9d4b-ec076b078f7d](https://api.imd.fun/artifacts/cd34576baf9021fc2bd1d6f12da420599bc2bf0355465b7ab0796eabfe6be64a) | `cd34576baf9021fc2bd1d6f12da420599bc2bf0355465b7ab0796eabfe6be64a` |

## Inputs taken from the reports

| Input | Model value |
|---|---|
| Supply and opening pool | 1 billion tokens; 900 million in a constant-product pool, 100 million swarm allocation |
| Virtual reserve / horizon | 10 ETH, 35 days; 3 and 5 ETH sensitivities |
| Swarm selling | Half its allocation sold evenly over days 1–14; no-sale sensitivity |
| Newcomers | Steady 150/day for days 1–3, then 80; hype `600*exp(-(day-1)/5)+25`; weak `40*exp(-(day-1)/15)+5` |
| Initial pack demand | Three per newcomer, scaled by `(0.01/price)^0.7`; 3% of active earlier farmers buy one extra pack/day |
| Demand response | `min(1,sqrt(21/perceivedPayback))` |
| Pack price | 0.01 ETH, weekly 15% decline to 0.006, demand premium capped at 50% |
| Rarity / hash | Common/Rare/Epic/Legendary 70/22/7/1%; base hash 10/28/80/250 |
| Pool emission | 3.5%/day, two half-day ticks, +5% for Surge |
| Churn | 1.5%–7.5%/day, depending on yield relative to 2% of paid cost/day |
| Sell intent / redirection | 65%; redirect `min(60%,1.5*averageWithdrawalTax)` of intended sells; defer by excess sell-fee fraction |
| Claim timing | 40%/30%/30% at ages 0/3/7 days; tax 20% falling to 5% over seven days |
| In-game spending | 5% purchasing bonus; 25% of redirected spending allocated to token packs, 70% recycled and 30% burned |
| Referrals | 40% participation assumption, 5% on top of fresh mining; no recursive referral on redistribution |
| Starter | 35% of 1,999 entitlements rounds to 700 packs; half in first three days of window; Rare/Epic 92/8%, half hash until paid activation |
| Lobby / external trading | 0.00004 ETH/active farm/day; round-trip trader volume 0.5 times pack ETH |
| Fees | The four immutable split rows in `design.md`; additional 0.25% network fee on swaps |
| Dynamic-fee approximation | Hour imbalance is 1.25 times daily imbalance; deviation is half the daily price drop; total including network at most 15% |
| Tariff controller | Initially 15%; reduce 10% when projected new-pack payback exceeds 35 days; increase 10% below 25 days while price falls; range 10%–30% |
| Inspection | 1% of fresh weekly mining, highest burn/gross among eligible farms; half the gross prize designated for immediate sale through normal withdrawal tax |

## Reconstruction choices

- Items are discrete, with the new type probabilities and set rules documented in `design.md`. A seeded greedy policy puts the highest-hash equipment into rooms one per type, then standalone slots, capped at 40 equipment. It does not solve optimal placement. Generator adoption defaults to zero because neither report specifies it; `Settings.generator_fraction` supports an explicit sensitivity.
- Whole token packs cost the current pack ETH price converted at model spot, discounted by 1.05. Unused budgets accumulate as held tokens; at most one pack per farmer/day is bought. This is deliberately not fractional NFT issuance, and produces fewer token packs than v2's aggregate model.
- Maintenance is a daily gross-yield proxy: tariff times the room power/hash ratio, 5% repair and 2% merge participation; 15% of the remaining yield initially funds upgrades. Upgrade progress is averaged continuously, with escalating costs and five-level cap. Actual contracts use integer levels, durability, electricity indices, daily vintages and exact token amounts. The simulation is an economic scenario model, not an EVM-equivalent accounting implementation.
- The 2% hash soft cap is recalculated across current model farms each tick. Contracts use permissionless refresh snapshots to keep work bounded. The model therefore assumes active maintenance and refresh, not indefinite stale on-chain farms.
- Swarm event choices are sampled from v1's 30/25/20/15/10% Surge/Heat/Blackout/Audit/Calm mix, subject to contract rolling caps/minimum-recovery rules and six-tick district cooldown. Lobby weights affect Blackout selection. Resolution latency is omitted. Hash and emission changes, electricity discounts, heat protection and blackout shields are included.
- Referral income is attributed to the referred population in aggregate; there is no individual inviter graph. Weekly inspection selection includes that week's last daily activity. Intraday claim ages, proof-resolution latency, the candidate window and rounding are collapsed into daily actions.
- System buys execute as daily aggregates. As in report v2's stated simulation, they enter the aggregate buy-imbalance estimate; **the production hook excludes its own system buys**. The on-chain rolling windows, output checks, 31-minute TWAP warm-up, batch spacing, current-sell inclusion and slow fee decay are tested separately with Solidity, including real v4 settlement.
- Beta hourly caps are implemented/tested in the contracts. They are not an extra restriction on daily model totals: v2 states that the initial queue clears within the first day. The model does not reproduce the missing original hourly queue/stress-test program.
- Payback is computed for still-active paid farmers, with later purchases included in their cost. Held and queued tokens are marked at 95% of model spot; actual sales use execution proceeds. The last seven yield observations project at a fitted daily multiplier bounded to 0.80–1.00, with a 120-day cutoff. Finite averages exclude non-paying outcomes, whose proportions are shown separately. Quitters are also reported separately.
- The reconstructed stall statistic starts at day three and uses the joining cohort's median projected payback above 60 days, or active farms below 25% of their prior peak. Its cohort/projection implementation cannot be asserted identical to the unavailable original source.

The program checks total tokens across AMM, swarm, reward pool, sink, player holdings, delayed claims and redistribution every day. Fresh emissions are transfers out of pool holdings, not token minting. Floating-point error is reported in whole tokens; the contract tests use exact integer conservation. Behavioral assumptions, virtual liquidity and marked holdings do not establish redeemable ETH or a promised return.

Run `python3 sim/blackout_sim_v2.py --check` for model checks and `python3 sim/blackout_sim_v2.py > artifacts/simulation.md` to regenerate the seeded results.
