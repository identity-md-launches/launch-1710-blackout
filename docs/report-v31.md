# BLACKOUT v3.1 report

This updates job **5ce56cbc** in the existing repository. **No deployment, token replacement, mint, signed transaction or live spending occurred.** The pinned Foundry compiler/configuration, remappings and dependencies are unchanged.

**None of the requested endowment options meets all economic targets.** Token endowment improves realized ETH payback, but does not create ETH capital. The default 42-day drip with 25% endowment gives the best steady payback among 42-day options, 19.125 days at the original 2% heartbeat share, versus the 14-day target. Every hype path stalls before 21 days and suffers a severe drawdown. Moreover, 2% cannot pay all required keeper work. Correcting that funding deficit diverts substantial revenue from reward buys and makes payback worse. With the funded keeper budget, 20% endowment is the fastest 42-day option at 24.5 days; it also has less drawdown than 25%. These are launch constraints, not passing results hidden behind token valuations.

## Implemented behavior

* RewardPool locks its immutable 100M/150M/200M/250M principal before activation, then releases it linearly over a frozen 14–56 day schedule, default 42. Plain transfer+public activation and exact approval+funding are supported. Donations/recycling remain available normally. Only ordinary FarmRewards reservation/payment paths can spend released tokens. There is no donor privilege, owner, recovery or administrative withdrawal.
* Bounties now cover actual farm measurement/audit/credit cursors, successful buybacks, paid/starter/plan entropy capture and nonempty weekly scoring/finalization. Gas reimbursement is bounded by Params caps and the heartbeat balance. Work state advances before payment; duplicates and empty work earn nothing. Existing advanceEpoch bounty remains.
* The ownerless custom v4 hook holds base fees and sell surcharges separately before the game exists. The fixed team can bind FeeRouter exactly once. Permissionless flushes preserve accounting and roll back on recipient failure without making swaps depend on router availability. The review also fixed v3 buybacks omitted from the rolling sell-pressure offset.
* Twelve application contracts fit two launches of 8+4 using a write-once GameRegistry. It authenticates exact creation bytecode plus the registry constructor argument through the actual factory's CREATE2 prediction. Arbitrary runtime-identical contracts with different initialization cannot enroll. No privileged registrar or module replacement exists.
* Only new paid PackSale purchases can be paused by the swarm for at most 72 hours. Expiry auto-unpauses, with a further 72 hour live interval before another pause. Claims, ETH withdrawals, advanceEpoch, entropy, settlement, buybacks, season work and existing receipts remain callable. No upgrades or delegatecall path was added.

Gameplay, item rarities, mining taxes, referrals, event quotas, seasons and snapshot starter eligibility otherwise remain v3. [Historical v3 report](docs/report-v3.md) is retained; its 10 ETH AMM/funded sensitivities and NFT-holder selling assumption are superseded here.

## Endowment comparison: zero ETH capital

Each run starts with 1 billion existing tokens, 10% contributor allocation, the stated pool/endowment split, and **zero actual AMM ETH and zero reward-buy capital**. The same modeled opening cap is 11.111111111 ETH, preserving v3's implied opening price. Single-sided liquidity uses virtual reserves; only subsequently received ETH can fund a sale. Unsold tokens never count toward cash payback.

Approximately 900 contributor agents are modeled as sellers, with 35/50/65% sale intent by day 14 in steady/hype/weak, after an assumed two-day claim lock. They are not NFT holders. Separate 900 NFT starter entitlements retain the v3 gameplay population assumption. Actual claim-lock/snapshot inputs must be confirmed from the eventual launch. [Assumptions and limits](docs/simulation-assumptions.md) distinguish the model from a concentrated-liquidity EVM replay.

The sweep covers 48 cases: all four allocations, instant/14/42/56 day release and all three scenarios. Instant release is comparison only; production enforces at least 14 days. Whole-cohort payback is the median over **all** week-1 paid farms, with unrepaid/quit farms censored, using actual ETH received after tax, fees and price impact. It is not the median only among successful cashouts.

