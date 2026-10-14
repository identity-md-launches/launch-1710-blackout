# BLACKOUT implementation report

Date: 2026-10-10. Source only; **no deployment, token creation, transaction broadcast or funded-wallet action**.

The supplied workspace contained project history and the pinned references, but no prior game implementation. This deliverable provides a root Foundry project pinned to Solidity **0.8.26**, ordinary vendored dependencies, contracts, deployment scripts, success/failure/fuzz/invariant tests, starter-proof tooling, and a deterministic economy reconstruction.

## Implemented behavior

- Immutable ERC-1155 game with GPU, ASIC, Power Supply, Cooling, Motherboard and Router equipment, plus Room Keys. Each equipment type mines alone. Rooms hold one of each type, and all requested set bonuses and the 40% set-hash cap are Params.
- ETH packs, reward-funded token packs, beta limits, fixed rarity, mint-epoch bonuses, future-native-block resolution and deterministic expiry. Starter claims use an immutable snapshot root, one entitlement per tokenId, a fixed claim window, and restricted transfers. Merges mint only through PackSale.
- Player item custody, placement, reward claims, oldest-first withdrawal tax, electricity, repair, overclock, lobbying, single-level referrals, and Generator principal lock/unlock. Emission is funded by existing pool tokens and reserves outstanding liabilities before allocation; it cannot mint the game token.
- The reports' pack/base-fee/excess-sell-fee/lobby splits, permissionless buybacks and donations, fixed fee entitlements and pull withdrawals. Only the current team address changes its own future recipient. Heartbeat and swarm addresses are immutable constructor inputs.
- Grid event commitments, bounded type frequencies, district cooldown, lobbying weights, herald letters, and permissionless resolution/inspection payouts. Only swarm changes bounded Params, at most 10% per key per 24 hours, and controls the bounded PackSale-only pause. There is no owner, upgrade, general pause, pool sweep or arbitrary mint role.
- Optional v4 combined launch hook and adapter, with total sell fee capped at 15% including the network share, a 30-minute arithmetic ETH/token TWAP, same-block manipulation resistance, permissionless output-checked buybacks, authenticated callbacks and a CREATE2 hook-address factory.

The exact assumptions and API are in [README.md](README.md) and [docs/design.md](docs/design.md). The new type probabilities, interpretation of the set cap, highest-only rarity triple, free first room, and seven-day Generator pledge are explicitly identified implementation choices. Neither report defines Generator economics.

## Verification

Final local results are recorded in [artifacts/verification.json](artifacts/verification.json), with source hashes and toolchain version:

| Check | Result |
|---|---|
| `forge build` | Passed with pinned Solc 0.8.26; compiler successful; Foundry lint warnings remain |
| `forge test -vv` | **68 passed, 0 failed, 1 optional fork test skipped**; 13 suites |
| Stateful invariants | 128 runs, 8,192 actions, zero action reverts; custody/hash and token/backing checks passed |
| `forge fmt --check` | Passed |
| Python simulation checks | 5 passed |
| Python Merkle tooling checks | 2 passed |
| Explicit Robinhood fork smoke | **1 passed, 0 failed, 0 skipped** |
| Fresh source copy, offline, four threads, fixed alternative fuzz seed, environment containing only PATH | **68 passed, 0 failed, 1 optional fork test skipped** |

The fresh-copy run excluded prior artifacts, caches, pinned inputs and scratch tests; see [artifacts/offline-verification.json](artifacts/offline-verification.json). All 13 application runtimes are below 24,576 bytes; the largest is FarmRewards at 21,782 bytes. [Runtime sizes](artifacts/runtime-sizes.json) exclude script/test contracts. Application bytecode has no unresolved library links. The aggregate deployment script is intentionally not an on-chain deployable factory.

The main reproduction commands are:

```sh
forge build
forge test
forge fmt --check
python3 sim/blackout_sim_v2.py --check
python3 -m unittest discover -s test/python -v
```

Coverage includes role failures, invalid/duplicate/expired pack and event actions, Merkle rejection and repeat claims, all equipment types and room combinations, exact fee splits, pausing and unpaused exits, parameter bounds/step limits, FIFO tax, full tax redistribution, referral restrictions, reservation solvency, long-idle catch-up, wallet-funded revival, inspection finalization, failing receivers/tokens/adapters, reentry attempts, hook fee/oracle behavior, and real vendored Uniswap v4 PoolManager settlement. Stateful invariants track token conservation, backing of pending liabilities, mining indices and NFT custody. Scripts are tested through explicit configuration; tests do not read or modify environment variables.

