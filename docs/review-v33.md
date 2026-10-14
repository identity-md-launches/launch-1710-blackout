# v3.3 review (same author, fresh checklist pass) — independent review still required

This was a checklist pass using `.imd/reads/skills/eth-security`. No independent contributor was available in this run, so this does **not** satisfy the brief's requirement for a second contributor. It lists what was checked and what was fixed.

| # | Area | Finding | Severity | Status |
|---|---|---|---|---|
| 1 | FarmRewards expiry | Re-committing within one epoch must move the old bucket, not add a second one. | High if wrong | Done: `_commit` removes the pending bucket when `nextExpiry > epoch`. Tested by `testActionBeforeExpiryMovesBucketWithoutDoubleCount`. |
| 2 | FarmRewards expiry | Settling an epoch from before the latest re-commit must use the expiry that applied at that time. | High if wrong | Done: `weightExpiry` and `nextExpiry` are kept alongside `weight` and `nextWeight`, and both roll forward together. |
| 3 | FarmRewards expiry | The epoch dust check `settledHash == raw` must still close when expired farms are left out. | Medium | Done: `raw` and `settledHash` both exclude zero-weight farms. Covered by the lazy-vs-eager fuzz and invariant suites. |
| 4 | claim re-commit | Claiming while behind must not re-commit against stale settlement. | Medium | Done: re-commit only when `lastSettled >= settledEpoch`. Tested. |
| 5 | Hook launch tax | Rounding could leave 1 wei of "launch tax" after the window, causing a needless take and event. | Low | Fixed: when the fee equals the normal fee, the network gets `normal − base`, the same as v3.2. |
| 6 | Hook max buy | System buybacks bypass hook callbacks, which would have skipped the max-buy check. | Medium | Fixed: `unlockCallback` enforces `maxBuy()` as well. |
| 7 | PackSale price | Measuring the VRGDA clock from token launch would discount the opening price by an hour of target. | Medium | Fixed: the clock starts at `opensAt()`. |
| 8 | Season district | The top-10 list must be exact even when a wallet outside the list later becomes the largest spender. | Medium | Done: spend only grows and every increase re-checks against the minimum. Tested by `testTopSpenderTrackingIsExact`. |
| 9 | Season gas | `finalize` now computes 8 district scores (about 10 reads plus a 10-element sort each). | Low | Accepted: bounded, no loop over farms. |
| 10 | Idle wear | Expired farms still take event and wear effects when their epochs are settled. | Low (design) | Documented. Players should `sync` every 3 days or unplace items. |
| 11 | 10% wallet cap | Under the literal rule, districts with fewer than 10 spending wallets score 0. | Design decision | Documented. The requester should confirm. |

Unchanged trust assumptions: the one-time `bindFeeRouter` by the team, the swarm Params bounds (at most 10% change per 24 hours), and the PackSale pause (72 hours maximum with a 72-hour gap). There is no owner and no upgrade path.
