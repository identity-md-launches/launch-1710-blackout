# Implementation-author adversarial review

This review was performed during implementation. It is **not independent** and is not a release audit. No external reviewer, Slither run or Mythril run is claimed. The RPC-backed Robinhood fork smoke test passed; its limited native-clock scope does not validate the eventual application deployment and external market configuration.

| Area examined | Design / evidence |
|---|---|
| Authority | Immutable contract links; no owner, proxy, generic calls, admin withdrawals or extra minters. Unauthorized mint, parameter, event and callback paths revert in tests. All parameter keys have bounds and step-limit tests. |
| User custody | ERC-1155 escrow accepts only a solicited transfer from its player. Exact owner/slot accounting and return paths; Starter movement cannot transfer ownership. Generator principal has its own vault and caller-only unlock. |
| Pool solvency | Fresh liability reserved before accrual. Existing reservations excluded from emission. Pending rewards, referral budgets, tax redistribution and inspection prizes remain funded. Fuzz/stateful tests cover exact token and custody conservation. |
| External calls | SafeERC20, checked incoming token deltas, checks before transfers, reentrancy guards. Malicious ERC-20 callbacks, rejecting transfers, ERC-1155 receiver callbacks, ETH recipient reentry and failed ETH delivery have regression tests. |
| Randomness | Future native block commits, asynchronous resolution, expiry fallback and duplicate rejection. Tests cover Arbitrum native block semantics. This remains sequencer-trusted randomness; delaying resolution can select the deterministic fallback. |
| AMM integration | Authenticated immutable PoolManager/pool callbacks; correct hook address flags; exact-input return deltas; real v4 liquidity/swap/settlement tests; system-buy output and balance checks. |
| TWAP and fees | Cumulative ETH/token arithmetic prices, elapsed-time weighting, same-block manipulation test and mixed-price test. Current sells enter their own fee; fractional decay resists dust-reset griefing; hard 15% total cap. |
| Operational failure | Expired events become Calm; event quotas permit recovery after missed ticks. Pack pause has an immutable maximum and cooldown. Emission/account catch-up is permissionless and bounded. |

Defects found and repaired during this work include:

- Rarity hash multiplication initially inherited too narrow an integer type; explicit uint256 bases now cover Rare through Legendary and all six types.
- Tax redistribution initially shared a referral-bearing index. Separate new-mining indices now prevent a referral top-up on recycled tax and preserve the entire tax amount for the next tick.
- A reward-vintage ring originally covered only the default decay. Sixteen daily slots now safely cover the maximum 14-day setting, with a regression test for changing decay while rewards are outstanding.
- An empty first-tick pool could snapshot zero emission until the following tick. It can now initialize its rate after the first funded buyback without crediting the unfunded past.
- Mint-epoch bonuses now freeze at commitment, avoiding changed outcomes from waiting to resolve or later parameter changes.
- The fee-decay representation retains fractional basis points, avoiding a timer reset attack using frequent tiny trades.
- Grid quota validation now permits positive events to restore minimum frequencies after an outage instead of permanently rejecting all submissions.
- A fully decayed farm can fund repairs from its own wallet; revival does not require already-claimable mining rewards.

Remaining material trust and operating limitations are documented, not treated as fixed findings: sequencer influence; Sybil wallet/referral/district selection; stale farm refresh snapshots; daily-average durability attribution; bounded catch-up gas; immutable configuration mistakes; ordinary non-taxed token requirements; conditional hook compatibility; and simulations based on unmeasured behavior. A malicious configured ERC-20 or market adapter is outside the plain-token/trusted-integration assumption. The swarm's external token allocation is not locked by these contracts.

Before live funds, obtain a separate contributor's adversarial review of the final source, test the complete launch hook configuration on the actual chain, and verify the immutable address graph. No transaction or funded-wallet action was taken in this assignment.
