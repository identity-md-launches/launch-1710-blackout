# BLACKOUT v3.2 independent contributor review

A separate contributor agent, `v32_review`, was started with fresh context and a bounded read-only review assignment. It did not implement the changes. It independently inspected the final Solidity diff and surrounding modules, checked the accounting specification and economic model, and executed targeted checks. This is a source review, not a live deployment audit or a guarantee of economic returns.

## Findings and repairs

| Finding | Severity | Evidence and resolution |
|---|---|---|
| Tiny mining emissions could underfund an individual envelope by one wei and block catch-up | Medium | The old formula floored the total 116% envelope before apportioning it. For 1 wei mining, a Green farm could earn 1 wei with a zero-wei attribution. Allocation now uses the same reward-rate and productive-hash rounding as gross, then adds its maximum referral. `testOneWeiMiningGreenCannotLockSettlementThroughEnvelopeRounding` reproduces the case. The reviewer independently checked 505,000 small two-farm partitions and proved the 117% aggregate reservation remains sufficient. |
| Sparse old reward vintages could be consumed after younger taxable credits | Medium | At epoch 34, credits from epochs 1 and 32 occupy slots 1 and 0; the old ring traversal reached slot 0 first. `_consume` now sweeps all 32 slots by actual age into the matured bucket before spending. `testSparseMatureVintageConsumedBeforeRecentSlotAfterWrap` confirms the oldest 100 tokens incur exactly the 5% floor. |
| Exhausted farms could continue taking redistribution using stale allocation weight | Medium economic issue | Allocation intentionally stays committed until an owner action, but redistribution must reflect actual eligibility. Payout now uses `min(realizedRawHash, allocationWeight)` while its reservation remains based on the larger envelope. The unused portion is recycled. `testExhaustedFarmCannotCollectRedistributionByRemainingIdle` confirms a zero-durability farm receives no redistributed tax despite a nonzero committed weight. |
| Simulator scrap and outstanding dust did not follow lazy reservations | Simulation discrepancy, affects available emissions | Active scrap capacity now excludes unsettled farm envelopes and final rounding headroom. The 0.5% mining headroom remains reserved while any positive-weight farm is unsettled; prior scrap is recycled before sizing the next mining budget. A numeric regression checks the active attribution bound with 60% idle weight. |
| Destroyed simulator items retained a same-epoch combo | Simulation discrepancy, affects economic estimates | Destroying an ASIC left a GPU producing 11 model hash instead of 10 through a phantom compute-pair bonus. Actual room stats now remove destroyed items before masks/tags/rarity calculations; the no-damage shadow intentionally retains them. A Python regression reproduces the reviewed case. |
| Simulator season lottery used pack rarity probabilities and independent kind/rarity draws | Simulation discrepancy, affects economic estimates | The contract uses the same seed modulo 100 for both kind and the 90% Rare / 10% Legendary split. The final simulator matches that correlation: Legendary prizes are only motherboard/rack/surge kinds. Regression tests reject Mythic prizes and impossible Legendary kinds. |

The review also identified old event-test setup that called `process` before the epoch was closed. Those tests now advance and settle through the real snapshot path, rather than bypassing the new historical-event boundary.

## Independently executed checks

- `forge test --match-contract 'LazyAccountingTest|EventsTest' -q`: passed, including the 256-case independent eager-reference fuzz test and deterministic event/destruction tests.
- `python3 -m unittest discover -s test/python -v`: all 19 tests then present passed.
- `python3 sim/blackout_sim_v32.py --check`: all five retained model checks passed.
- The one-wei Green regression passed independently after the rounding repair.
- The five v3.2-specific Python regressions were rerun after fixing lottery correlation: passed. After the reservation/scrap corrections, all six v3.2-specific Python tests passed independently.

Review covered allocation envelopes, historical weight promotion, reserve/dust accounting, monotonic settlement cursors, destruction/theft bounds, retirement, callbacks, claim aging, season eligibility/freeze deadlines and documentation. The contributor confirmed the fixes and reported **no unresolved high or medium Solidity findings**. It made no file edits and sent no transactions. The reviewer also rechecked the model reservation flows after the scrap/dust findings and found no additional material lazy-accounting mismatch. The primary contributor subsequently completed the full suite and final simulation verification recorded in report.md and artifacts/v32; the independent reviewer did not claim to have validated all final economic run artifacts.

## Residual limitations

Future native-block randomness and fixed timeout fallbacks retain the v3 sequencer-influence assumptions; this is not a VRF. An unpaid bootstrap advance, timely entropy capture, slippage-safe buy execution and IMD policy-run funding remain operational responsibilities. No fixed heartbeat share guarantees keeper participation at arbitrary gas prices or after revenue stops.

Lazy/eager equivalence is exact for the same immutable global epoch snapshots. Settlement timing can change future available funds through delayed recycling. Committed inactive weights and their outstanding reservations affect the economy and are modeled, not hidden by deleting absent farms. The economic model still assumes demand, churn, maintenance, referral adoption, gas prices and simplified single-sided AMM behavior. No test establishes profitability.
