# v3.2 accounting specification

This supersedes the epoch settlement and season sections of the v3/v3.1 design. Contracts remain immutable. No token or live application is migrated by this source release.

## Epoch and allocation semantics

`advanceEpoch()` performs constant work with respect to the farm population and its inactivity. The fixed loops snapshot twelve combo parameters, eight district weights and the existing bounded event history. It never reads `playerAt` or calls `FarmCore.process`. At closure it stores the event kind, severity, district and seed, the mining budget and the reward-per-hash increment. At start it snapshots total allocation hash, tariff, emission rate, sales target, combo parameters and the audit threshold. One successful call closes at most one six-hour epoch and starts the next at its actual call time. No emissions accrue in an advancement gap.

A farm's **allocation hash** is its installed loadout at full durability, paid/starter status and overclocks, with the maximum legally permitted combo bonuses and no theft. Using protocol maxima makes this a safe envelope even if bounded combo Params change while a farm is offline. At initial default combo Params, it equals the familiar undamaged farm raw hash. Farm configuration interactions update a running `nextTotalHash`; their weights become effective in the next epoch. Both old and next farm weights are retained until the old history has settled.

Settlement alone never changes allocation weights. Destruction, wear and theft instead reduce realized production and release the unused reward reservation. This is a necessary change from the eager v3.1 denominator, which removed dead hash by visiting every farm. Offline allocation remains in the denominator until an owner interaction updates it; otherwise an opportunistic settler could change other farms' historical shares. A player can unplace dead equipment or interact after catching up to remove its allocation for future epochs. Idle farms' still-unsettled envelopes remain reserved, without an expiry or an owner confiscation path. Simulations include this dilution and lockup.

All ordinary loadout, repair, overclock and paid-status snapshots retain next-epoch activation. The current epoch's snapshot survives unplacement and repairs. Cable repair retains the v3 remaining-fraction rule. No changes can rewrite a closed epoch: Core first settles its owner's closed history and then rolls the active snapshot. `CatchUpRequired` means more than eight epochs remain; that attempted action reverts atomically, so use explicit settlement transactions to persist progress.

## Reservation and exact rounding

For closed epoch `e`, let `H` be its snapshotted allocation total, `M = available * emissionBps / 40000`, and `Q = 10^27`. If `H == 0`, there is no mining reservation and that epoch's redistribution is queued again. Otherwise:

- `rewardPerHash[e] = floor(M * Q / H)`; `accRewardPerHash[e]` adds this to the prior cumulative index.
- Reserve `floor(1.17 * M)`. The 1% season prize is assigned immediately, without looking at farms.
- For one farm with committed weight `h`, compute `maxGross = floor(rewardPerHash[e] * floor(1.10 * h) / Q)`. Reserve attribution is `maxGross + floor(0.05 * maxGross)` plus its pro-rata redistribution envelope. This uses the same rounding as actual gross; flooring a global envelope before apportionment could underfund a tiny payout by one wei and lock its cursor. Aggregate mining/referral attribution is at most 115.5% of mining; the additional 1% prize still fits the 117% budget.
- Engine replays the farm's historical loadout, wear, combo protections, theft and event. Farm identity is its permanent player address; hits use `keccak256(abi.encode(epochSeed, player))`. No caller supplies damage, hash, beneficiaries or victim lists.
- Gross mining is `floor(rewardPerHash[e] * realizedProductiveHash / Q)`. Electricity uses the same rate times realized power, then the epoch tariff (halved for Cheap). Audit charges exactly 10% of gross if **pre-event raw hash is strictly greater** than the snapshotted threshold. Severity does not scale that fixed 10% tax. Default threshold is 100,000 contract hash units, bounds 10,000–10,000,000, subject to the usual 10%/24h governance limit.
- Tax redistribution payout uses `min(realizedRawHash, h) / H`; exhausted/destroyed farms receive none. Their larger committed-weight envelope is safely recycled. This also prevents increasing realized hash from overdistributing a tax pool.
- Net mining, redistribution and an optional one-level 5%-of-gross referral are credited once. Green is bounded at 110% of allocation; even 110% gross plus a 5% referral plus a 1% season prize fits the 117% reservation. Electricity only reduces the obligation. This corrects the old 116% envelope's worst-case shortfall.
- Unused attribution is recycled during settlement. For the most recently closed epoch only, up to `M/6` in aggregate can instead fund the existing scrap allowance; the remainder is recycled. The next advance recycles unspent scrap allowance. The last settled allocation weight releases final rounding dust. No farm is assigned the entire dust remainder based on caller order.

