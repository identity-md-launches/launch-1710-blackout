# BLACKOUT v3.8 — launch kit against the real IMD platform (source only)

Nothing was deployed, broadcast, bought or signed. This supersedes `launch-v37.md` where they differ; everything not mentioned here is unchanged from v3.7. The platform facts come from research job b94e6839 ([copy](docs/research/b94e6839-platform-report.md)). X: https://x.com/IMDBlackout · https://playblackout.xyz · https://playblackout.xyz/freepack.

## What changed in v3.8 and why

| Blocker (research id) | v3.8 answer | Status |
|---|---|---|
| C2 launch numbers cannot be reserved | No constructor takes a launch coordinate. `SwarmDesk.bind`, `V4Market.bindFeeRouter` and `EndowmentEscrow.forward` take the recorded `(launchNumber, index)` pairs as call arguments and prove them with `ProjectFactory.predictContract`, its registry `isRecorded`, and the pinned creation-code hashes (`SwarmCode.REGISTRY`, `SwarmCode.PARAMS`, `ModuleCode`). The Desk's binding word keeps only `heartbeatBps`; the coordinate bits must be zero. `gameConfigHash` no longer includes the token or Params address: `keccak256(abi.encode(starterRoot, freeRoot, snapshotBlock, endowment))`. | Done, tested |
| C6 / Q1 endowment to a predicted address | `EndowmentEscrow` (ownerless, `src/EndowmentEscrow.sol`) is the token launch's `remainderTo`. Its single exit `forward(...)` sends the whole balance once to `registry.module(0)` after proving the registry is the one the pinned Desk bound to, that both registry and pool are factory CREATE2 results of pinned code at recorded coordinates, and that `Params.swarmWallet` is the Desk. `RewardPool.fundEndowment` already accepts a plain transfer of at least the principal and starts the drip. | Done, tested |
| C3 hook fee | `V4Market` accepts only the platform pool fee `12500`; its `PoolKey`, `poolId` and `key()` match the real pool. The constructor is static: `$poolManager`, `$token`, network recipient, `12500`, tick spacing `60`, `$factory` (LaunchFactory, which initializes the pool and is checked in `afterInitialize`), the ProjectFactory literal, the Desk literal and the config hash. **Remaining:** the hook still adds its own 0.25% `NETWORK_BPS` and routes half of the base fee to the team through `FeeRouter._base`. Both must go before launch (see "Open items"). | Partly done |
| C1 schedules cannot deliver cross-chain | `SwarmDesk.submit(attestation, signature)` is a permissionless relay with exactly the delivered-result checks (attester signature in the Desk's own domain on 4663, pinned question hash, context window, panel, slot and epoch freshness, once per UUID). Schedules are bought on Ethereum with `consumer {chainId: 4663, verifyingContract: Desk}` and no `deliver`; the keeper fetches `GET /oracle/requests/:id/attestation` and relays. `askBackup` (Robinhood Intake, donated IMD) is unchanged. | Done, tested |
| Event policy fixed at 9000 | The attested answer chooses kind and severity. The Desk clamps severity to `SEVERITY_MIN..SEVERITY_MAX` = 5000..7000 (GridOperator's own floor is 5000; lowering it to 3000 requires a GridOperator change and a module re-pin, deferred so the 14 module pins stay valid). Positive-event quotas in GridOperator are unchanged. | Done, band narrower than the brief's example |
| C5 toolchain | `foundry.toml` is protected in this job (`via_ir = true`, no `bytecode_hash`). The verifier builds with `viaIR false`, `bytecode_hash none`, solc 0.8.26. **Open:** change the two lines, rebuild, re-run `tools/pin_module_code.py` then `tools/pin_swarm_code.py`, and confirm every runtime is under 24,576 bytes without via-IR (FarmCore is at 24,330 with via-IR and will need splitting). | Open, needs a config change this job may not make |
| Q3d team swap income | Comes from the platform's 1% to the paying wallet via `LaunchFactory.claimFees(launchNumber)`; no `setRequester` is needed when the paying wallet is the team wallet `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`. **Open:** remove the team half from `FeeRouter._base` (module change, re-pin). | Open |
| Q8 snapshot | Identity MD NFT is on Ethereum mainnet (chain 1) `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d`, ERC-721, 2000 token ids 0–1999. `snapshotBlock` is an **Ethereum** block number everywhere (constructor, UI, proofs). | Documented |

## Deployment order (Sepolia 11155111 rehearsal first, then Robinhood 4663)

All addresses below are literals known at the time each manifest is written; none is a prediction.

1. **Freeze inputs (requester).** Starter root and free-pack root from the Ethereum snapshot block (chain 1, IDMD contract above), endowment 200,000,000e18, `heartbeatBps` 200. Build `gameConfigHash = keccak256(abi.encode(starterRoot, freeRoot, snapshotBlock, endowment))`.
2. **Launch 1 — SwarmDesk bootstrap** (`launch.open`, `onchain:"evm_contracts"`, 1 contract). Fourteen static words from `node tools/swarm_constructor_args.mjs docs/oracle-v37/oracle-config.json binding.json` where `binding.json` has `factory` = ProjectFactory `0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e`, all four coordinates `0`, `heartbeatBps 200`, `heartbeatCap 1000000000000000000`, and the config hash. Record `DESK` from `GET /launches/:id`.
3. **Launch 2 — EndowmentEscrow** (`evm_contracts`, 1 contract): `EndowmentEscrow(ProjectFactory, ProjectFactory registry 0xf52bbe066b7ad2d28c2195d066ea08dcbca88406, DESK)`. Record `ESCROW`.
4. **Launch 3 — token** (`launch.open`, `onchain:"univ4_hook"`, `chainId 4663`, `pairWith "eth"`, `economics {poolBps: 7000, remainderTo: ESCROW}`). Hook `V4Market` constructor: `$poolManager`, `$token`, network recipient (platform `LaunchFees.feeRecipient` once the network share is folded in; see open items), `12500`, `60`, `$factory`, ProjectFactory, `DESK`, `gameConfigHash`. Opens at 10 ETH FDV by policy. Record `TOKEN`, `HOOK`, token launch number `N_T`.
5. **Launch 4 — job A** (`evm_contracts`, 8): `Params(DESK, 200, 1e18)`, `GameRegistry(TOKEN, $contract[0], HOOK, starterRoot, freeRoot, snapshotBlock, 200000000000000000000000000, ProjectFactory)`, then RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim, each taking the registry. If the manifest cannot reference a same-launch contract, split: Params alone, then Registry + 7 modules. Record `N_A`, indices.
6. **Launch 5 — job B** (`evm_contracts`, 8): FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards, each taking the registry. Open it as `workflow.open` together with the site job so the UI ships against live addresses. Record `N_B`.
7. **Wiring (any wallet; the keeper has these as commands, see `keeper/README.md`):**
   1. `GameRegistry.register(role, launch, index, creationCode)` for all 14 roles.
   2. `SwarmDesk.bind(REGISTRY, registryCode, paramsCode, N_A, registryIndex, N_A, paramsIndex)`.
   3. `V4Market.bindFeeRouter(FEE_ROUTER, N_A, registryIndex)` — after `Desk.bind`, because the hook accepts only the Params of the registry the Desk bound to.
   4. `EndowmentEscrow.forward(REGISTRY, N_A, registryIndex, registryCode, N_A, poolIndex, poolCode)`.
   5. `RewardPool.fundEndowment()`.
   6. Start the keeper; buy the two schedules on Ethereum with `consumer {chainId 4663, verifyingContract DESK}` and no `deliver`; periodically `LaunchFactory.claimFees(N_T)`.
8. **Gas:** each launch is one transaction. Job A and B were measured locally at under 8M gas each in the rehearsal script; at Robinhood's observed gas price this is far below the 0.01 ETH per-launch ceiling, but confirm on the Sepolia rehearsal receipt before mainnet.

## Objective texts (each under 8000 characters, paste verbatim into the paid step)

**Bootstrap:** "BLACKOUT v3.8 SwarmDesk bootstrap on Robinhood Chain (4663). Deploy exactly one contract, SwarmDesk from the accepted v3.8 commit, with the fourteen static constructor words from the reviewed oracle-config and binding files (all launch coordinates zero, factory 0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e, heartbeat 200 bps, cap 1e18, gameConfigHash as reviewed). No owner, key, upgrade, token action or placeholder. Record the address. Project: https://playblackout.xyz, https://x.com/IMDBlackout."

**Escrow:** "BLACKOUT v3.8 EndowmentEscrow on Robinhood Chain (4663). Deploy exactly one contract, EndowmentEscrow(ProjectFactory 0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e, ProjectFactory registry 0xf52bbe066b7ad2d28c2195d066ea08dcbca88406, SwarmDesk <DESK>). It is ownerless and its only function forwards its whole balance once to the authenticated RewardPool. Record the address; it is the remainderTo of the token launch. https://x.com/IMDBlackout"

**Token:** "BLACKOUT token launch on Robinhood Chain (4663), univ4_hook, pairWith eth, poolBps 7000, remainderTo <ESCROW>. Hook V4Market from the accepted v3.8 commit with static constructor args ($poolManager, $token, <network recipient>, 12500, 60, $factory, 0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e, <DESK>, <gameConfigHash>). The hook has no owner. Paying wallet 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007 receives the platform 1%. https://x.com/IMDBlackout"

**Job A / Job B:** as in `launch-v37.md` with the v3.8 constructor lists above, each ending with "Record every address and index; no token operations, owner or upgrade. https://x.com/IMDBlackout". Job B as `workflow.open` chained with the site job.

## Economy check (Balanced, 10 ETH FDV, swarm 10% claimable after 1 hour)

Fixed by policy: 1,000,000,000 tokens, 70% in the pool against single-sided liquidity at 10 ETH FDV, 20% endowment via the escrow, 10% swarm. The stepped buy tax (90/50/25% by ten-minute steps, 100% to reward buys) is unchanged. The one new input versus `artifacts/v35/simulation.md` is up to 100,000,000 tokens of swarm sell pressure from hour one. At 10 ETH FDV that is at most 1 ETH of notional at the opening price, which the progressive sell surcharge (pot share as in v3.6) absorbs; the sell surcharge and the 1% hook share on every swap keep funding reward buys. The full Balanced re-run with these inputs was **not** executed in this job (time budget); run `python3 sim/run_v35.py` with `fdv_eth=10`, `swarm_unlock_hours=1`, `swarm_sell_fraction` 0.25–1.0 and report launch tax collected, maximum drawdown, payback and team ETH (team ETH now equals 1% of swap volume via `claimFees` plus 10% of packs and lobby sales).

## Open items before any launch

1. Fold `NETWORK_BPS` into the LP fee (set to 0, drop `withdrawNetwork`) and make the hook's post-launch buy charge exactly 1% to rewards (`projectBps() = 100`, `FeeRouter._base` 100% to `rewardETH`). Update the fee assertions in `test/Market.t.sol`, `test/V33.t.sol`, `test/V34.t.sol`, `test/V4Integration.t.sol`, `test/HookBinding.t.sol`. FeeRouter is a pinned module: re-pin afterwards.
2. Set `via_ir = false` and `bytecode_hash = "none"` in `foundry.toml`, split FarmCore if it exceeds 24,576 bytes without via-IR, re-pin `ModuleCode` and `SwarmCode`, rebuild, re-run everything.
3. GridOperator severity floor 3000 if the swarm should go below 5000 (module re-pin).
4. Sepolia rehearsal: read the attested `creationCodeHash` values, the `afterInitialize` sender, and gas against 0.01 ETH per launch.
5. Second-contributor review of this diff was not performed inside this job's time budget; it is required before release.
