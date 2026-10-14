# BLACKOUT v3.18 — final L1–L4 launch runbook

Source only; no transaction is authorized by this change. This runbook replaces earlier M1–M13 deployment objectives. Use the accepted v3.18 source commit in `identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood`, based on `e17f0ef7bd7d188949eb4dc91e3eb0540c94cbf3` (v3.17). **v3.18** (L1 is deployed as launch 1628, before L2) fixes L2 import-audit a3749636 (medium) in `src/V4Market.sol` only: a buy whose `sqrtPriceLimitX96` stopped the swap early paid the launch tax and the 1% share on ETH the pool never consumed (10 ETH specified, about 0.5 ETH swapped, 9 ETH taken). Buys now revert `PriceLimitedBuy` unless they carry the extreme bound `BUY_PRICE_LIMIT = 4295128740` (MIN_SQRT_PRICE + 1, what v4 routers send), and `afterSwap` reverts `PartialFill` unless the pool consumed exactly the taxed input; full-fill buys pay exactly as before. The audit's low (tax taken from the PoolManager float in beforeSwap) is accepted in `docs/accepted-v318.md`. **Only the V4Market creation hash changed** (`0x8d6e…92a4`, runtime 21,534); the other 18 are byte-identical to e17f0ef, so the deployed L1 and the L3/L4 pins are unaffected. `launch/V4Market.sol` is re-flattened. v3.17 (the deployed L1's source) is described next. **v3.17** (before L2; L1 is redeployed) ports the sticky `farmDaily` basis fix from launch 1593 commit `1e4490923f20a389ecb6be136121f4eea65db3b1` (`src/FarmRewards.sol`, `test/FarmDailyBasisV317.t.sol`) and fixes pre-token audit 339b6b19 (1 medium, 3 low: Enhancement lapse instead of re-arm, GridOperator re-arm instead of a precomputable fallback seed, `Economy.unlock` never blocked by liveness, destroyed items leave the committed weight next epoch); its info 5–8 and the L1 judge items are accepted in `docs/accepted-v317.md`. Changed source: `src/FarmRewards.sol`, `src/Enhancement.sol`, `src/GridOperator.sol`, `src/Economy.sol`, `src/FarmCore.sol`, `src/interfaces/IGame.sol`, the regenerated `src/lib/ModuleCode.sol` / `src/lib/SwarmCode.sol` pins and the re-flattened `launch/V4Market.sol`; `foundry.toml` and `src/lib/Robinhood.sol` are untouched. **Nine of the 19 creation hashes changed**: SwarmDesk, EndowmentEscrow, V4Market, GameRegistry (pins), FarmRewards, FarmCore, GridOperator, Economy, Enhancement; the other ten (Params, RewardPool, FarmItems, PackSale, StarterClaim, FeeRouter, Season, FarmEngine, Civic, Billboards) are byte-identical to v3.16. Constructor words, the eight Desk words and the binder are unchanged. History: v3.16 changed only `src/SwarmDesk.sol` (import audit 10bfac6d): the Desk takes an eighth constructor word, the **binder** `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007` (the project wallet, not an IMD protocol address), and `bind` reverts `Unauthorized` for any other caller; every v3.15 proof (registry/Params pins and coordinates, frozen config, hook echoes, `LaunchFactory.positionOf` record with currency0 == 0, currency1 == token, hooks == market) is unchanged. Every other creation hash was byte-identical to v3.14/v3.15 until v3.17. **NO SOURCE CHANGES** in any launch job.

Site: https://playblackout.xyz

## Frozen inputs and build

Build exactly with this repository's unchanged `foundry.toml`: solc 0.8.26, optimizer true / 200 runs, Cancun, viaIR false, bytecode_hash none. `out/` and `out-launch/` must contain identical creation code. Run `python3 tools/pin_module_code.py --check`, `python3 tools/pin_swarm_code.py --check`, and `node tools/check_deploy_gate.mjs` before handing off. The deploy-gate tool takes the JSON plan (`node tools/check_deploy_gate.mjs docs/launch-v314-plan.json`, also its default), never this markdown runbook: it walks every `constructorArgs` array of a JSON launch document and refuses any literal IMD protocol address. `docs/launch-v314-plan.json` is the machine-readable source plan, not a platform manifest; the platform prepares the actual manifest separately.

GAME_CONFIG_HASH is unchanged: **0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3**. Endowment is **200000000000000000000000000**. The existing private STARTER_ROOT, FREE_ROOT and SNAPSHOT_BLOCK remain unchanged and are supplied only for L3; they were already symbolic inputs in this repository. Before L3, verify `keccak256(abi.encode(bytes32 STARTER_ROOT, bytes32 FREE_ROOT, uint256 SNAPSHOT_BLOCK, uint256 ENDOWMENT))` equals that exact hash. A mismatch stops the launch; never substitute rehearsal roots or alter the commitment.

