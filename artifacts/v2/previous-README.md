# BLACKOUT

Immutable Solidity game contracts, a deterministic economy reconstruction, Foundry tests, and deployment scripts. **Nothing has been deployed. No game ERC-20 is created, replaced, or minted by this project.** The future IMD token is supplied as a constructor parameter.

Read [report.md](report.md) for verification results and limitations, [docs/design.md](docs/design.md) for accounting, [docs/simulation-assumptions.md](docs/simulation-assumptions.md) for model provenance and approximations, and [artifacts/simulation.md](artifacts/simulation.md) for reconstructed economy results.

## Reproduce without network

The dependencies are vendored as ordinary source files. Foundry must have the compiler pinned by `foundry.toml`, **Solidity 0.8.26**. There is no FFI or filesystem permission configuration.

```sh
forge build
forge test
forge fmt --check
python3 sim/blackout_sim_v2.py --check
python3 -m unittest discover -s test/python -v
python3 sim/blackout_sim_v2.py
```

The optional Robinhood fork smoke test is skipped on other chains. It reads native ArbSys results through the selected fork RPC and replays them into the local EVM, which does not itself execute ArbOS. To run it with a working RPC and Foundry:

```sh
forge test --fork-url "$ROBINHOOD_RPC_URL" --match-contract RobinhoodForkTest -vv
```

An initial direct RPC probe returned HTTP 403, but the explicit Foundry fork run subsequently **passed the native ArbSys number/hash smoke test**. Local tests additionally cover ArbSys-versus-L1 block numbering and real vendored Uniswap v4 PoolManager integration. The smoke test is not a full application test against the eventual launch token and market configuration.

## Contracts and authority

| Contract | Purpose / authority |
|---|---|
| `Params` | Only the immutable `swarmWallet` changes numeric settings, within hard bounds and at most 10% relative change per key per 24 hours. |
| `FarmItems` | ERC-1155 equipment and room keys; immutable metadata. Only `PackSale` mints paid items; only `StarterClaim` mints Starter items. |
| `PackSale` | ETH and reward-funded packs, beta limits, permissionless future-block resolution, and paid-item merges. Only new pack commitments can be paused by swarm; max 72 hours, no extension, then 24 hours before another pause. |
| `StarterClaim` | Immutable snapshot root and block; one claim per snapshot tokenId, hour 48 through before day 16. Anyone resolves the randomness. |
| `FarmCore` | Player-owned item escrow and placement, room bonuses, upkeep prepay, repairs, overclock, token packs, token lobbying, and referrer registration. Anyone can refresh a farm. |
| `FarmRewards` | Permissionless emission/settlement, daily reward vintages, player claims, funded referrals, and permissionless inspection selection/payment. |
| `RewardPool` | Donation-only funding from users; reserves and payouts restricted to immutable `FarmRewards`. No administrative withdrawals. |
| `Generator` | Voluntary seven-day token pledge; only the depositing player retrieves principal. No administrator, slash, or pause. |
| `GridOperator` | Swarm submits bounded event types and herald content hashes/URIs. Anyone resolves future-block districts or applies overdue Calm. Players lobby their own district. |
| `FeeRouter` | Immutable ETH splits, pull credits, TWAP-constrained buybacks. Current team address can only change its own future fee recipient. Old credits stay with their original payee. |
| `BurnVault` | Irretrievable token sink. This locks tokens; it does not call or alter ERC-20 `totalSupply()`. |
| `V4Market` | Optional combined v4 launch hook, arithmetic ETH/token TWAP, progressive sell fee, and system buy adapter. Immutable pool and recipients. |
| `MarketFactory` | Optional permissionless CREATE2 deployment of a correctly flagged `V4Market`. No game privileges. |

No owner, proxy, upgrade function, arbitrary-call executor, administrative NFT mint, or administrative pool withdrawal exists. Claims, Generator unlocks, item exits, and fee-credit withdrawals have no pause check. Standard token transfers and permissionless accounting catch-up must still succeed.

## Play / integration API

