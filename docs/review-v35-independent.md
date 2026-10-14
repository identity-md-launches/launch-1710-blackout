# BLACKOUT v3.5 independent contributor review

Internal security and launch record. This document is not player-facing documentation and is not part of the public site navigation. No deployment, broadcast, or token action was performed.

The second contributor reviewed the implementation independently of the contributor writing the contracts and tests. The review covered `Economy`, `Enhancement`, `Civic`, `Billboards`, the token purchase and fee paths, lazy farm accounting, item custody, starter claims, seasonal token pots, and registry enrollment. The pinned project history and supplied Ethereum security reference were treated as review inputs. This is a bounded source review, not an external production audit.

## Findings and disposition

### M-1: Contest finalization used mutable post-deadline inputs

The first implementation of `Civic.warScore` read live district active hash and the current mining-to-token conversion rate. Funding closed after 48 hours, but finalization could happen arbitrarily later. A district could activate additional hash after the funding deadline, wait for its opponent's hash commitment to expire, or wait for the mining rate to change, then finalize a different winner. The result controls the losing chest's redistribution and the output reward.

The implementation now snapshots both district hashes and the conversion rate at contest creation (`War.hashA`, `War.hashB`, and `warRate`). The chest contributions remain changeable only during the 48-hour contribution window. This fixes caller-selected finalization timing; it explicitly defines the active hash part of the score as the starting snapshot. The deployment/operator documentation must retain that definition.

Source review of the fix is complete. The implementing contributor retained the regression in `test/CivicV35.t.sol::testWarFreezeScoresConservationAndPayoutOnlyOnce`. A separately authored isolated regression passed under Solidity 0.8.26, checking post-deadline hash/rate changes, the resulting winner, and the fixed registry binding. Its source is retained in `test/WarReviewV35.t.sol`.

### M-2: Automatic repair spending omitted paying-farm season eligibility

The first `FarmCore.autoRepair` implementation consumed pending tokens directly with `rewards.spend` and restored the item. Manual repair instead passed through `_charge`, which records season spending and paid XP. Consequently a farm paying only automatic repairs during a later week could receive no paying-farm district entitlement despite spending the same tokens as a manually repaired farm. This also omitted the spending from the best-farm score.

The implementation now passes the settled epoch to `autoRepair` and records its actual cost through the Core-only `Season.recordRepair`. The cost is attributed to the historical mining epoch's week before activity and completion are recorded. `recordRepair` ignores completed farms and submissions after the fixed season grace deadline, so settlement cannot reopen old results. Paid XP is credited under the existing transaction-day cap and the normal spending event is emitted. Source verification of this fix is complete. The independently authored regressions are retained in `test/AutoRepairReviewV35.t.sol`; executable results are recorded below.

### M-3: Item-yield floor used the wrong fixed-point scale

`FarmRewards.lastYieldPerHash` stores wei of token per hash multiplied by `1e18`. The initial `Economy.HASH_RATE_FLOOR` supplied only `0.000001 ether`, but `itemDaily` divided both the observed rate and the floor by `1e18`. Consequently ordinary item floors rounded to zero before the first positive settled rate. Manual enhancement/repair then reverted at the nonzero charge check, while automatic repair could restore durability at zero cost.

The floor is now `0.000001 ether * 1 ether` in the stored rate scale: a Common compute item with 10,000 hash yields a 0.04-token daily quote. Source verification is complete. An independently authored isolated regression passed, checking that initial daily yield is 0.04 tokens, ten-percent repair costs 0.01 tokens, +1 enhancement costs 0.01 tokens, and all three scale exactly threefold when the settled rate triples. The independently authored source is retained in `test/YieldFloorReviewV35.t.sol`; the existing `EconomyV35` suite also exercises the floor.

## Reviewed properties

- Purchases and lobby payments transfer tokens into the router before allocating their 88/10/2 shares. Ordinary repair, enhancement, room, expansion, and civic spending returns tokens to the reward pool. No new token mint or token burn path was introduced.
- Reward reserves include a 150% output envelope, referrals, the 1% mining prize, and rounding slack. Automatic repair recycles consumed liabilities rather than allocating new tokens. Lazy processing skips wear when the farm has no active weight. The final tax redistribution correction uses productive hash bounded by committed weight, so output tiers also constrain redistribution and fully overheated farms receive none; unspent reservation is recycled.
- Pending enhancement attempts lock the item against placement and scrapping. A captured seed cannot be replaced, and resolution consumes the pending attempt before applying the outcome. The failure downgrade and conditional burn tables were checked against the brief through +16.
- Lock principal has no early withdrawal or administrator withdrawal. Lock state is synchronized with farm settlement before mutation. Escrow removal updates both list links and district totals.
- The official V4 system sell authenticates FeeRouter, measures the full token debit and ETH output, uses the 30-minute quote for its minimum, limits sale size using pool liquidity, and charges ordinary project/network fees. Its own-hook callback suppression is handled explicitly. Router ETH proceeds are not routed through the generic donation split a second time.
- Starter claims bind index and wallet, cap indices and aggregate claims at 500, mark entitlement before registering the farm, and cannot replace the root once set. The existing Identity MD receipt namespace remains separate.
- Weekly pots maintain a separate liability, per-week remaining balances, one-time claims, and one-time rollover. Pot transfers and prize minting are atomic: failed receiver transfers or full inventory revert the entitlement mutation, preserving retry rights.
- The size-reduction extractions preserve caller boundaries: automatic repair in `Economy` accepts only Core and checks each item holder, enhancement resolution consumes its pending attempt before direct item mutation, and supply-drop drawing in `FarmItems.mintDrop` remains Core-only and passes through the guarded mint path. Automatic repair deliberately permits its trusted nested call during lock synchronization.
- Final purchase hardening makes `Civic.buyLot` require the canonical `PackSale.ready()` predicate before any lot, payment, or inventory mutation. This includes opening time, automatic pause expiry, profile selection, funded endowment, and official FeeRouter binding, while retaining the module enablement check. A missing module or incomplete binding fails closed.
- Reserved Festival output clamps every `uint16` severity to a 500–1,500 basis-point bonus. Even with the maximum combined civic bonus of 2,500 basis points, its 1.4375-times multiplier stays below the 1.5-times reservation envelope. Heatwave extra cooling wear retains both Airflow and Cold Power protections. The final hardening and corresponding readiness/reserved-event regressions received source review; the implementer's final run supplies executable evidence for these later changes.
- Module enrollment still proves the exact creation code and canonical factory address. Modules have registry-only constructors without external calls and no replacement or upgrade entry point. Creation-code pins and final factory tests must be regenerated and rerun after source changes.

