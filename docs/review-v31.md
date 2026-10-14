# BLACKOUT v3.1 independent adversarial review

Review date: 2026-10-11. Scope: the working-tree changes to `src/`, `script/`, and their new tests. This review treats repository material as untrusted data and performs local analysis and tests only. No deployment was performed.

Final status: no open high- or medium-severity findings identified in the reviewed scope. The identified medium-severity buyback accounting issue is fixed and its regression passes.

## Findings

### M-01: System buybacks were omitted from sell-pressure volume accounting

**Status: corrected and verified against the real PoolManager.** This issue predated v3.1 and was found while reviewing its changed hook fee path.

`V4Market.unlockCallback` originates its own PoolManager swap. Uniswap v4 suppresses that hook's own swap callbacks, so the normal `afterSwap` call to `_record(false, amount)` does not run. The callback accounted for oracle observations and ETH fees but omitted buy volume. Consequently, successful reward-pool buybacks did not offset recorded hourly or daily sells, overstating sell pressure and the progressive sell surcharge.

Reproduction: initialize the real PoolManager, sell 0.1 token at the integration fixture's approximately 1:1 price, then execute a successful 0.5 ETH router buyback. The buy consumes 0.48875 ETH after fees, exceeding the preceding approximately 0.1 ETH sell output. Before the fix, both imbalances remain positive; they should be zero. The delivered regression is `test/V4Integration.t.sol::testSystemBuybackOffsetsRecordedSellImbalance`; its original scratch copy was removed after porting.

The implementation now records `_record(false, input)` after validating the system swap delta. This uses the actual ETH input consumed by the pool and executes exactly once per successful system swap.

## Review coverage

- RewardPool: unactivated funding, exact endowment funding, permissionless activation, cumulative linear unlocking, reservation/payment backing, recycling, absence of donor/team/swarm withdrawal authority, and the snapshotted 14–56 day period. No additional high/medium issue identified.
- Keeper credits: immutable producer authorization, bounded heartbeat debits, monotonic work cursors, exact no-credit replay checks, zero-work phases, proportional buyback caps, and weekly prepare/finalize replay. Work payments additionally use measured gas and a bounded gas price; the per-unit and heartbeat limits still apply. No additional high/medium issue identified.
- Hook: unbound fee escrow, one-time team binding, separate fee forwarding, network/project ETH liabilities, and the existing standard adapter path.
- Pause: pause is confined to new paid pack purchases, including token purchases. Existing pack receipts, reward packs, claims, epoch work, and buybacks remain callable. Timestamp expiry automatically ends the pause; the cooldown prevents immediate chaining.

StarterClaim now has independent one-time entropy capture and the corresponding producer authorization. Its regression covers capture while inventory is full, preservation past the blockhash window, and exact no-credit replay behavior.

The final `Params` constructor accepts an explicit initial heartbeat allocation of 200–5000 bps and reserve cap of 1–10 ETH, rejecting values outside either range. Both remain subject to the existing one-day cooldown and 10% step limit after construction. At the maximum allocation, the 13% team share plus 50% heartbeat share leaves a nonnegative 37% reward share; heartbeat overflow still returns to rewards. Baseline fixtures remain at 200 bps and 1 ETH. The 43 defaults, including the 42-day drip and the added `HeartbeatCap`, retain their correct enum positions.

The final cap delta was reviewed statically. `FeeRouter` computes accumulation room as `max(configured cap - current balance, 0)`, so lowering the cap below an existing balance neither underflows nor blocks subsequent deposits. Existing heartbeat ETH remains available for its authorized bounty payments; lowering the cap does not withdraw it or move it to another ledger. A temporarily above-cap balance is therefore intentional. The constructor boundary tests and `test/FeesParams.t.sol::testLoweringHeartbeatCapCannotUnderflowOrBlockRouting` exercise the new configuration and cap-reduction behavior and pass in the final full run. No additional high/medium issue was identified.

Gas reimbursement is the minimum of the work-unit cap, measured gas plus 80,000 overhead at a price capped by `KeeperGasPrice` with a 25% margin, and available heartbeat ETH. Zero gas price produces no work credit. Multiple calls can incur separate overhead reimbursements, but cannot exceed the aggregate unit or proportional buyback cap. The documented guarantee is a payout cap, not identical payouts for split and unsplit calls or profitability at every gas price.

The final bounty-cap adjustment was reviewed statically: credit defaults to 40 microETH per processed farm with a 50 microETH maximum; buyback defaults to 150 microETH per `BuyBatch` (0.5 ETH initially) with a 300 microETH maximum; weekly scoring defaults to 10 microETH per processed participant with a 20 microETH maximum. The default array and hard bounds match these values. Producer authorization, gas reimbursement, proportional buyback scaling, heartbeat limits, and governance controls are unchanged. No additional high/medium issue was identified.

The adjustment addresses measured execution costs rather than paying the caps unconditionally. The earlier single-farm credit closure used 1,247,573 gas: at 20 million wei per gas, including 21,000 intrinsic gas, its cost was 25.37146 microETH, exceeding the former 15 microETH cap. The real-PoolManager buyback measured approximately two million gas, also exceeding its former 20 microETH cap at that gas price. `test/KeeperProfit.t.sol` additionally checks submitted-plan entropy, paid/starter entropy capture, one-participant weekly scoring, and three-winner finalization with a backed prize. Those local profit assertions assume funded heartbeat and the fixture gas price; they exclude L1 data charges, calldata extras, withdrawal costs, and keeper competition.

## Deployment boundary