- Approve `FarmCore` as the ERC-1155 operator. `PackSale.openPack(n)` requires exactly `price()*n` ETH; anyone calls `resolve(id)` after its target block.
- Six equipment types use kind numbers GPU **0**, ASIC **1**, Power Supply **2**, Cooling **3**, Motherboard **4**, Router **5**; Room Key is **6**. `place(id, room, slot)` uses rooms 0–3 with `slot == kind`. Room **4** means standalone mining, with slots 0–39. There is a combined 40-equipment cap. Room 0 is free; install a key for each additional room.
- Every equipment type mines without a room or another item. Room keys unlock space and do not themselves produce hash. `unplace` returns the exact item to its player. A key can be removed only from an empty room. Withdrawn slot overclocks are discarded.
- Call `setReferrer(inviter)` once before placing mining equipment. The inviter must have an older registered farm, preventing cycles. A pack purchase can register a farm before equipment placement.
- `FarmRewards.settle(player, maxDays)` and `checkpoint(maxTicks)` can be called by anyone. `claim(amount)` consumes the caller's oldest credited rewards first. The frontend should settle before displaying spendable pending balances.
- `FarmCore.spend(kind, room, slot, units)` consumes unclaimed rewards with 5% extra purchasing power. Kind numbers: **0** slot overclock (`units=1`), **1** repair (`units=points`), **2** electricity (`units=nominal token base units`), **3** lobby (`units=nominal token base units`), **4** one token-paid pack (`units=1`). No withdrawal tax is charged on spending.
- `payMaintenance(isRepair, units)` pays from the player's wallet without the reward-spend discount; this permits revival after inactivity even without pending rewards. Approve the game token to `FarmCore` for that payment. `PackSale.merge(id)` burns three identical unplaced paid equipment items and mints one next rarity, charging two days of the result's yield from pending rewards.
- Approve the game token to `Generator`, then `lock(amount)` with at least `FarmCore.generatorRequirement(player)`. The seven-day deadline is immutable for that pledge. `unlock()` returns all principal after it. This is a pledge, not yield-bearing staking.
- `StarterClaim.claim(tokenId, proof)` verifies the caller against the snapshot holder. Later NFT sales do not transfer this entitlement. Starter equipment is soulbound except custody movement into/out of that same player's farm; it mines at half hash until a normal paid pack resolves. Token-paid packs count as paid packs.

## Deployment inputs

`script/Deploy.s.sol:Deploy.run()` reads these **required** environment variables, with no fallback addresses, IDs, roots, or private keys:

| Variable | Value supplied and verified by the launch operator |
|---|---|
| `TOKEN` | The actual future IMD game token; ordinary, non-rebasing, non-taxed ERC-20 transfers. No replacement token is deployed. |
| `SWARM_WALLET` | The swarm's chosen Grid Operator address. Immutable. |
| `HEARTBEAT_RECIPIENT` | Heartbeat ETH fee recipient. Immutable. |
| `TEAM` | Initial team ETH fee recipient; only that address can later call `changeTeam`. |
| `MARKET` | Verified immutable `IMarket` adapter for this exact token, providing a 30-minute TWAP and actual output-checked buys. Can be a correctly configured `V4Market`. |
| `LAUNCH_TIME` | Future Unix timestamp, UTC. All windows derive from it. |
| `STARTER_ROOT` | Nonzero root built from the actual Ethereum snapshot. Not an example root. |
| `SNAPSHOT_BLOCK` | The actual Ethereum snapshot block. |
| `DEPLOYER` | The intended deployment account; used only to record the correct transaction sequence and predict immutable CREATE wiring. It receives no game privilege. |

The script's `deploy(Config)` function is tested directly with explicit test-only configuration and from an unrelated caller. `run()` is a dry run under ordinary `forge script`; this assignment does **not** authorize `--broadcast`. No launch manifest is included.

There are eleven sequential application deployments. Their constructor links are predicted from the actual creator's nonce, checked locally, and cannot be rewired afterward. The script is not an on-chain factory and its own aggregate bytecode must not be deployed. If the network launcher deploys contracts individually, it must reproduce the complete immutable address plan rather than use the script's address as an owner.