## Constructor-only registry binding

The pinned Solidity 0.8.26 compiler encountered an assembler immutable-patching failure when the larger modules used `GameModule.registry` as a Solidity `immutable`. The implementation now stores that address in an ordinary storage slot, assigned only by the constructor. This changes the compiler representation, not the exposed authority: source inspection found one assignment, in `GameModule`'s constructor, and no setter, delegatecall, upgrade, or arbitrary storage-write path in the production graph. Compiler-managed inherited storage prevents module state from aliasing the new slot.

The v3.4 enrollment proof already commits the entire canonical creation code **and** the ABI-encoded registry constructor argument to the factory's CREATE2 address. It therefore proves the initial registry storage value as well as the code that has no subsequent writer. The official market's binding additionally verifies that canonical registry and its enrolled router. An alternate module with a registry setter would have different creation code and fail enrollment. No live instance is migrated or modified by this source change. All creation-code pins and layout-dependent test fixtures must be rebuilt for the final source.

## Residual assumptions and operational risks

Future-block entropy is the mechanism explicitly requested here; it is not a verifiable randomness service. A sequencer can influence it, and an uncaptured result can expire and be re-armed. Timely permissionless capture is therefore material. The entropy bot now supports enhancement commitments; the operator must include the pinned Enhancement module when configuring it. The new selectors and receipt field positions were checked. An already captured result cannot be retried.

The wallet share limit is a soft cap against each district's *uncapped* stake/chest total. It is not an identity or Sybil limit, nor does it ensure that every wallet is at most 10% of the final counted total in a small district. Locked tokens continue to be escrowed until the player withdraws after maturity. These definitions must be explicit in the economics and operator documentation.

The 30-minute price observation and 150-basis-point minimum do not guarantee liquidity or prevent sustained manipulation. System sale execution may remain unavailable when depth is insufficient or price has moved outside the allowed range. Permissionless maintenance still needs someone to submit transactions.

Unclaimed pro-rata rounding dust can remain in escrow. Swarm administrative powers, item receiver rejection, and full inventories are deliberate trust/liveness boundaries rather than upgrade or seizure authority. The generic historical StandardAdapter is a buy-only compatibility artifact; a v3.5 launch must use the reviewed official market path supporting the new sell interface.

## Verification record

Final observed launch bytecode sizes fit the EIP-170 runtime and EIP-3860 initcode limits. The largest game module is `FarmCore` at 24,330 runtime bytes, leaving only 246 bytes of runtime headroom; any future source change must repeat this measurement. `MarketFactory` is 21,390 bytes and `V4Market` is 18,861 bytes. No library link placeholders were present in the observed production artifacts.

Independent command: `forge test --match-path test/scratch/IndependentWarReview.t.sol -vv`, using the unmodified pinned Solidity 0.8.26 configuration. Final result: **1 passed, 0 failed** after the compiler representation repair and a scratch timestamp-fixture correction.

Independent command: `forge test --match-path test/AutoRepairReviewV35.t.sol -vv`. Final result: **2 passed, 0 failed**, covering historical-week eligibility and the fixed grace deadline. These independently authored tests are retained as permanent deliverables. The earlier setup failure was resolved by synchronizing creation-code pins with the final compiled artifacts. The war regression was also rerun against the final artifacts: **1 passed, 0 failed**.

Independent command: `forge test --match-path test/scratch/IndependentYieldFloorReview.t.sol -vv`. Final result: **1 passed, 0 failed**, checking floor units and observed-rate scaling without a factory-pin fixture.

Slither, Mythril, live-chain forks, and production deployment checks were not run by this reviewer. No external audit certification is claimed. All three reported medium findings are source-verified fixed and covered by passing independent regressions. No high-severity finding was confirmed in this bounded review. The implementing contributor's final full test and pin checks remain separate necessary release evidence.