| Endowment / poolBps | Steady instant | Steady14d | Steady42d | Steady56d | Hype alive,42d | Price drawdown steady / hype,42d |
|---|---:|---:|---:|---:|---:|---:|
| 10% / 8000 | 20d | 20d | 21.375d | 21.5d | 18.75 | 26.3% / 93.0% |
| 15% / 7500 | 19.5d | 19.5d | 20.75d | 21d | 17.75 | 30.3% / 94.0% |
| 20% / 7000 | 17.5d | 18.75d | 20d | 20.5d | 17.5 | 34.5% / 94.6% |
| 25% / 6500 | 17.25d | 19d | 19.125d | 19.25d | 19.25 | 37.5% / 95.5% |

Steady remains mechanically alive beyond 35 days in these baseline cases, but fails 14-day payback even with instant availability. No hype case reaches 21 days; weak fails to repay half its week-1 cohort during 35 days despite remaining mechanically active under the model's stall definition. Price ending above opening does **not** imply price stability: hype loses approximately 93–96% from peak in 42-day cases. A 25% allocation improves cash recovery but deepens drawdown relative to 10%; no tested share establishes the requested combination of fast payback and resilient price.

The 42-day budget/results table below includes gross team ETH. Every row also requires 70 IMD of externally purchased policy runs, valued here at 0.24157 ETH before acquisition/payment gas. If the team pays, subtract that expense from gross proceeds.

| Endowment | Scenario | Repaid week-1 farms | Team gross ETH | HB receipts | Bounties due / paid ETH | Combined deficit incl runs | Weekly loss |
|---|---|---:|---:|---:|---:|---:|---:|
| 10% | steady | 63.0% | 13.7250 | 1.7694 | 9.2663 / 1.7694 | -7.7384 | 2.47% |
| 10% | hype | 25.9% | 18.3703 | 2.3535 | 11.1978 / 2.3535 | -9.0859 | 1.80% |
| 10% | weak | 23.4% | 2.5430 | 0.3284 | 4.4264 / 0.3284 | -4.3396 | 2.96% |
| 15% | steady | 64.7% | 13.7854 | 1.7760 | 9.3076 / 1.7760 | -7.7731 | 1.93% |
| 15% | hype | 25.0% | 18.9384 | 2.4255 | 11.3837 / 2.4255 | -9.1998 | 2.99% |
| 15% | weak | 27.4% | 2.5961 | 0.3348 | 4.5112 / 0.3348 | -4.4179 | 3.76% |
| 20% | steady | 67.3% | 13.7997 | 1.7767 | 9.2823 / 1.7767 | -7.7471 | 1.66% |
| 20% | hype | 25.4% | 18.8619 | 2.4152 | 11.3549 / 2.4152 | -9.1813 | 5.24% |
| 20% | weak | 28.6% | 2.6046 | 0.3355 | 4.6143 / 0.3355 | -4.5204 | 1.79% |
| 25% | steady | 69.2% | 13.9168 | 1.7908 | 9.3175 / 1.7908 | -7.7682 | 3.15% |
| 25% | hype | 24.9% | 18.9259 | 2.4226 | 11.3473 / 2.4226 | -9.1663 | 3.11% |
| 25% | weak | 28.0% | 2.6514 | 0.3411 | 4.6265 / 0.3411 | -4.5271 | 3.17% |

[Full 48-case comparison](artifacts/v31/final/comparison.md) and [all cohorts/epoch data](artifacts/v31/final/simulation.json) include the 14/56 day sensitivities. Planned-case weekly event losses stay below 10% of counterfactual gross yield; the data also allow a stricter after-tariff comparison. The model is one seed and behavioral scenario set, not a return forecast.

## Keeper funding: cost, smallest tested change and tradeoff

On 2026-10-11 the Robinhood RPC reported 0.02 gwei. Work reimbursement is:

`min(perUnitCap * usefulUnits, (measuredGas + 80000) * min(tx.gasprice, gasPriceCeiling) * 125 / 100, heartbeatBalance)`.

The 80k allowance covers transaction/payment overhead; default price ceiling is 0.05 gwei. Credits are pull payments. A full eight-farm/24-item measurement uses about 17.35 million local gas and earns about 0.000434 ETH against about 0.000347 ETH execution cost at 0.02 gwei. Credit processing for those farms uses about 3.14 million gas and earns about 0.000079 ETH. Tests check actual positive margins for typical and dense farms, while caps/balance/race conditions can still make a real call unattractive. Calldata/L1 posting, withdrawing credits, failed races and gas spikes are not free.

| Work | Default cap | Params bounds |
|---|---:|---:|
| Successful epoch advance |0.001 ETH |0.0005–0.003 ETH |
| Farm measurement |0.000060 ETH/farm |0.000010–0.000200 |
| Farm credit |0.000040 ETH/farm |0.000003–0.000050 |
| Audit selection |0.000010 ETH/selected farm |0.000001–0.000030 |
| Pool buyback |0.000150 ETH per 0.5 ETH bought, proportional |0.000005–0.000300 |
| Plan/pack/starter entropy |0.000010 ETH/unit |0.000002–0.000050 |
| Season scoring |0.000010 ETH/participant |0.000001–0.000020 |
| Nonempty season finalize |0.000040 ETH/week |0.000010–0.000200 |
| Gas-price ceiling |0.05 gwei |0.001–0.1 gwei |

Caps are maxima, not a flat payment on every call. Measuring empty-but-registered farm entries is real cursor work, while an empty phase transition is not. A buy's total cap is proportional to ETH volume; splitting cannot increase that cap, although transaction overhead makes actual split credits differ. No unpaid bounty debt accumulates: exhausted heartbeat means partial/zero pay, while the game remains callable.

A 1 ETH cap discards early hype receipts into reward buys, leaving too little reserve for later settlement. Raising only the cap cannot solve 2%'s total income deficit. We compare a **31% heartbeat share and 4.5 ETH cap** with the 2% / 1 ETH baseline. The [full-path boundary checks](artifacts/v31/boundary-checks.json) show:

* 29% / 4.5 ETH, 25% allocation with timely plans: weak is short 0.14128 ETH including runs.
* 30% / 4.5 ETH, 25% allocation without swarm plans: weak is short 0.11779 ETH. Its low receipts do not fill the cap, so merely enlarging that cap cannot cure the deficit.
* 31% / 4 ETH, 25% allocation without swarm plans: hype is short 0.16969 ETH because early cap overflow reduces later reserves.

Thus 31% / 4.5 ETH is the smallest **tested** combination at whole-percentage share and half-ETH cap increments for the full set below. It is not a global optimum or a guarantee under arbitrary behavior. The increase is economically large: the initial 2% budget was far below the measured work load.

| Scenario | HB share / cap | Week-1 payback | Hype/steady stall day | Team gross / after IMD ETH | HB receipts | Bounties due / paid | Minimum combined headroom | Reward buy ETH diverted vs baseline |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| steady | 2% / 1ETH | 20d | >35 | 13.7997 / 13.5582 | 1.7767 | 9.2823 / 1.7767 | -7.74710 | 0.0000 |
| steady | 31% / 4.5ETH | 24.5d | >35 | 12.8916 / 12.6500 | 13.3786 | 8.9640 / 8.9640 | 0.40897 | 11.6904 |
| hype | 2% / 1ETH | not reached | 17.5 | 18.8619 / 18.6203 | 2.4152 | 11.3549 / 2.4152 | -9.18134 | 0.0000 |
| hype | 31% / 4.5ETH | not reached | 16.0 | 17.7720 / 17.5304 | 11.7990 | 10.8202 / 10.8202 | 0.73721 | 9.5008 |
| weak | 2% / 1ETH | not reached | >35 | 2.6046 / 2.3630 | 0.3355 | 4.6143 / 0.3355 | -4.52044 | 0.0000 |
| weak | 31% / 4.5ETH | not reached | >35 | 2.1221 / 1.8805 | 4.3870 | 4.0294 / 4.0294 | 0.10907 | 4.1040 |