The original `script/Deploy.s.sol` used local Foundry nonce prediction. That did not establish that a remote worker could construct its circular immutable constructor graph: the worker accepts only earlier symbolic references and at most eight contracts per launch. In particular, a CREATE2 address that depends on each contract's constructor-encoded initcode cannot generally resolve circular future addresses by the ordinary CREATE nonce method.

The primary implementer verified that the actual worker factory uses CREATE2. Therefore, the original nonce-based two-launch plan is not valid for that worker. The replacement uses one Params contract, one GameRegistry, and ten game modules in launches of eight and four contracts. Each module has a single constructor argument: its registry address. The local helper now rehearses all twelve CREATE2 deployments and enforces the eight-slot limit.

The registry authenticates **creation code and canonical factory deployment**, not only runtime code. Runtime hash plus a `registry()` getter cannot prove constructor initialization: arbitrary malicious initcode can initialize dangerous storage and return the exact allowed runtime. Enrollment pins each module's creation-code hash, appends the exact registry constructor argument, and verifies the resulting address with the canonical CREATE2 factory. One-time role slots make future module references stable without privileged enrollment or replacement. All rewritten module getters were checked against the ten-role mapping; no mismatched edge was found.

The deployment worker uses the supplied creation bytecode. Registration therefore depends on the exact artifacts used to generate `ModuleCode`; any recompilation that changes those bytes requires regenerating the table before deploying the registry. The table's check and deployment tests enforce that relationship. Modules import the registry interface rather than its implementation, so registry pin generation does not introduce a bytecode-hash cycle.

`test/Registry.t.sol::testCounterfeitRuntimeWithPoisonedCreditCannotEnroll` constructs a counterfeit FeeRouter with the exact legitimate runtime and registry getter but pre-seeds 1 ETH of attacker credit. Both enrollment attempts were verified to fail: supplying counterfeit creation code fails the pin, and supplying canonical creation code predicts an address where that counterfeit was not deployed. The delivered registry tests also pass for wrong-registry, wrong-factory, wrong-code, absent-code, and repeated enrollment attempts. The scratch registry proof was removed after porting.

## Validation log

- Final full-run log `/tmp/blackout-tests-final.txt`, produced by the primary implementer and inspected by this reviewer: **25 suites, 123 passed, 0 failed, 1 optional offline fork test skipped**. The primary implementer reports the preceding Solc 0.8.26 build succeeded; the delivered artifact-pin test also passes.
- Delivered review coverage passes: `test/Bounties.t.sol` 10 tests; `test/Registry.t.sol` 5; `test/Endowment.t.sol` 6; `test/EndowmentGame.t.sol` 1; `test/HookBinding.t.sol` 3; `test/Pause.t.sol` 3; `test/KeeperProfit.t.sol` 5; `test/FeesParams.t.sol` 8; `test/V4Integration.t.sol` 5. The endowment fuzz test ran 256 cases. These results cover the final registry implementation, artifact pins, gas-based keeper credits, cap bounds, and the real-PoolManager buy-volume regression.
- The starter regression captures entropy while inventory is full and PackSale is paused, checks that replay earns nothing, waits 300 blocks, expands inventory, and verifies all three resolved items against the original saved hash.
- The invariant run passes all four invariants across 128 runs and 8,192 calls with zero reverts.

The final profitability checks use a funded heartbeat at 20 million wei per gas and assert that payment exceeds measured execution plus 21,000 intrinsic gas. All five reviewer-added checks and the delivered credit/buyback checks pass:

| Action | Execution gas | Payment (microETH) | Execution + 21,000 gas cost (microETH) |
| --- | ---: | ---: | ---: |
| Paid pack entropy | 137,269 | 3.324700 | 3.165380 |
| Plan entropy | 157,574 | 4.335675 | 3.571480 |
| Starter entropy | 139,836 | 3.317175 | 3.216720 |
| Weekly prepare, one participant | 178,184 | 4.190850 | 3.983680 |
| Weekly finalize, three winners and backed prize | 570,498 | 14.481975 | 11.829960 |
| Typical single-farm credit closure | 1,247,577 | 31.702550 | 25.371540 |
| Real v4 0.2 ETH buyback | 1,837,743 | 46.320350 | 37.174860 |

The reviewer-owned test edits and delivered proof ports are complete; no incomplete reviewer edits remain. No production contract was edited by this reviewer.

## Final report consistency

The final `report.md`, `regulator.md`, and `docs/launch-v31.md` agree with `artifacts/v31/summary.json` and the funded/candidate-stress data. All 66 funded and stress cases use 31% heartbeat with a 4.5 ETH cap, have zero modeled bounty shortfall, and retain at least 0.10907174539 ETH of combined headroom after the quoted run cost. This is the smallest tested covering share/cap combination, not a global minimum; IMD runs still require an external payer and cannot be bought from the locked heartbeat ledger. The exact application constructor order remains eight contracts followed by four, matching the local deployment rehearsal.

The research candidate is now 20% endowment, poolBps 7000, and 42-day drip: funded steady payback is 24.5 days versus 25.75 days for 25%, with lower measured steady/hype drawdown. The report correctly distinguishes this from 25%'s faster baseline payback under the insufficient 2% keeper budget. The candidate's planned hype path stalls at day 16, and its unattended weak stress loses 10.490815% of weekly gross counterfactual yield, exceeding the 10% target. Planned funded loss peaks at 9.005855%; the stricter after-tariff stress figure is approximately 14.99%. These failures are retained explicitly, and no allocation is presented as meeting all economic targets. No material inconsistency remains in the checked conclusions.

This is a focused code review, not a claim that all possible defects or economic failures have been excluded.