The explicit Robinhood fork run **passed one RPC-backed native ArbSys number/hash smoke test** with no skip. An earlier direct RPC probe returned HTTP 403; both outcomes are recorded in [artifacts/rpc-probe.json](artifacts/rpc-probe.json). [Robinhood's network documentation](https://docs.robinhood.com/chain/add-network-to-wallet/) confirms the mainnet endpoint and chain ID. The smoke test reads native precompile results through RPC and replays them into Foundry's local EVM. Offline tests separately exercise native-versus-ancestor block semantics and a real local v4 PoolManager. Full integration against the eventual launch token, market, liquidity and immutable configuration remains pre-release work.

## Reconstructed v2 simulation

**The original v2 simulation source was absent** from the repository and linked research trees. I rebuilt it from the stated v2 assumptions, carrying forward its v1 inputs, and included the six equipment types and set bonuses. The retrieved report SHA-256 hashes match both supplied artifact identifiers. [Simulation assumptions](docs/simulation-assumptions.md) distinguish source inputs, daily approximations and new choices; [the generated tables](artifacts/simulation.md) are reproducible from `sim/blackout_sim_v2.py` with seed 20261010.

The 35-day reconstruction currently produces:

| Scenario | Week-1 / week-4 finite mean payback | Week-4 no payback by 120 days | Reconstructed stall | Team ETH / routed inflow |
|---|---:|---:|---:|---:|
| Steady | 26.8 / 34.9 days | 7.6% | Day 34 | 13.134 / 14.97% |
| Hype | 39.1 / 50.7 days | 20.3% | Day 13 | 21.877 / 14.97% |
| Weak | 44.8 / 60.6 days | 27.8% | Day 16 | 3.013 / 14.86% |

These are conditional results for still-active paid farmers, not promised returns. Quitters and non-paying outcomes are reported separately. The model checks token conservation every day; maximum observed floating-point residual across the three primary runs was approximately 0.000011 whole tokens out of one billion. Steady's day-35 pool is about 308.98 million tokens with sets versus 309.17 million without sets. Sensitivities cover lower virtual liquidity, stronger selling and no swarm sales.

**These results do not reproduce or validate the original report's numerical claims.** Whole-item luck, whole token packs, placement, survivor handling and projection choices change the results. The model is a daily economic reconstruction, not an EVM trace. In particular, a positive token pool does not establish sustainable player returns or redeemable ETH in a pool with virtual liquidity.

## Launch inputs and responsibilities

No real recipient, owner, token, PoolManager or snapshot address has been invented. Test placeholders exist only in tests. Deployment scripts require environment values for the actual token, swarm, heartbeat, initial team, market, launch timestamp, snapshot root/block and deployment account. The optional hook additionally requires the actual PoolManager, network recipient, pool settings, factory and salt. All linked application addresses must be planned before immutable deployment. Every application constructor has fewer than 16 arguments and makes no external dependency call.

The launch operator must verify plain token-transfer semantics, the immutable address graph, snapshot provenance, market configuration, hook compatibility and liquidity. Swarm operates events/heralds and bounded Params; permissionless keepers resolve commits, advance accounting, refresh farms, execute buybacks, and submit/finalize inspection results. Fee recipients claim their own credits. There is no operator recovery route for pool funds or mistaken immutable configuration.

The supplied reports leave IMD launch-hook compatibility open. The optional combined hook charges the policy fee itself and must not be layered on another fee hook. Its exact-input-only and zero-LP-fee constraints, initialization and 31-minute TWAP warm-up are documented. No existing token or launch hook was changed.

## Review limits

[docs/security-review.md](docs/security-review.md) records the implementation-author adversarial review and repaired defects. **No independent audit was performed.** Passing tests carry no independent authority. Outstanding release concerns include sequencer-influenced future-block randomness, Sybil behavior, stale farm refresh snapshots, intraday durability approximation, catch-up gas, external token/market assumptions and full application integration on the actual chain. A separate contributor review and that configured application integration remain pre-release work.