`<L1_SWARM_DESK>` and `<L1_ENDOWMENT_ESCROW>` are now recorded: launch 1628 deployed SwarmDesk `0x5cb0686a4475d1f8a6c6e5240579080a4a05b609` and EndowmentEscrow `0x11947494c0ba91508eb7409648193818c36521fb`; the L2 objective carries them literally. `<L2_TOKEN>`, `<L2_V4MARKET>` and `<L3_GAME_REGISTRY>` mean the exact recorded output addresses of the earlier launch. `<STARTER_ROOT>`, `<FREE_ROOT>`, `<SNAPSHOT_BLOCK>` mean the approved private preimage, not new choices. These are runbook substitutions; resolve them before submission. `$contract:Name` is a same-launch named reference; `$poolManager`, `$token`, `$factory` remain literal platform placeholders in L2. Do not replace those placeholders with IMD protocol address literals.

All eight protocol addresses are pinned in `src/lib/Robinhood.sol`. The Desk takes no protocol-address argument (its eighth word is the project-wallet binder, which the constructor only requires to be nonzero; no code is read at construction); the escrow takes only the Desk; GameRegistry takes seven words without a factory word; V4Market takes seven words with the allowed platform placeholders. The supplied manager and launcher are platform-injected; the application factory is compiled in. Every constructor runs without external code. No owner, upgrade, arbitrary withdrawal or protocol-setting setter is added.

## Expected creation hashes

Creation-code hashes exclude constructor words. CREATE2 prediction uses the creation code **plus** ABI-encoded constructor words; the rehearsal labels these separately as `initCodeHash`. The platform supplies the standard token for L2; it is not a BLACKOUT source contract and has no newly invented source hash here. The hook's standalone flattened `launch/V4Market.sol` compiles to the same creation bytes as `src/V4Market.sol`.