Reservations conserve tokens: locked principal is unavailable; reserved obligations, mining credits, tax queues, prizes, scrap and recycled balances never overlap. Delayed settlement delays recycling and therefore can change **future** available pool and emission budgets. Equivalence means exact eager replay of the same closed global snapshots, not a claim that different patterns of player transactions produce identical future pool balances or prices.

## Bounded player settlement and taxes

`FarmRewards.settle(player, limit)` is permissionless, unpaid and accepts only 1–8 epochs. It returns the persisted `lastSettled` cursor; duplicates have no effect. Each epoch visits at most 24 installed items. Core mutations auto-settle up to eight and require completion. Claim auto-settles up to eight and can withdraw an existing or newly credited amount even if more history remains. A frontend can explicitly settle, read `pending`, then claim. `pending` reports credited funds, not a costly simulation of all outstanding history.

Credits age from the original epoch end, not the catch-up transaction. Credits already seven days old enter the 5%-tax matured bucket directly. Before consumption, a fixed 32-slot sweep moves all old sparse vintages into that bucket, so old credits are spent before newer higher-tax credits, even after ring wrap. The minimum six-hour epoch spacing and 32 slots exceed the seven-day tax horizon. Late referrals cannot evict a still-young credit. Claims and fee withdrawals remain callable during PackSale pauses and between epochs.

## Seasons

Calendar weeks still start at the token launch timestamp. Yield and activity tickets accumulate during farm settlement. A farm enters the prize competition only after settling the last closed epoch of that entire week; partial low-yield history cannot inflate its spend/yield score. At completion, the full score competes with the running best and its ticket count is inserted into the existing bounded 32-level sum tree. Ties use the lower player address.

The deadline is **week end plus seven days**. Completing later still pays mining and applies wear, but adds no tickets, score or district entitlement to that season. This published cutoff prevents an absent farm from indefinitely blocking rewards and prevents late entry after the lottery seed is known. A farm with zero total earned yield cannot enter. Season prizes are reserved globally regardless of attendance; an empty eligible season recycles them.

After the deadline and once an epoch has advanced beyond that week, anyone calls `prepare(week,1..64)`. The old limit argument remains for client compatibility; preparation now performs one constant operation and pays no bounty. The roster is already fixed by the deadline. `finalize(week)` examines eight districts and selects at most three distinct weighted winners using bounded tree traversals. It awards the best-score prize and pays at most one small nonempty-season bounty. A missed 256-native-block entropy window requires `rearm` and a fresh future block. Winners pull their item/pack entitlements; full inventory does not block global finalization.

## Authority and operations

Only advance, entropy capture, successful buyback and nonempty season finalization pay bounties. The old Params enum indices for MeasureBounty, CreditBounty, AuditBounty and SeasonScoreBounty are retained for ABI numbering but FeeRouter rejects them even from their former authorized producers. There is no `processEpoch` keeper cursor anymore.

The selected launch share is 200 bps (2%); heartbeat cap is fixed at exactly 1 ETH, and overflow funds reward buys. The bounded share setting remains available for a future evidenced gas/revenue change; it does not create a withdrawal or an upgrade right. Only PackSale's new paid purchases can be paused by the swarm for up to 72 hours, followed by the retained 72-hour live interval. No other module has a pause path. The hook's only privilege remains the fixed team's one-time FeeRouter binding.