The diverted-reward column compares the heartbeat take to 2% on the enhanced run's own routed fee base; demand/fee feedback also changes absolute totals. Team remains 13% of packs/lobby/surcharge and 50% of project base fees. Other routed rewards move from 85% to 56% while heartbeat is below cap; overflow still goes to reward buys. Base project fees remain 50/50. Thus the team percentage is unchanged, but gross team ETH can fall as lower reward buying affects demand. Manual IMD payment further lowers its net proceeds.

The **31% / 4.5 ETH** configuration covers all modeled bounties plus the quoted run cost at every quarter-day in all **48 allocation/drip/scenario reruns and eighteen additional stress cases at 20% and 25% endowment**. No bounty is partially paid in those runs. Minimum combined headroom is **0.10907 ETH**; the minimum in unattended hype at the 20% candidate is **0.39777 ETH**. These are modeled budget margins before extra payment/bridge costs, not withdrawable schedule credits. [Full funded comparison](artifacts/v31/funded/comparison.md), [stress comparison](artifacts/v31/stress-comparison.md), and [machine-readable summary](artifacts/v31/summary.json) expose the complete results.

Funding the work does **not** fix player economics. The table above uses the **20% endowment / 42-day drip** candidate. Its steady payback is **24.5 days** and hype stalls at **16 days**. Without swarm plans, steady does not repay half its week-1 cohort within 35 days and hype stalls at 18.25 days. Team gross ETH in the planned candidate is **12.8916 / 17.7720 / 2.1221** for steady/hype/weak, or **12.6500 / 17.5304 / 1.8805 ETH** after the quoted IMD expense, before other external costs.

The funded allocation ranking differs from the underfunded baseline: 20% beats 25% on steady 42-day payback (**24.5 vs 25.75 days**) and peak drawdown (**35.0% vs 39.6% steady; 95.12% vs 95.76% hype**). This is why the final research recommendation is 20%, despite 25% winning the initial 2% budget comparison. Neither protects the hype price. The 25% alternative has a slightly later planned hype stall (16.25 days) and lower unattended weak event loss.

Event-loss interpretation matters: the largest weekly loss is **5.985%** of gross counterfactual yield in the 2% baseline and **9.006%** in the 31% planned full sweep, both below 10%. However, the added 20% unattended weak case reaches **10.491%**, so the gross event-loss target **fails without timely plans** in that stress. The earlier 25% stresses peak at 8.820%. A conservative after-electricity denominator at the maximum 30% tariff gives **8.55% / 12.87% / 14.99%** for baseline / funded planned / all stress, respectively. The funded and stress sweeps therefore also do **not establish** the 10% target under that stricter interpretation. [Candidate stress data](artifacts/v31/candidate-stress/simulation.json) retain this failure; no passing-result selection is used.

The replay sweep resolves 1 bps candidates with fixed behavior; full reruns include the routing/price/demand feedback. Do not label a replay estimate a proven minimum. Sensitivities for claim locks and missing swarm plans are in the [18-case stress comparison](artifacts/v31/stress-comparison.md). A six-hour schedule is policy cadence; public transaction bots must separately capture entropy inside 256 native blocks. The first launch advance and manual schedule purchase require a bootstrap payer even though the game has no ETH capital endowment.

## Recommended parameters and launch responsibility

**Research candidate, not an all-target launch pass:** poolBps **7000**; endowment **20% = 200 million tokens**; drip **42 days**; custom hook 2% project + 0.25% network plus bounded sell surcharge; heartbeat **3100 bps / 4.5 ETH cap**; bounty caps as listed. Default 42 days spreads principal and avoids instant front-loading; a 14-day drip also misses payback. This selects the fastest 42-day steady option **after paying for keeper work**, with lower modeled drawdown than 25%. Its unattended weak event-loss miss is an additional reason this is not a production approval. No tested allocation satisfies all payback, hype-liveness and loss goals.