| Launch | Contract | Creation-code hash (without constructor words) | Runtime bytes |
|---|---|---|---|
| L1 | SwarmDesk | `0x1d8e1afa90ba7a4c436fa2406f52743c97f7e6d9add372516144cadcb0795879` | 22226 |
| L1 | EndowmentEscrow | `0xe7a48446223ad53d50a9a9372c5552b70fb94e4f03c0f9f45298f7e5d2036368` | 5008 |
| L2 | V4Market | `0x8d6e02398e351aa4c28486a92d7ec60baf7edc67ccaaa88eed4bd61e9b9092a4` | 21534 |
| L3 | Params | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` | 3118 |
| L3 | GameRegistry | `0xe41104da4edfb9a746e9080ce7b1885b5fe7609674a3a68fc5addbfd5a871531` | 2864 |
| L3 | RewardPool | `0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de` | 4234 |
| L3 | FarmRewards | `0xfa1a4087722916aeefae66aaf3400299a5e4cb8f4fc8e516a17cec7754e07506` | 17002 |
| L3 | FarmCore | `0xc390b07ef7a9ab65bef3a1ec3b39c1a16e117543c9565fedc9342526aa57aa47` | 22361 |
| L3 | FarmItems | `0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76` | 13861 |
| L3 | PackSale | `0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a` | 12538 |
| L3 | StarterClaim | `0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90` | 5477 |
| L4 | FeeRouter | `0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af` | 11750 |
| L4 | GridOperator | `0x931bdfaeeacadb7c8014ce1411671d0045013c2b373d95bbf0bb83dfce0b7c74` | 9519 |
| L4 | Season | `0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83` | 11933 |
| L4 | FarmEngine | `0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c` | 10783 |
| L4 | Economy | `0x105f9f29d79579fa33ff8e11d4d86847dd7d9f59bd681500553a3844db50ccc9` | 11097 |
| L4 | Enhancement | `0x31242676dd3a728a2ad32a5cb300166020e87831b0f547756fa0bab88cedea38` | 7112 |
| L4 | Civic | `0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2` | 13019 |
| L4 | Billboards | `0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60` | 6031 |

## Final launch objectives

Each complete objective below includes its exact ordered constructor words, expected creation hashes and accepted findings. Keep the order and named references. Substitute only the bracketed prior outputs/private preimage values described above.

### L1. Desk + escrow

**Deployed** as launch 1628: SwarmDesk `0x5cb0686a4475d1f8a6c6e5240579080a4a05b609`, EndowmentEscrow `0x11947494c0ba91508eb7409648193818c36521fb` (v3.17 creation hashes, unchanged in v3.18). Do not resubmit; the objective is kept for the record.

```text
BLACKOUT v3.17 L1 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.17 commit (deployed as launch 1628; identical creation hashes in v3.18) of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy SwarmDesk at index 0 then EndowmentEscrow at index 1 in ONE evm_contracts launch. Resolve the escrow Desk argument as $contract:SwarmDesk from this same launch. Return both addresses, their indices and this single launch number.
The Desk takes eight static words. The eighth is the binder 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007: the project wallet (not an IMD protocol address) and the only account that may call bind; any other caller gets Unauthorized (import audit 10bfac6d). The Desk is bound after L3 with bind(REGISTRY, registryCreationCode, paramsCreationCode, N_A, 1, N_A, 0, N_TOKEN), signed by that wallet: the last word is the recorded L2 launch number, and bind reads LaunchFactory.positionOf(N_TOKEN) (compiled-in 0xa25b…4645) and refuses any registry whose market is not the hook that record names for the registry's token. A market that only echoes desk(), token() and gameConfigHash() cannot bind. Keep the L2 launch number with the L1/L3 outputs for the keeper (wiring.tokenLaunch).
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] SwarmDesk ["0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000","5391989333430298100116863486635657822062725418115979424500284366258177","0x2fc5a57f2c5f7bc083ea8ac5016234f1a0b1c68a514e5d921956cc57948534ef","0xc13efed8438aab53ea052a4507def2dc4ce9856765520dfa28c66daa59cfc11d","0x00e69e4445c7ca7256338293f9f9cea439fd2beb1959d1d43ebec7b14493e2f6","0xc0ae7511b06744cf7ccadc6b60ff9ff96cb7234cf32988850df33324861cc8df","0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3","0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007"]
Creation hash: 0x1d8e1afa90ba7a4c436fa2406f52743c97f7e6d9add372516144cadcb0795879
[1] EndowmentEscrow ["$contract:SwarmDesk"]
Creation hash: 0xe7a48446223ad53d50a9a9372c5552b70fb94e4f03c0f9f45298f7e5d2036368
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (verbatim and in full in docs/accepted-v318.md; abridged here to the objective limit):
- Accepted — RewardPool shortfall: repair a shortfall with a plain token transfer; `donate` is not the repair path.
- Accepted — Exact-input swaps only: V4Market rejects exact-output swaps; request exact input with a minimum output. v3.18: a buy must carry the extreme sqrtPriceLimitX96 4295128740 (`PriceLimitedBuy` otherwise) and afterSwap refuses a partial fill (`PartialFill`), so tax is never paid on unconsumed ETH.
- Accepted — a3749636 low, manager float: beforeSwap takes the buy tax from the PoolManager before the swapper settles; the live Robinhood PoolManager holds about 24,500 ETH, far above any single buy's tax.
- Accepted — `spot()` bounds: zero, underflowed or above-1e40 prices revert; keep the pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: compiled in, no owner rotation; migration needs a reviewed source release.
- Accepted — Answers between job A and job B: stored after L3, executable only once all L4 modules are registered.
- Accepted — Future-block randomness: native L2 block entropy with capture/re-arm rules, not VRF; enhancement attempts lapse to their worst outcome instead of re-arming (v3.17).
- Accepted — Reserved Params keys (docs/params-keys-v313.md): no gameplay effect; proposals may still consume cooldown.
- Accepted — M-2 matching twin: only the pinned binder can bind; the binder key could still choose a proven twin (docs/m2-trust-assumption.md).
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by a byte-identical copy: same pinned code, same registry; keeper registers every role immediately and verifies module(role).
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: keeper finalizes then rolls over weekly; a rollover only moves the pot to later players.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: a reverting sell rolls the sweep back; it repeats on the next success.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: at most about 54 bps in the player's favour, self-triggered.
- Accepted — 031c93c4 info 6, deploy-gate tool takes only the JSON plan; the runbook says so since v3.15.
- Accepted — 339b6b19 info 5, `Civic.claimWar` rounding dust: wei left by integer splits never leave the game.
- Accepted — 339b6b19 info 6, no max-cost bound on openPack/buyTokenPack: price read at execution; bounded by approval or ETH minimum output.
- Accepted — 339b6b19 info 7, unused minter/caller permissions: every allowed caller is a pinned module of this registry.
- Accepted — 339b6b19 info 8, dead fields: written, never read; no gameplay or security effect.
- Accepted — L1 judge, `PackSale.buyPacksFor` gifting: packs may be bought for another farm; value only flows in.
- Accepted — L1 judge, one-shot escrow: `forward` runs once to the proven RewardPool; no retry or admin by design.
- Accepted — L1 judge, Festival band: attested severities are clamped to 5000–7000; the fallback table keeps 10000.
- Accepted — L1 judge, `Economy._insert` 33-tie lock griefing: deeper insertion reverts atomically; no funds at risk.
- Accepted — L1 judge, stream-0 answers before role 1: stored, executed only after wiring completes.
- Accepted — Binder liveness: one-time bind by 0x6d51…d007; a lost key leaves the Desk unbound and the endowment in escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L2. Token + hook