### Optional v4 market

The existing IMD launch integration must explicitly select this combined hook. **Do not layer it on another hook that already charges the 1.25% policy fee.** This implementation charges that total base fee itself, sends 0.25% to the configured network recipient, and routes the other 1% into the game's fee router. It supports exact-input swaps; exact-output swaps revert. The pool LP fee is fixed at zero to avoid adding an uncounted LP fee to the disclosed cap. The v4 PoolManager's own external governance remains outside BLACKOUT.

`V4Market` constructor inputs are PoolManager, token, Params, FeeRouter, network recipient, zero LP fee, and positive tick spacing ≤ 32767. Confirm that the launch system supports this hook and provides the correct network fee recipient. No address for those external services has been guessed. Its low address bits must be **0x10cc**. `MarketFactory` can find and deploy a valid CREATE2 salt from the exact constructor configuration; `script/DeployMarket.s.sol` reads `MARKET_FACTORY`, `POOL_MANAGER`, `TOKEN`, `PARAMS`, `FEE_ROUTER`, `NETWORK_RECIPIENT`, `TICK_SPACING`, `MARKET_SALT`, and `DEPLOYER`.

Resolve the address plan before launch: predict the game's Params/FeeRouter, compute the market CREATE2 address with those immutable links, then use that market address in the application configuration. The market may be deployed before or after the application, but both must exist and agree before the future launch timestamp. Initialize the native ETH/token pool with this hook and sufficient liquidity; wait for **31 minutes of price history** before token packs or buybacks can obtain a quote. Trading can proceed during warm-up using the imbalance fee terms; the deviation term starts when the TWAP is ready.

### Starter snapshot tooling

Export the real collection's owners at the chosen Ethereum block into CSV columns `tokenId,holder`. Then run:

```sh
python3 tools/starter_merkle.py owners.csv --snapshot-block "$SNAPSHOT_BLOCK" --collection "$COLLECTION" > starter-proofs.json
```

This uses local `cast keccak`, not a network or private key. The leaf is exactly `keccak256(abi.encode(uint256 tokenId,address holder))`, with sorted pairs and an unpaired node carried upward. Publish the snapshot, collection identity, root, block, and proofs for review before immutable deployment. The snapshot collection identity is an operational attestation; the game verifies the root and does not bridge NFT ownership on demand.

## After launch: operational responsibilities

There is no post-launch owner configuration. Verify every constructor value before launch; mistakes cannot be repaired through an admin setter.

- The **launch operator** verifies the token's plain-transfer behavior, immutable graph, external market/PoolManager, hook support and fee handling, recipient addresses, chosen liquidity, snapshot data, compiler/runtime hashes, and hook address flags. Deploying the token and initializing liquidity belong to the separate launch process.
- The **swarm** publishes an event number during the first hour of each 12-hour tick and optionally a herald letter; only the future block hash chooses districts. It monitors pool inflow, tariffs and event fairness, and applies bounded parameter changes. A letter is informational, not executable configuration.
- **Permissionless keepers / clients** resolve pack and event commits promptly (the future hash expires after 256 native L2 blocks), advance emission, settle/refresh stale farms, run small buyback batches at least ten minutes apart, and submit inspection candidates during the 24-hour window after each week. Finalize after that window. No operator key is needed for these actions.
- Accounting is bounded: checkpoint 1–64 half-day segments and settle 1–64 daily segments per call. After long inactivity, use small `checkpoint` batches until caught up and then settle/refresh accounts. The max batch is a ceiling, not a recommended transaction size on every chain. Avoid assuming a large catch-up will fit one block.
- Fee payees withdraw their own accrued ETH credits. Anyone may deliver accrued network fees to the immutable network recipient. Pool tokens and burn-vault tokens have no operator withdrawal path.

Use a separate adversarial review before handling live funds. The tests and implementation-author review in this repository are not an independent audit.
