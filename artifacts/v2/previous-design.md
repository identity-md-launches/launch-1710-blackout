# Economic and implementation decisions

Source specifications: [v1](https://api.imd.fun/artifacts/dfbd6842bdf572b684b09c4e56d150483da21ccc8dfb14d05fb01409c4441c0b) and [v2](https://api.imd.fun/artifacts/cd34576baf9021fc2bd1d6f12da420599bc2bf0355465b7ab0796eabfe6be64a). The current task's no-owner rules, explicit recipients, six equipment types, room sets, daily step limits and restricted pause supersede older report proposals.

## Immutable fee flows

| ETH stream | Reward buy | Burn buy | Team pull credit | Heartbeat pull credit |
|---|---:|---:|---:|---:|
| Packs | 65% | 10% | 15% | 10% |
| Base 1% swap fee | 30% | 40% | 20% | 10% |
| Excess progressive sell fee | 40% | 35% | 15% | 10% |
| Lobby | 0% | 85% | 10% | 5% |

The network's 0.25% is additional to the project's 1% base fee and is not routed into these columns. Team shares are fixed at at most 20% for every stream. Token-paid packs recycle 70% to the reward pool and lock 30% in BurnVault by default, with **no team token allocation**. ETH rounding dust goes to the heartbeat credit; token rounding dust stays in the pool as a conservative surplus/reservation. There is no sweep function.

Buybacks are permissionless, at most 0.5 ETH per call initially, and at least ten minutes apart across both reward and burn buys. The minimum accepted output is at least 98% of the immutable market's 30-minute TWAP quote. The actual recipient's ERC-20 balance increase is checked, rather than trusting an adapter's return value. A failure reverts all queue changes. Very shallow liquidity can require much smaller batches than the upper limit.

## Equipment and room interpretation

The reports had GPU/Cooling/PSU/Room probabilities 60/20/12/8. The new task adds ASIC, Motherboard and Router and requires every equipment item to mine. Because it supplies no replacement type table, this implementation preserves 60% combined compute and 8% keys, and divides the former cooling category between cooling and the new support types:

| Kind | GPU | ASIC | Power Supply | Cooling | Motherboard | Router | Room Key |
|---|---:|---:|---:|---:|---:|---:|---:|
| Probability | 30% | 30% | 12% | 12% | 4% | 4% | 8% |

Rarity is unchanged: **70% Common, 22% Rare, 7% Epic, 1% Legendary**. Each of the six mining types uses the report's **10 / 28 / 80 / 250** base hash table. Keys are utility assets. Three items per pack; Starter rarity is **92% Rare / 8% Epic**. These tables and mint rights cannot be changed by swarm.

One room has exactly six slots, one per equipment type. One room is free; three more require keys. Standalone equipment needs no key or companion item. At most 40 mining items can be placed across standalone slots and rooms. Old PSU slot extensions, extra-slot purchases, and a separate legacy cooling hash boost are superseded by this new layout; Rare+ Cooling still protects its room against heat waves.

Hash bonuses in a room add, then cap at 40%:

- Six types: +25%.
- GPU + ASIC: +10%.
- Three or more Rare / Epic / Legendary: +5% / +10% / +20%. If two triples qualify, only the highest rarity counts; they do not stack.
- Power Supply + Cooling reduces that room's electricity by 15%.
- Motherboard + Router reduces that room's blackout damage by 25%.

The 40% limit is on **set hashrate bonuses**. Electricity and damage reductions operate on their respective costs, and the report's separate mint-epoch and paid overclock bonuses remain separate. Full Common sets produce +35%; full Rare/Epic/Legendary sets reach +40%. No bonus crosses rooms or applies to standalone equipment.

IDs encode kind, rarity, mint epoch, Starter status and a frozen mint bonus. Low 16 bits are `1 + kind*4 + rarity + 28*epoch`, bit 16 marks Starter, and bits 24 onward hold mint bonus basis points (0–4000). Epoch is 0–4. Mint bonus defaults to +10%/epoch capped at 40%, is snapshotted at commitment, and cannot be improved by delaying resolution. Params changes only affect new mint commitments.

Overclock is +10% per level, at most five levels, charged 15 days of incremental yield times `1.4^level`. It belongs to the occupied slot and is discarded on unplacement, preventing cheap upgrades on a Common item being transferred onto a Legendary item. Merging requires three identical **unplaced paid equipment** IDs, costs two days of the resulting item's yield, preserves edition/mint bonus, and mints through PackSale only. Room keys, Starter items, and Legendary items cannot merge.

## Mining, conservation, and inactivity

- A 12-hour tick snapshots available pool tokens, excluding every already-reserved player reward, tax awaiting redistribution, referral reserve and inspection prize. Default base mining is 3.5%/day, pro-rata in time. Referrals and inspections are additionally reserved before allocation. Total **fresh** allocation is capped at 2.5% of the tick's starting available balance, hence below 5% across two consecutive half-days even at the highest setting. At that cap the extra budgets reduce base mining; they cannot overdraw the pool.
- A surge raises fresh emission 5%, subject to that same cap. Pool inflows after a nonzero rate snapshot affect the next tick. An initially empty pool remains ready to establish its first rate after the first donation/buyback, without crediting the unfunded past.
- A 128-bucket index distinguishes eight districts, cooling protection, motherboard/router protection, Generator protection and audit size. Updates depend on buckets, not the number of players. Audits lock 5% of the large class's gross reward in BurnVault; a large farm has at least 2,000 effective hash.
- A farm has five reward positions: four rooms and standalone equipment. Historical daily indices preserve original accrual days when settlement is delayed. Claiming consumes oldest vintages first. The ring has 16 days, supporting the maximum 14-day tax decay; older balances can safely compact to the floor-tax bucket.
- Default withdrawal tax is `max(5%, 20% - 15%*age/7 days)`. Daily vintages use the **end of the accrual day**, so the tax reduction is conservative by less than one day. Full tax is added to the next tick, without a referral or inspection deduction. Separate mining indices ensure redistribution cannot create repeated referral top-ups.
- The one-level referral is 5% of durability-adjusted **new mining** gross, reserved on top and credited to the inviter's vintage. It is not recursively referred. Nonqualifying and unused referral reserves return to available rewards when the farm settles. A paid-pack purchase itself earns no referral reward.
- `rpsEMA` starts from the first funded interval's daily yield/hash, then uses 70% old / 30% daily observation. Electricity is tariff × EMA × effective power hash × elapsed days. Repair costs 0.025 daily yield per restored point initially. Accrual first covers upkeep/debt and remaining rewards become pending; it never debits a player's wallet automatically. Electricity prepay consumes only the player's authorized payment.
- Durability starts at 100, decays two points per active day, and scales credited mining by average durability over each settled daily segment. A segment crossing zero uses the area under the remaining linear decay. This uses interval-average reward attribution within each day, an approximation when event weights/rates change intraday. Settling before a placement/repair prevents earning with equipment retroactively.
- Equipment withdrawal stops further durability decay. A fully decayed farm can be permissionlessly refreshed to zero effective hash and revived through a wallet-funded repair. Operators should settle and refresh abandoned farms: cached inactive hash otherwise temporarily dilutes active miners until refreshed, with the unused allocation returned to the pool on settlement.
- The 2% soft cap halves excess hash. At refresh it solves `effective = min(raw, c) + (raw-c)/2` with `c = share*(otherEffective + effective)`. This is a snapshot against other farms at that time; changing other farms does not iterate through all existing farms.
- Room-set settings and soft-cap settings are **applied to recorded mining positions on their next refresh**, while `roomStats` previews current values. Anyone can refresh; keepers should do so after related Params changes. Historical accrual always uses recorded positions. Tariff, event effects and mint rules have their separate checkpoint/snapshot boundaries. This avoids retroactively repricing past rewards but requires refresh operations; stale positions are a documented limitation.

ERC-20 balance conservation is tested across pool, sink, players and Generator. Index division may leave tiny conservative reserved dust; it is not claimable twice or administratively recoverable. Standard non-rebasing, non-transfer-tax IMD token semantics are required. Incoming donations and Generator locks reject short receipts.

## Generator assumption

Neither report defines Generator economics. This implementation chooses a **voluntary seven-day pledge** of at least one current raw-farm day of electricity (before the soft cap), held in its own principal vault. While the pledge covers the farm's current requirement at refresh, it reduces blackout damage by **25%**. It stacks multiplicatively with the room's 25% motherboard/router reduction: a 50% blackout loss becomes 28.125% (subject to integer rounding). It provides no hashrate bonus or yield on principal. A growing farm may outgrow its protection; there is no unilateral lock extension or confiscation. The simulation defaults adoption to zero because no participation assumption was supplied.

## Grid events, randomness and inspections

The swarm chooses an event type, not a player, district, seed or reward recipient. Events are submitted in the first hour of the current half-day and commit to native block `N+2`. Lobby weights and blackout eligibility are frozen at submission. Anyone resolves after the target and before the first hour ends. Late/expired events become Calm; anyone can apply an overdue Calm tick. Effects start at resolution and never rewrite elapsed accrual.

Rolling 20-tick event caps are Surge ≤8, Heatwave ≤6, Blackout ≤5, Audit ≤4. Surge ≥4 and Heatwave ≥2 guide admissible submissions after the initial window; after an outage, underrepresented positive events are allowed to restore those minima, preventing an all-Calm history from permanently disabling the operator. Blackout cooldown defaults to 72 hours (six ticks), can only increase, and is checked against selected district history.

Lobbying applies only to the caller's hash-derived district. Its score decays with a three-day half-life using fixed-point exponentiation. Weight is `max(0.40, 1/(1 + 0.5*L_d/max(mean(L),0.05 ETH)))`. Lobbying lowers odds, never guarantees immunity, and lobbying after event submission cannot target the pending draw. Token lobbying uses the same TWAP and is burned. The in-game 5% bonus increases its nominal lobby credit.

Packs and Starter claims also target `N+2`. Resolving is permissionless and requires the target to be in the past. On expiry, a paid pack resolves to three Common GPUs; a Starter pack to three Rare Starter GPUs. These deterministic fallback items prevent a new random reroll. They are **not a proof of unbiased randomness** and may have different subjective utility from a random pack. A refusing ERC-1155 receiver can prevent delivery to itself; it cannot redirect someone else's items or freeze the sale globally.

On chain IDs 4663 / 46630, `ChainClock` uses ArbSys `arbBlockNumber()` and `arbBlockHash()` at precompile 0x64; `block.number` is an ancestor estimate on these chains. Other supported EVM test/L1 environments use native `block.number`/`blockhash`. [Arbitrum explicitly warns that child-chain hashes are not secure randomness](https://docs.arbitrum.io/arbitrum-essentials/arbitrum-vs-ethereum/solidity-support). This follows the supplied report's sequencer-trust design, **not VRF**. The sequencer can bias/censor outcomes. No VRF service address, subscription, key, or operator has been invented.

For each seven-day week, inspection eligibility uses the minimum-hash setting snapshotted for that week. Score is its burned token spend / gross credited accrual. Candidates must be fully settled; submissions are permissionless during `[weekEnd, weekEnd+24h)`. The highest score wins, with numeric address order as a deterministic tie-break. Finalization is permissionless after that window and credits the already-reserved prize to the winner's reward balance; normal tax applies if withdrawn. No candidate returns the prize to available pool tokens. The swarm never selects or pays an arbitrary winner.

## Bounded Params

Every change is limited to **10% relative to the previous value**, per key per 24 hours; elapsed time does not permit a larger single step. No-op changes revert. Parameters use integers, so sufficiently small basis-point values cannot reach zero through a sub-unit step. A first change is allowed immediately on ordinary post-genesis chains. No shares, rarity probabilities, minters, recipients, beta limits, pause maximum, or sell-fee ceiling are Params.

| Key | Initial | Hard range / extra rule |
|---|---:|---|
| EmissionBps | 350 | 250–500; total fresh funding cap also applies |
| TariffBps | 1500 | 1000–3000 |
| PriceStepBps | 1500 | 0–2000 |
| PriceFloor | 0.006 ETH | 0.004–0.010 ETH |
| PremiumBps | 5000 | 0–10000 |
| DemandTarget | 1000 | 500–3000 packs |
| RepairBps | 250 | 150–400 per point |
| IngameBonusBps | 500 | 0–1000 |
| TokenRecycleBps | 7000 | 5000–9000 |
| TaxDay0Bps | 2000 | 1000–2500 |
| TaxFloorBps | 500 | 0–500, only decrease |
| TaxDecaySeconds | 7 days | 3–14 days |
| LobbyKBps | 5000 | 2500–10000 |
| LobbyMinWeight | 4000 | 4000–7000, only increase |
| BlackoutCooldownSeconds | 3 days | 3–12 days, only increase |
| HeatPenaltyBps | 2000 | 1000–3000 |
| InspectionBps | 100 | 0–200 of new base mining |
| InspectionMinHash | 100 hash | 100–2000 hash (1e18 fixed-point units) |
| EpochHashBps | 1000 | 0–1500 per epoch, new commitments only |
| SoftCapBps | 200 | 100–500 |
| FullSetBps / ComputePairBps | 2500 / 1000 | 0–2500 / 0–1000 |
| ElectricityPairBps / ShieldPairBps | 1500 / 2500 | 0–1500 / 0–2500 |
| RareSetBps / EpicSetBps / LegendarySetBps | 500 / 1000 / 2000 | 0 to their launch value |
| SetCapBps | 4000 | 0–4000 |
| BuyBatch | 0.5 ETH | 0.1–1 ETH |
| SlippageBps | 200 | 100–300 |
| SellHourBps / SellDayBps / SellDeviationBps | 500 / 400 / 5000 | 200–600 / 0–500 / 2000–5000 |

Pack base price is 0.010 ETH, steps down by 15% per seven-day epoch to the floor, and applies a demand premium initially capped at +50%. Demand uses conservative 25 hourly buckets covering the previous 24 hours plus its partial oldest hour. Wallet pack limits use exact timestamps for the last 20 purchases: 3 before hour 12, 6 before hour 24, 10 before hour 48, then 20 per rolling day. Global beta limits use launch-relative hourly demand bands but absolute hourly accounting buckets: 75 before hour 6, 150 before hour 24, 300 before hour 48, then unlimited. Token packs additionally have an exact rolling 24-hour per-wallet limit of one. These limits have no setter; Sybil wallets can bypass wallet-based limits.

## v4 sell fee and TWAP details

The fee recipient portion is `min(1475, 100 + aHour*s1h + aDay*s24h + k*min(deviation,1000))` basis points, with fraction products divided by 10,000. Add the fixed 25 bps network fee: total ≤1500 bps. Volume windows include the current sell, with twelve five-minute and twenty-four one-hour buckets, dampers 0.5 ETH and 2 ETH. Deviations use the **post-swap ETH/token price** against the arithmetic 30-minute mean ETH/token price. The stored rate rises immediately and falls no faster than 100 bps per ten minutes. Fractional rate decay is retained to prevent frequent dust swaps from resetting the decay timer.

Every external swap updates cumulative prices. The oracle records exact cumulative values at minute boundaries; the quote covers the preceding 30 complete minutes. A flash move within a block contributes no elapsed time. A quiet market extrapolates its unchanged last price, rather than falsely treating it as stale. System buys through the immutable fee router are explicitly observed but excluded from the buy-imbalance counters. They still pay the 1.25% base fee.

The hook permits only its immutable ETH/token pool and only authenticated PoolManager callbacks, uses return deltas rather than LP-fee overrides, and rejects exact-output requests. The combined hook integration is optional until the launch operator confirms compatibility; the reports left that compatibility question open. No claim is made that an already deployed IMD hook can be modified.