```text
BLACKOUT v3.18 L2 on Robinhood Chain (4663). NO SOURCE CHANGES. L1 is deployed (launch 1628): SwarmDesk 0x5cb0686a4475d1f8a6c6e5240579080a4a05b609, EndowmentEscrow 0x11947494c0ba91508eb7409648193818c36521fb.
Source: accepted v3.18 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy the platform token plus V4Market hook using onchain univ4_hook, pairWith eth, economics poolBps 7000 and remainderTo 0x11947494c0ba91508eb7409648193818c36521fb (the deployed L1 EndowmentEscrow, launch 1628). Platform pool fee 12500, tick spacing 60. Paying wallet 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007 receives the platform 1% via LaunchFactory.claimFees; the platform keeps 0.25%. The hook adds its 1% rewards share after the stepped launch tax and its existing sell surcharge. Omit owner and initialMarketCapWei. Return token, hook, launch number and pool key.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] V4Market ["$poolManager","$token","12500","60","$factory","0x5cb0686a4475d1f8a6c6e5240579080a4a05b609","0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3"]
Creation hash: 0x8d6e02398e351aa4c28486a92d7ec60baf7edc67ccaaa88eed4bd61e9b9092a4
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (verbatim and in full in docs/accepted-v318.md; abridged here to the objective limit):
- Accepted — RewardPool shortfall: repair a shortfall with a plain token transfer; `donate` is not the repair path.
- Accepted — Exact-input swaps only: V4Market rejects exact-output swaps; request exact input with a minimum output. v3.18: a buy must carry the extreme sqrtPriceLimitX96 4295128740 (`PriceLimitedBuy` otherwise) and afterSwap refuses a partial fill (`PartialFill`), so tax is never paid on unconsumed ETH.
- Accepted — a3749636 low, manager float: beforeSwap takes the buy tax from the PoolManager before the swapper settles; the live Robinhood PoolManager holds about 24,500 ETH, far above any single buy's tax.
- Accepted — `spot()` bounds: zero, underflowed or above-1e40 prices revert; keep the pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: compiled in, no owner rotation; migration needs a reviewed source release.
- Accepted — Answers between job A and job B: stored after L3, executable only once all L4 modules are registered.
- Accepted — Future-block randomness: native L2 block entropy with capture/re-arm rules, not VRF; enhancement attempts lapse to their worst outcome instead of re-arming (v3.17).
- Accepted — Reserved Params keys (docs/params-keys-v313.md): no gameplay effect; proposals may still consume cooldown.
- Accepted — M-2 matching twin: only the pinned binder can bind; the binder key could still choose a proven twin (docs/m2-trust-assumption.md).
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by a byte-identical copy: same pinned code, same registry; keeper registers every role immediately and verifies module(role).
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: keeper finalizes then rolls over weekly; a rollover only moves the pot to later players.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: a reverting sell rolls the sweep back; it repeats on the next success.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: at most about 54 bps in the player's favour, self-triggered.
- Accepted — 031c93c4 info 6, deploy-gate tool takes only the JSON plan; the runbook says so since v3.15.
- Accepted — 339b6b19 info 5, `Civic.claimWar` rounding dust: wei left by integer splits never leave the game.
- Accepted — 339b6b19 info 6, no max-cost bound on openPack/buyTokenPack: price read at execution; bounded by approval or ETH minimum output.
- Accepted — 339b6b19 info 7, unused minter/caller permissions: every allowed caller is a pinned module of this registry.
- Accepted — 339b6b19 info 8, dead fields: written, never read; no gameplay or security effect.
- Accepted — L1 judge, `PackSale.buyPacksFor` gifting: packs may be bought for another farm; value only flows in.
- Accepted — L1 judge, one-shot escrow: `forward` runs once to the proven RewardPool; no retry or admin by design.
- Accepted — L1 judge, Festival band: attested severities are clamped to 5000–7000; the fallback table keeps 10000.
- Accepted — L1 judge, `Economy._insert` 33-tie lock griefing: deeper insertion reverts atomically; no funds at risk.
- Accepted — L1 judge, stream-0 answers before role 1: stored, executed only after wiring completes.
- Accepted — Binder liveness: one-time bind by 0x6d51…d007; a lost key leaves the Desk unbound and the endowment in escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L3. Job A

```text
BLACKOUT v3.18 L3 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.18 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy job A as ONE evm_contracts launch of eight contracts in exactly the listed order. Resolve $contract:Params and $contract:GameRegistry by name inside this launch. Use the unchanged private roots/snapshot only after checking their committed hash. Return all addresses, indices and launch number. The binder wallet 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007 must sign SwarmDesk.bind(REGISTRY, registryCode, paramsCode, N_A, 1, N_A, 0, N_TOKEN) immediately when this launch is recorded, where N_TOKEN is the recorded L2 launch number (the keeper prints this calldata with wire --step bind-desk and never sends it; no other account can bind); then the keeper registers roles 0–5.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] Params ["<L1_SWARM_DESK>","200","1000000000000000000"]
Creation hash: 0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0
[1] GameRegistry ["<L2_TOKEN>","$contract:Params","<L2_V4MARKET>","<STARTER_ROOT>","<FREE_ROOT>","<SNAPSHOT_BLOCK>","200000000000000000000000000"]
Creation hash: 0xe41104da4edfb9a746e9080ce7b1885b5fe7609674a3a68fc5addbfd5a871531
[2] RewardPool ["$contract:GameRegistry"]
Creation hash: 0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de
[3] FarmRewards ["$contract:GameRegistry"]
Creation hash: 0xfa1a4087722916aeefae66aaf3400299a5e4cb8f4fc8e516a17cec7754e07506
[4] FarmCore ["$contract:GameRegistry"]
Creation hash: 0xc390b07ef7a9ab65bef3a1ec3b39c1a16e117543c9565fedc9342526aa57aa47
[5] FarmItems ["$contract:GameRegistry"]
Creation hash: 0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76
[6] PackSale ["$contract:GameRegistry"]
Creation hash: 0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a
[7] StarterClaim ["$contract:GameRegistry"]
Creation hash: 0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (verbatim and in full in docs/accepted-v318.md; abridged here to the objective limit):
- Accepted — RewardPool shortfall: repair a shortfall with a plain token transfer; `donate` is not the repair path.
- Accepted — Exact-input swaps only: V4Market rejects exact-output swaps; request exact input with a minimum output. v3.18: a buy must carry the extreme sqrtPriceLimitX96 4295128740 (`PriceLimitedBuy` otherwise) and afterSwap refuses a partial fill (`PartialFill`), so tax is never paid on unconsumed ETH.
- Accepted — a3749636 low, manager float: beforeSwap takes the buy tax from the PoolManager before the swapper settles; the live Robinhood PoolManager holds about 24,500 ETH, far above any single buy's tax.
- Accepted — `spot()` bounds: zero, underflowed or above-1e40 prices revert; keep the pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: compiled in, no owner rotation; migration needs a reviewed source release.
- Accepted — Answers between job A and job B: stored after L3, executable only once all L4 modules are registered.
- Accepted — Future-block randomness: native L2 block entropy with capture/re-arm rules, not VRF; enhancement attempts lapse to their worst outcome instead of re-arming (v3.17).
- Accepted — Reserved Params keys (docs/params-keys-v313.md): no gameplay effect; proposals may still consume cooldown.
- Accepted — M-2 matching twin: only the pinned binder can bind; the binder key could still choose a proven twin (docs/m2-trust-assumption.md).
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by a byte-identical copy: same pinned code, same registry; keeper registers every role immediately and verifies module(role).
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: keeper finalizes then rolls over weekly; a rollover only moves the pot to later players.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: a reverting sell rolls the sweep back; it repeats on the next success.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: at most about 54 bps in the player's favour, self-triggered.
- Accepted — 031c93c4 info 6, deploy-gate tool takes only the JSON plan; the runbook says so since v3.15.
- Accepted — 339b6b19 info 5, `Civic.claimWar` rounding dust: wei left by integer splits never leave the game.
- Accepted — 339b6b19 info 6, no max-cost bound on openPack/buyTokenPack: price read at execution; bounded by approval or ETH minimum output.
- Accepted — 339b6b19 info 7, unused minter/caller permissions: every allowed caller is a pinned module of this registry.
- Accepted — 339b6b19 info 8, dead fields: written, never read; no gameplay or security effect.
- Accepted — L1 judge, `PackSale.buyPacksFor` gifting: packs may be bought for another farm; value only flows in.
- Accepted — L1 judge, one-shot escrow: `forward` runs once to the proven RewardPool; no retry or admin by design.
- Accepted — L1 judge, Festival band: attested severities are clamped to 5000–7000; the fallback table keeps 10000.
- Accepted — L1 judge, `Economy._insert` 33-tie lock griefing: deeper insertion reverts atomically; no funds at risk.
- Accepted — L1 judge, stream-0 answers before role 1: stored, executed only after wiring completes.
- Accepted — Binder liveness: one-time bind by 0x6d51…d007; a lost key leaves the Desk unbound and the endowment in escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L4. Job B