The fixed team address is `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`. It receives the plain-address launch remainder temporarily and publicly transfers the **entire** endowment immediately after game deployment. Once funded, no team token allocation or recovery right remains. Publish transfer and Endowed receipts. Before the transfer, custody remains a trust assumption the required plain remainderTo format cannot remove.

[Exact launch/deploy procedure](docs/launch-v31.md) gives all constructor arguments and responsibilities. In brief: custom token/hook first; application A deploys Params, GameRegistry, RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim; application B deploys FeeRouter, GridOperator, Season, FarmEngine. Anyone authenticates the ten module enrollments. The team binds the hook once, transfers/funds endowment, and the launch operator performs the initial advance. Permissionless bots flush fees, capture entropy, settle, buy and finalize; team and bounty recipients pull their own credits. Params has three constructor arguments, Registry eight, every module one, hook five. Constructors make no external calls.

The single-file hook is [launch/V4Market.sol](launch/V4Market.sol), independently compiled with 0.8.26 to 9,954 runtime bytes. All application runtimes are under EIP-170. The registry uses exact pinned module artifacts, so changing compiler settings/source metadata requires regenerating the pins and reviewing before launch. A production factory prediction was checked against an existing live deployment and matched; no production transaction was sent.

Current IMD documentation/capabilities expose schedule.topup at 0.5 IMD/run on Ethereum, not through the Robinhood contract intake. FeeRouter cannot turn its heartbeat ETH into those runs. Any external payer may buy them; team-funded cost is 70 IMD per 35 days at four runs/day, illustrated as 0.24157 ETH plus actual purchase/payment/bridge fees. No owner withdrawal is added to disguise that operational requirement. More frequent swarm runs multiply this cost. See [evidence](artifacts/v31/evidence/launch-and-cost-facts.json) and [operating regulator](regulator.md).

## Validation and review

* `forge build`: passed with pinned Solidity 0.8.26.
* `forge test -vv`: **123 passed, 0 failed, 1 skipped** across 25 suites. The skip is the existing optional network fork; no environment or network is needed for the ordinary suite.
* `forge fmt --check`, exact module-pin check and `git diff --check`: passed.
* Python: 14 unit tests and five retained simulation self-checks passed. All 117 full economic runs completed: 48 baseline, 48 funded, eighteen stress and three boundary checks. Maximum token conservation error was below 0.000203 token per billion-token system.
* Fuzz tests ran 256 cases; invariant campaign ran 128 × 64 calls. Gas tests include typical/dense farm processing, real v4 buyback, plan/paid/starter entropy, single-participant scoring and three-winner finalization with a prize.

[Validation and contract sizes](artifacts/v31/validation.json) record the checked configuration. The largest application runtime is FarmCore at 23,527 bytes, below 24,576. The standalone hook is 9,954 bytes. Protected configuration/dependency paths were not changed. No Slither/Mythril, live deployment, or post-deployment verification is claimed.

Meaningful tests cover endowment conservation/no withdrawal/exact release bounds and real mining, every bounty's useful-work/replay/authority/balance caps, preserved starter entropy despite full inventory, hook escrow/rollback/one-time binding, pause scope/expiry, exact CREATE2 graph enrollment, runtime-identical alternate constructors, v4 settlement and the retained v3 suite. The local tests are not a substitute for independent release review or a live liquidity rehearsal.

A second contributor reviewed the changes with fresh context. Its medium finding on buyback pressure accounting was fixed and regression-tested against a real local PoolManager. It reviewed the registry and final bounded heartbeat changes; no high/medium finding remains open. [Review record](docs/review-v31.md) distinguishes execution from static inspection. Future-block randomness remains sequencer-influenced v3 randomness, not a VRF; missed capture, absent plans, liquidity shape, inactive farms and gas prices remain operational/economic risks.