```text
BLACKOUT v3.18 L4 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.18 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy job B as ONE evm_contracts launch of eight contracts in exactly the listed order. Each argument is the recorded L3 GameRegistry already bound to the L1 Desk. Return all addresses, indices and launch number. The keeper registers roles 6–13 and completes hook binding, escrow forwarding and endowment funding before executing any oracle answer.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] FeeRouter ["<L3_GAME_REGISTRY>"]
Creation hash: 0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af
[1] GridOperator ["<L3_GAME_REGISTRY>"]
Creation hash: 0x931bdfaeeacadb7c8014ce1411671d0045013c2b373d95bbf0bb83dfce0b7c74
[2] Season ["<L3_GAME_REGISTRY>"]
Creation hash: 0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83
[3] FarmEngine ["<L3_GAME_REGISTRY>"]
Creation hash: 0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c
[4] Economy ["<L3_GAME_REGISTRY>"]
Creation hash: 0x105f9f29d79579fa33ff8e11d4d86847dd7d9f59bd681500553a3844db50ccc9
[5] Enhancement ["<L3_GAME_REGISTRY>"]
Creation hash: 0x31242676dd3a728a2ad32a5cb300166020e87831b0f547756fa0bab88cedea38
[6] Civic ["<L3_GAME_REGISTRY>"]
Creation hash: 0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2
[7] Billboards ["<L3_GAME_REGISTRY>"]
Creation hash: 0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (verbatim and in full in docs/accepted-v318.md; abridged here to the objective limit):
- Accepted — RewardPool shortfall: repair a shortfall with a plain token transfer; `donate` is not the repair path.
- Accepted — Exact-input swaps only: V4Market rejects exact-output swaps; request exact input with a minimum output. v3.18: a buy must carry the extreme sqrtPriceLimitX96 4295128740 (`PriceLimitedBuy` otherwise) and afterSwap refuses a partial fill (`PartialFill`), so tax is never paid on unconsumed ETH.
- Accepted — a3749636 low, manager float: beforeSwap takes the buy tax from the PoolManager before the swapper settles; the live Robinhood PoolManager holds about 24,500 ETH, far above any single buy's tax.
- Accepted — `spot()` bounds: zero, underflowed or above-1e40 prices revert; keep the pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: compiled in, no owner rotation; migration needs a reviewed source release.
- Accepted — Answers between job A and job B: stored after L3, executable only once all L4 modules are registered.
- Accepted — Future-block randomness: native L2 block entropy with capture/re-arm rules, not VRF; enhancement attempts lapse to their worst outcome instead of re-arming (v3.17).
- Accepted — Reserved Params keys (docs/params-keys-v313.md): no gameplay effect; proposals may still consume cooldown.
- Accepted — M-2 matching twin: only the pinned binder can bind; the binder key could still choose a proven twin (docs/m2-trust-assumption.md).
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by a byte-identical copy: same pinned code, same registry; keeper registers every role immediately and verifies module(role).
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: keeper finalizes then rolls over weekly; a rollover only moves the pot to later players.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: a reverting sell rolls the sweep back; it repeats on the next success.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: at most about 54 bps in the player's favour, self-triggered.
- Accepted — 031c93c4 info 6, deploy-gate tool takes only the JSON plan; the runbook says so since v3.15.
- Accepted — 339b6b19 info 5, `Civic.claimWar` rounding dust: wei left by integer splits never leave the game.
- Accepted — 339b6b19 info 6, no max-cost bound on openPack/buyTokenPack: price read at execution; bounded by approval or ETH minimum output.
- Accepted — 339b6b19 info 7, unused minter/caller permissions: every allowed caller is a pinned module of this registry.
- Accepted — 339b6b19 info 8, dead fields: written, never read; no gameplay or security effect.
- Accepted — L1 judge, `PackSale.buyPacksFor` gifting: packs may be bought for another farm; value only flows in.
- Accepted — L1 judge, one-shot escrow: `forward` runs once to the proven RewardPool; no retry or admin by design.
- Accepted — L1 judge, Festival band: attested severities are clamped to 5000–7000; the fallback table keeps 10000.
- Accepted — L1 judge, `Economy._insert` 33-tie lock griefing: deeper insertion reverts atomically; no funds at risk.
- Accepted — L1 judge, stream-0 answers before role 1: stored, executed only after wiring completes.
- Accepted — Binder liveness: one-time bind by 0x6d51…d007; a lost key leaves the Desk unbound and the endowment in escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

## Wiring and operator checks (bind by the binder; everything else permissionless)

1. After L1, check `Desk.registry() == 0`, `Desk.binder() == 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, all `oracleConfig()` endpoints match Robinhood.sol, and the binding hash, 200 bps heartbeat and 1 ETH cap match this runbook. Check `Escrow.desk()` equals the L1 Desk and `forwarded()` is false.
2. After L2, check `(ETH, TOKEN, 12500, 60, HOOK)`, `manager()` and `launcher()` match the pinned PoolManager and LaunchFactory, `desk()` and `gameConfigHash()` match L1 (`desk() == 0x5cb0686a4475d1f8a6c6e5240579080a4a05b609`), `BUY_PRICE_LIMIT() == 4295128740`, and `initializedAt() != 0`. Tell integrators that buys must use the extreme price bound with a minimum output (the v4 router default); a buy with any other `sqrtPriceLimitX96` reverts `PriceLimitedBuy`. The escrow must hold at least 200,000,000e18 tokens; liquidity dust may make the balance larger.
3. Immediately after L3, the **binder wallet** `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007` signs and sends `Desk.bind(REGISTRY, registryCreationCode, paramsCreationCode, N_A, 1, N_A, 0, N_TOKEN)` using the v3.17 artifacts, where `N_TOKEN` is the recorded L2 launch number (`keeper/wiring.json` `tokenLaunch`). `node keeper/keeper.mjs wire --wiring wiring.json --step bind-desk` simulates the call from `Desk.binder()` and prints the transaction (from, to, data) for that wallet to sign; the keeper key cannot send it (any other caller reverts `Unauthorized`). The Desk reads `LaunchFactory.positionOf(N_TOKEN)` and requires it to name `(ETH, TOKEN, 12500, 60, HOOK)` with `HOOK == REGISTRY.market()` and `TOKEN == REGISTRY.token()`; check that record yourself first with `cast call 0xa25b…4645 "positionOf(uint64)" N_TOKEN` (launch 832 reads `currency0 == 0x0`, like every ETH-paired univ4_hook launch). After the binder's transaction confirms, re-run `wire`: it confirms `Desk.registry() == REGISTRY` and stops otherwise. Confirm `Desk.tokenLaunch() == N_TOKEN`, registry token/market/Params/roots/snapshot, and `Params.swarmWallet() == DESK`. Then `GameRegistry.register(role, N_A, role + 2, creationCode)` for roles 0–5 (permissionless, keeper key). Keep eligibility lists private until binding is verified. If a different registry is bound, stop; do not forward funds or publish wiring. The binder key must be available once, after L3: if it is lost before binding, the Desk never binds and the endowment stays in the escrow. See `docs/m2-trust-assumption.md`.
4. After L4, register roles 6–13 using `(role, N_B, role - 6, creationCode)`, and verify all fourteen modules. Call `V4Market.bindFeeRouter(FEE_ROUTER, N_A, 1)`, check `fees()` and `params()`, then call `flushFees()` if fees accumulated during launch.
5. Recheck the bound registry, then `EndowmentEscrow.forward(REGISTRY, N_A, 1, registryCreationCode, N_A, 2, rewardPoolCreationCode)`. It transfers its entire token balance once to the authenticated RewardPool. Check escrow balance zero, `forwarded()`, and RewardPool balance ≥ principal; call `RewardPool.fundEndowment()` and check `endowed()` and the 42-day drip.
6. Call `FarmRewards.advanceEpoch()` after funding and before announcing pack availability. The one-hour pack gate and 30-minute launch tax both start at L2 initialization, potentially hours before L4 is available. The tax may have ended by game activation; the clock never resets. A keeper should advance immediately once the complete graph is ready, not wait for another hour.
7. The requester funds a keeper wallet for gas and supplies its RPC and schedule funding. The keeper has no authority beyond permissionless calls; the one bind is signed by the binder wallet, never by the keeper key. `node keeper/keeper.mjs wire --wiring wiring.json` uses `keeper/wiring.example.json`; dry-run the resolved values first. Configure existing schedule IDs, registry and token launch number after recording actual outputs. Never commit keys.
8. Create the two Ethereum-paid oracle schedules from the unchanged bodies using `tools/make_oracle_bodies.mjs DESK`: event cron `5 */6 * * *` UTC, regulator cron `5 0 * * 4` UTC, consumer `{chainId:4663, verifyingContract:DESK}`, no `deliver`. The requester renews/funds schedules (14.5 IMD per week at the pinned 0.5 IMD price). Relayers authenticate the served EIP-712 document and submit it to the Desk; execute only after all modules are registered. If schedules stop, the existing fallback game rules continue. Robinhood IMD backup donations have no withdrawal path.
9. Keepers advance epochs, capture native L2 entropy, settle/finalize bounded work, execute reward buys and safe sell batches, and call `LaunchFactory.claimFees(N_TOKEN)` periodically for the paying wallet. Sell callers supply a minimum based on the current safe batch; a stale high minimum still reverts atomically. Lottery claims now return PackSale receipt IDs: capture entropy and resolve the receipt as with district rewards, after making room for three items.
10. Economy lock insertion traverses at most 32 existing district locks. A deeper insertion reverts atomically with `InvalidValue`; a larger stake that belongs earlier or an earlier lock's exit can make insertion possible. Existing unlock and district stake accounting are unchanged. RewardPool accounting shortfalls are repaired by plain transfer, not `donate`.

## Rehearsal and limits

Run `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v318/rehearsal.log` (alternative: `https://robinhood-rpc.publicnode.com`). The script compiles before taking a fresh local Anvil fork (public endpoints may prune historical state) and sends no upstream transactions. Its five test-only launch numbers are 777001–777005, asserted unrecorded first (777005 is a fake-market registry that the v3.15 bind must refuse). L1 submits both contracts in one real ProjectFactory call; L2 uses the real LaunchFactory/PoolManager; L3/L4 use the real factory and registry. Rehearsal roots are explicitly test-only and never replace the frozen production preimage.

The fixed attester remains in the deployed Desk configuration. Only on the local fork, an ERC1271 test signer is etched at that address so valid/invalid signed answers can be exercised without the real private key; native L2 blockhash inputs are also controlled for repeatable entropy tests. This proves constructor decoding, recorded deployment, code proofs, wiring, endowment, fee settlement and keeper paths. It does not prove the live attester service, paid admission, schedule delivery or launch-day gas. See `report.md` v3.15 and the committed logs for results. No waits for paid launch queues occur in this source task.

The v3.18 run passed all five fork tests at anvil fork block 88100745 on 2026-10-14 (`artifacts/v318/rehearsal.log`, upstream `https://robinhood.drpc.org`, basefee 20,298,000 wei) with the v3.18 hook: L2 (777002) deployed the token and the new hook through the real LaunchFactory, every rehearsal buy (extreme bound) paid the stepped tax then exactly 1%, the sell surcharge was unchanged, bind, roles 0–13, `bindFeeRouter`, `forward` and the pack entropy completed. Measured factory-call gas: L1 6,952,280; L2 7,143,830 (hook 275 bytes larger); L3 21,561,311; L4 19,753,231, all below the 0.01 ETH ceiling. The v3.17 run passed all five fork tests at anvil fork block 87728112 on 2026-10-13 (`artifacts/v317/rehearsal.log`, upstream `https://robinhood.drpc.org`, basefee 20,148,000 wei) with the re-pinned v3.17 artifacts: L1 deployed the eight-word Desk and the escrow through the real ProjectFactory (777001), L2 the token and hook through the real LaunchFactory (777002), L3 job A (777003) and L4 job B (777004); non-binder senders were refused `Unauthorized`, the binder's bind set `tokenLaunch() == 777002` with `LaunchFactory.positionOf(777002)` naming the rehearsal token, hook and paying wallet, the fake-market registry (777005) was refused, roles 0–13 matched the recorded addresses, `bindFeeRouter` and `forward` completed and the first pack entropy was captured. Measured factory-call gas: L1 6,952,280; L2 7,089,377; L3 21,628,498; L4 19,828,437, all below the 0.01 ETH ceiling at the fork basefee (the largest, L3, costs about 0.000436 ETH at 20.148 gwei-equivalent basefee 20,148,000 wei). The previous v3.16 run (block 87590429, `artifacts/v316/rehearsal.log`) is kept for comparison. The v3.16 run passed all five fork tests at block 87590429 on 2026-10-13 (`artifacts/v316/rehearsal.log`, upstream `https://robinhood.drpc.org`-equivalent 4663 endpoint): L1 deployed the eight-word Desk with `binder() == 0x6d51…d007`, the platform deployer and a keeper hot wallet were refused `Unauthorized` with the complete correct proof, the fake-market registry launched through the real ProjectFactory (777005) was refused from its launcher and from the binder, the binder's bind set `tokenLaunch() == 777002`, and the real `LaunchFactory.positionOf(777002)` record named the rehearsal token, hook and paying wallet; all four measured launch costs were below 0.01 ETH at 0.020748 gwei. Full figures and the fork limitations are recorded in `report.md`.
