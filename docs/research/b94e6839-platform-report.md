# BLACKOUT on Robinhood Chain via IMD: how the platform actually supports the launch plan

Research date: 2026-10-11 (Robinhood Chain head ≈ 86,055,359; Ethereum head ≈ 26,171,137).
Scope: read-only. Nothing was deployed, paid, signed, quoted or scheduled. The only calls made to the IMD plane were public GETs and two free `POST /requests/check` preflights, which create nothing and hold no price. All chain calls were `eth_call` / `eth_getCode` / receipt reads, including local simulations (`cast call --trace`) that sent no transaction.

Subject: BLACKOUT v3.7 (X: https://x.com/IMDBlackout, site: playblackout.xyz), repository
`https://github.com/identity-md-launches/launch-1269-reports-v1-job-b9e37680-814c-4f17-b4bc-6`,
job c379f49a (commit `23bcc49e`, v3.6) and job 03cb04ff (commit `0410ef2c`, v3.7). Files read: `launch-v37.md`, `src/SwarmDesk.sol`, `script/PredictGame.s.sol`, plus `src/V4Market.sol`, `src/RewardPool.sol`, `src/GameRegistry.sol` and `foundry.toml`, where needed.

## How to read this report

Each claim carries one of four labels:

- **[FACT]**: read directly from a primary source. That means the docs, a live API response, on-chain bytecode or state, or a past launch transaction.
- **[INFERENCE]**: follows from facts but was not observed directly.
- **[UNKNOWN]**: no primary source was found. A workaround is proposed.
- **[PROPOSAL]**: a recommendation by this report, not platform behaviour.

### Source keys used in citations

| Key | Source |
|---|---|
| D:§x | `https://imd.fun/docs/llms.txt` (the docs as Markdown), section *x* |
| CAPS | `GET https://api.imd.fun/requests/capabilities` |
| POL v | `GET https://api.imd.fun/launch/policies`, policy version *v* |
| L n | `GET https://api.imd.fun/launches/<id>` for launch number *n* (ids below) |
| W | Worker distribution `github.com/Identity-md/worker` @ `ffda8796`, `dist/cli.js` (the protocol schemas the swarm builds against) |
| LF | LaunchFactory, Robinhood `0xa25b02a1e93903b790e6aaf7da1b8b8d50294645` |
| PF | ProjectFactory, Robinhood `0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e` |
| PFR | ProjectFactory registry, Robinhood `0xf52bbe066b7ad2d28c2195d066ea08dcbca88406` |
| CHECK | `POST https://api.imd.fun/requests/check` (free preflight) |

The function names below come from selectors in the deployed runtime bytecode, resolved through the public 4byte/openchain database. The factory sources are not verified on an explorer (D:§Contract addresses). The names are therefore labels; the behaviour was checked by calls and traces.

Past launches used as evidence (all on Robinhood, chain 4663):

| Launch | id | Kind | Economics | Tx |
|---|---|---|---|---|
| 1316 MONEYBACK | `1ed280f5-02e0-4d77-83a2-1917bad1a061` | univ4_hook | poolBps 9000, remainderTo `0x…dEaD` | `0x22206fe6…8a76c53` |
| 1300 SPEPE | `1c3296e8-d1b9-459e-93f1-6e9b710aa4c2` | univ4_hook | poolBps 8000, remainderTo `0xbda0…9611` | `0xe7cc4120…b3fa81b` |
| 1015 Work | `cce19797-a905-488f-9dd3-ee558d4ccb50` | univ4_hook | poolBps 6500, remainderTo `0xc9ea…12a0` | `0xf9ae82d5…c3d497fb` |
| 1271 IMD6900Perps | `848ec41a-4641-42bc-b2e8-0c1426b49d8e` | evm_contracts | none | `0xcc510b0b420b4968c06a85fb079da76fb416dfeaf51a68a6679bacdac4bdfaeb` |

Full hashes for the others: 1316 `0x22206fe6de8ae281bbf9f4e51ade224365cbfff770cb1ff57fa5159098a76c53`, 1300 `0xe7cc4120312982d1a88bf121c2b8b4819024c4f42d9d5fb95817e8026b3fa81b`, 1015 `0xf9ae82d5d548e92fdd5f1890d327f5b5126a3f280f2bd4b8b3c6cfc9c3d497fb`.

---

## Executive summary

1. **The 20% endowment can go to a codeless address, so the mechanism works. The plan's way of obtaining that address does not.** `remainderTo` is a single plain ERC-20 transfer inside the launch transaction, and no code-size, EOA or allowlist check was observed. The blocker is that you cannot know the RewardPool's address before the token launch. That address is CREATE2 over a *launch number* that IMD assigns from one global counter, and a requester cannot reserve one.
2. **The custom hook as written will not survive the platform's pool parameters.** `V4Market`'s constructor reverts unless `fee_ == 0`. Every current Robinhood `univ4_hook` launch opens at LP fee 12,500 (1.25%), set by policy.
3. **The oracle heartbeat design is refused at the API.** `schedule.create` rejects an oracle body that contains `deliver` (`Unrecognized key: "deliver"`). `SwarmDesk` accepts results only from Intake or IntakeDelivery, so scheduled answers can never reach it as written.
4. **The 1% project fee goes to the paying wallet, not to a predicted FeeRouter.** Only that wallet can later redirect it, using `setRequester` on the LaunchFactory.
5. **`workflow.open` covers one launch plus one site, not five steps.** The sequence is five separately paid actions (0.5 IMD each). Every post-deploy call (register, bind, bindFeeRouter, fundEndowment, setRequester) has to come from an ordinary wallet or keeper.

Recommendation: do not launch on the v3.7 plan. The blocker list at the end gives the minimum changes.

---

## Q1–Q3: yes/no + evidence table

| # | Question | Answer | Evidence | Label |
|---|---|---|---|---|
| 1a | Can `remainderTo` be an address with **no code**? | **Yes** | L1316 used `remainderTo = 0x…dEaD`. `eth_getCode` is `0x` and the nonce is 0 at the current block. The launch tx sent it the remainder via `Transfer(LF → 0x…dEaD)`. L1300 and L1015 sent 100M and 250M tokens to EOAs (`eth_getCode` = `0x`). | FACT |
| 1b | Any code-size / EOA-only / allowlist check on `remainderTo`? | **None observed** | W `RequesterShare = {poolBps:int 1..9000, remainderTo: Address ≠ 0x0}`, and nothing else. The protocol-wallet and stand-in refusals (`refuseStandIn`) apply to *constructor arguments*, not to `economics`. L1316 shows even `0x…dEaD` passed admission (`admissionChecks.economics: passed`). | FACT (schema + precedent). An *off-chain* evaluator refusal of a specific address is not ruled out (INFERENCE) |
| 1c | With poolBps 7000, what lands where? | 10% swarm distributor, 70% pool, **20% to `remainderTo`** | D:§Launch fields ("poolBps of the supply seeds the pool … the rest goes to remainderTo … swarm always takes ten percent"). Measured on chain: L1015 poolBps 6500 sent 100M distributor, 650M PoolManager, 250M remainderTo. L1300 poolBps 8000 sent 100M / 800M / 100M. So `poolBps` is out of the **total** supply. | FACT |
| 1d | Can the allocation be split (20% to A, 10% to the swarm share)? | **Already the case, but no further split.** The swarm 10% is automatic and separate. The requester's non-pool remainder goes to exactly **one** address. | D:§Delivery `economics` "only `{poolBps, remainderTo}`" on a hook launch. LF `launch(...)` tuple has one `remainderTo` address (decoded L1316 calldata). | FACT |
| 1e | Can we know the predicted RewardPool address at token-launch quote time? | **No (blocker)** | The RewardPool address is `PF.predictContract(launchNumber, index, initcode)`, and its initcode embeds the Registry address. The Registry address in turn embeds the token and hook addresses, which depend on the *token's* launch number (see Q2). Launch numbers come from one global counter shared by every chain and kind, and are not reservable (see Q2). | FACT for the derivation, INFERENCE that it can't be pre-known |
| 1f | Safest supported alternative that never routes 20% through a personal/swarm wallet | Set `remainderTo` to an **already-deployed, ownerless escrow** whose only function forwards its whole token balance once to a RewardPool it authenticates on chain. Any code-free predicted address is unsafe, because if the prediction misses, the 20% is unrecoverable. | See *Q1 workaround* below. | PROPOSAL |
| 2a | How is a ProjectFactory contract address derived? | `CREATE2(PF, salt = keccak256(abi.encode(uint64 launchNumber, uint256 index)), keccak256(initcode ‖ args))` | `PF.salt(1271,0)` (selector `0x4bb045d0`) = `0x58f10efc…dde159` = `cast keccak(abi.encode(1271,0))`. `cast create2` with that salt reproduces `PF.predictContract(1271,0,0x00)` = `0xa5E8…475E`. With the real 20,235-byte initcode from tx `0xcc510b0b…`, `predictContract(1271,0,ic)` = `0x2aBc…7Aa3` = the deployed artifact of L1271. | FACT |
| 2b | Token and hook (LaunchFactory) addresses? | Token: `LF.predictToken(launchNumber, initcode)`. Hook: `CREATE2(LF, salt, keccak(hookInitcode))` with salt = `launchNumber << 192 \| minedNonce` | `predictToken(1316, tokenInitcode)` = `0xc400…332E` (actual token). For the hook, salt `0x0000000000000524…00001353` (0x524 = 1316, nonce 0x1353) reproduces hook `0x0BB8…60cc`. `LF 0x94e81bd1(bytes,uint256)` returns the same address. The nonce is mined by the plane for the flag bits. | FACT |
| 2c | Can we know RewardPool / FeeRouter / SwarmDesk addresses before the token launch? | **Only if all the relevant launch numbers are known in advance. They are not.** | Launch numbers are not requested, quoted or reserved anywhere in the docs. D:§Open a job lists no such field. W's task schemas show `launchNumber` assigned by the plane. Of the last 100 numbers (1228–1328), 68 do not appear in `/launches`: numbers are also consumed by non-launch work. Your own research repo is `launch-1269-…`, and 1269 is not a launch. | FACT (no reservation API; numbers shared), INFERENCE (unpredictable) |
| 2d | Is each coordinate single-use? `NotDeployer` / `AlreadyLaunched`? | **Single-use: yes. Only the IMD launch wallet can deploy: yes.** | PF/LF `deployer()` = `0xcecc29b0…a551` (D:§Wallets "the only wallet either factory takes a launch from"). The `NotDeployer()` selector `0x8b906c97` is present in both runtimes. `PFR.isRecorded(1271)` = true and `isRecorded(5000)` = false. CREATE2 itself cannot redeploy to an occupied address. `AlreadyLaunched(uint64)` (`0x400f4236`) was **not** found as a literal in either runtime, so the exact error name is unconfirmed. The independent v3.7 review's claim of seeing it by disassembly could not be reproduced here. | FACT / UNKNOWN (error name only) |
| 2e | Contracts per ProjectFactory launch | 1–8, indices 0–7 | W `EvmContractsManifest.contracts.min(1).max(8)`. D:§Launch fields "1–8 contracts, deployed in order and recorded in one transaction, all or nothing". | FACT |
| 3a | Does a univ4_hook launch take *our* hook with constructor data? | **Yes**, the hook contract from your repo, via `launch.json` `hook.constructorArgs` | W `UniV4HookManifest.hook = {contract, constructorArgs: string[≤16], permissions[≤14]}`. L1316 deployed the requester's `MoneyBackHook` (flags 0x20CC). | FACT |
| 3b | Constructor arg rules | ≤16 **static** words (address/uint/bytes32 hex or decimal) plus placeholders `$poolManager`, `$token`, `$owner`, `$factory`. An `IPoolManager`-typed arg must be `$poolManager`. Zero, `0x…dead`, low addresses, all-ones and IMD launch wallets are refused. | W `HOOK_PLACEHOLDERS`, `validateHookConstructor`, `refuseStandIn`, `standInAddress`. | FACT |
| 3c | Can it commit Params and gameConfigHash? | Mechanically yes (bytes32 and address words are allowed). Practically it needs the predicted Params address, which hits the same launch-number blocker. | As 2c. | INFERENCE |
| 3d | Fee settings: 1% project to the predicted FeeRouter + 0.25% network? | **No, not as designed.** The pool LP fee is fixed by policy at **12,500 (1.25%)**. `claimFees(launchNumber)` is permissionless and pays 80% (0x1f40 = 8,000 bps) of collected fees = **1%** to the launch's *requester* (the paying wallet) and 20% = **0.25%** to `LaunchFees.feeRecipient()` = `0x3f25…1f22`. | POL 30 (`feeTiers [12500]`, chain 4663). All 7 live 4663 hook launches since #832 have `poolFee 12500`. A traced simulation of `LF.claimFees(1316)` from an arbitrary address succeeded and showed both transfers (to `0x5779…1eac` = L1316 requester, and to `0x3f25…1f22`). | FACT |
| 3e | Can the 1% be pointed at FeeRouter? | **Only afterwards, by the paying wallet**: `LF.setRequester(launchNumber, newAddress)` | Simulated from a random address it reverts `NotRequester(1316)` (`0x4e8b9bd4`). From the L1316 requester it succeeds. No request-body field sets a different fee recipient (D:§Launch fields "1% to the paying wallet"). | FACT (access rule); INFERENCE (whether a contract recipient keeps working; ETH legs need `receive()`) |
| 3f | V4Market compatibility with that fee | **Blocker.** The `V4Market` constructor reverts when `fee_ != 0`. Its `poolId` and `key()` are built with that fee, and every hook callback checks `keccak(key) == poolId`. With the platform's 12,500 fee, the hook can neither be built with the real fee nor match the real pool. It also charges its own 0.25% `NETWORK_BPS`, which would double the network fee. | `src/V4Market.sol` L88–110, L201–203, L30–31, vs POL 30. | FACT |
| 3g | Tick spacing | Observed **60** (L1316, decoded `launch` calldata and the `claimFees` trace PoolKey). The manifest field `pool.tickSpacing` accepts 1–32767. | W `UniV4HookManifest.pool`. L1316 calldata. | FACT (observed); UNKNOWN whether the plane overrides a different value |
| 3h | Initial price | Set by policy for the pairing, not by the requester: `initialMarketCaps` on 4663 is **10 ETH** (ETH pair) or **2,500 IMD** (IMD pair). Single-sided liquidity in the launch token. L1316 used tickLower −887220, tickUpper 128940. | POL 30. D:§Launch fields. L1316 calldata. | FACT. Only `custom_token` takes `initialMarketCapWei` (D:§Delivery) |
| 3i | Who initializes the pool? (address for the authenticated-init check) | **LaunchFactory `0xa25b02a1e93903b790e6aaf7da1b8b8d50294645`** calls `PoolManager.initialize` inside its own `unlockCallback` in the launch tx, so `sender` in `before/afterInitialize` is the LaunchFactory. The tx sender is the launch wallet `0xcecc…a551`, not the initializer. | L1316 tx `to = LF`, PoolManager `Initialize` log in the same tx. LF exposes `unlockCallback(bytes)` and `poolManager()` = `0x8366…0951`. `PoolInitializationGuard 0x19be…6000` is the ProjectFactory's hook for `evm_project`/`custom_token`, **not** for univ4_hook. | FACT (tx structure); INFERENCE (exact `sender` argument; confirm with a Sepolia rehearsal) |

### Q1 workaround (safest supported path)

A RewardPool address predicted ahead of time stays unknowable as long as the launch numbers are. Sending 20% of supply to a code-free predicted address is therefore an irreversible bet: if any number differs, the tokens sit forever at an address nobody can deploy to (the factory deploys only for the launch wallet, at recorded coordinates). The safest supported option within the platform's real features:

1. **[PROPOSAL] Deploy an `EndowmentEscrow` first** as its own `evm_contracts` launch (1 contract, 0.5 IMD). It has no owner, no admin, no withdraw-to-caller and no upgrade. It exposes one permissionless `forward(token, registryLaunch, registryIndex, …)` that:
   - recomputes the RewardPool and Registry via `PF.predictContract` with pinned creation-code hashes;
   - checks `code.length > 0`, `RewardPool.registry().token() == token`, and the frozen roots/endowment commitment;
   - transfers its whole balance once.

   This is the same proof style as `SwarmDesk.bind`, so it fits the existing code.
2. Use the escrow's **real, existing** address as `remainderTo` in the token launch. That needs no launch-number knowledge at token time, and the 20% never touches a personal or swarm wallet.
3. After jobs A/B, anyone calls `forward`, then `RewardPool.fundEndowment()`.

   Caveat: `RewardPool.fundEndowment` excludes `otherInflow`, but a direct `transfer` from the escrow is not counted as `otherInflow` (only `donate` and `recordInflow` are), so the principal check passes. **[INFERENCE from `src/RewardPool.sol` L64–77]**

If you don't want an extra contract, the only other supported settings are `poolBps 9000` (no remainder at all) or `remainderTo = paying wallet`. You have ruled out both.

---

## Q2: launch numbers, indices and address prediction (details)

- **[FACT] Reservation.** The docs expose no field or route to reserve a launch number (D:§Open a job, §Launches). `launchNumber` appears only in plane-to-worker task schemas (W `UniV4LaunchTask`, `ContractsContext`), so the plane assigns it. Numbers are shared across Ethereum, Sepolia and Robinhood and across all kinds: `GET /launches` mixes chain 1, 4663 and 11155111 in one sequence (latest 1328), and numbers are also consumed by non-launch jobs (68/100 gaps; `launch-1269-…` is your own research repo).
- **[FACT] Index.** It is the position of the contract in the `launch.json` `contracts` array (0–7). Contracts deploy in order, all or nothing, and `$contract:EarlierName` resolves to an earlier sibling (W `EvmContractsManifest`, D:§Launch fields). The factory's `launchContracts` takes the expected `address[]` and records the artifacts in PFR (`artifactsOf(uint64)`, `launchOf(uint64)`, `deploymentBlock(uint64)`).
- **[FACT] Prediction functions on PF:** `predictContract(uint64,uint256,bytes)` (0xa28e1899) and `predictToken(uint64,bytes)` (0x31316a9a). On LF: `predictToken` and a hook predictor `0x94e81bd1(bytes,uint256)`.
- **[INFERENCE] Consequence.** Each of `SwarmDesk` (word 12 freezes `registryLaunch`, `paramsLaunch`), `PredictGame`, `V4Market` (Params commitment) and `remainderTo` needs launch numbers that do not exist yet at the time each must be frozen. The only window for knowing a number is after the plane assigns it to *that* launch. By then the inputs (constructor args, `remainderTo`) are already pinned in the quote and manifest.
- **[PROPOSAL] Design fix.** Bind by **recorded artifacts**, not pre-frozen coordinates. After deployment, Desk/escrow/hook accept a `(launchNumber, index)` proof checked against `PFR.isRecorded`, `PF.predictContract` and pinned code hashes, supplied at bind time instead of in the constructor. Uniqueness then comes from the factory (deployer-only plus recorded once), which you already rely on.

## Q3: custom hook details

- **[FACT] Pipeline.** For `launch.open` with `onchain:"univ4_hook"`, a planned launch ends in an audit panel (4 `audit-specialist` + `audit-judge`, D:§Skills). Admission checks are provenance, findings, independent_review, bytecode, manifest (with hook flags), protected_invariants and economics (L1316 `admissionChecks`). Then LF deploys token + hook + MerkleDistributor, seeds the pool and initializes it in **one tx** (L1316: 4.09M gas).
- **[FACT] The univ4_hook schema deploys only the token and the hook.** No other contracts. L1316's own objective says so ("the univ4_hook schema deploys nothing else"), and W `manifestContracts` returns `[token, hook]` for univ4_hook.
- **[FACT] Toolchain.** The verifier built L1316 with solc 0.8.26, forge 1.8.3, **`viaIR: false`**, optimizer 200 runs, cancun, **`bytecodeHash: none`** (L1316 `attestation.toolchain`). The docs require `bytecode_hash = "none"` in `foundry.toml` for an imported launch repo (D:§From your repository). BLACKOUT's `foundry.toml` has `via_ir = true` and no `bytecode_hash` line (see Q9).
- **[FACT] Limits.** Deployed bytecode ≤ 24,576 bytes and initcode ≤ 49,152 bytes (W `MAX_DEPLOYED_BYTES_LIMIT`, `MAX_INIT_CODE_BYTES`). No `delegatecall`, `callcode` or `selfdestruct` is recorded per contract (L1316 attestation `opcodes`; treat as screened). Gas ceiling on 4663 is 0.01 ETH per launch (POL 28/30 `gasCeilingWei 10000000000000000`).
- **[FACT] Hook admin.** POL 30 sets `owners.hookAdmin = 0xcecc…a551` (launch wallet). Ownerless hooks like V4Market are unaffected. A hook with an `$owner` arg resolves to the payer.

---

## Q4: order, job types, limits, costs

**[FACT] What each action can do** (D:§Actions, §Open a workflow, §Launch fields; CAPS):

| Step | Correct action / kind | Contracts | Notes |
|---|---|---|---|
| SwarmDesk bootstrap | `launch.open`, `onchain:"evm_contracts"`, `chainId:4663` | 1 | No token. Constructor args: static address/uint/bool/bytes32, `$owner`, `$contract:Earlier`. No ETH. Nothing is called after deploy. |
| Token launch | `launch.open`, `onchain:"univ4_hook"`, `chainId:4663`, `pairWith:"eth"`, `economics:{poolBps:7000, remainderTo}` | token + hook (+ protocol distributor) | Token fixed at 1e9 × 1e18 with plain transfers (D:§Launch fields). |
| App job A | `launch.open`, `evm_contracts` | 8 (max) | Same constructor rules. All or nothing. |
| App job B | `launch.open`, `evm_contracts` | 8 (max) | Cross-launch addresses must be literal words (no `$contract:` across launches). |
| Site | `job.continue` on the project with `build-website`/`frontend-for-contract` + `ipfs`; or a fresh `job.open` with the addresses as inputs | – | `job.continue` gets "its verified addresses" handed over (D:§Continuing a project). Only the original payer can continue. |

- **[FACT] `workflow.open` cannot chain all of these.** A workflow is *one* contracts job → *one* deployment (one `permissions.onchain` kind) → one site (D:§Open a workflow, "runs as two jobs"). You could make the **last** step (job B) a `workflow.open` with `evm_contracts` so its site is built against B's live addresses. Addresses from the earlier launches would have to be supplied in `context`. **[INFERENCE]** the site validator checks only that workflow's deployment.
- **[FACT] Constructor args.** At most 16 per contract (W `constructorArgs.max(16)`). So "16 words?" is correct, but **only static types**. Tuples, arrays, `bytes` and `string` are refused (`unsupported constructor type`), and payable constructors are refused.
- **[FACT] Bytecode limits.** 24,576 deployed / 49,152 initcode (W). Your `artifacts/v37/byte-sizes.json` reports FarmCore at 24,330 and SwarmDesk at 17,157 *under via_ir*. Sizes will change under the verifier's toolchain (see Q9).
- **[FACT] Gas.** Ceiling 0.01 ETH per launch on 4663 (POL 28 `evm_contracts`, POL 30 `univ4_hook`). The launch wallet pays it. **[UNKNOWN]** whether two eight-contract launches (FarmCore ~24 KB, etc.) fit under it at the Robinhood gas price on the day. **Workaround:** run the same manifests on Sepolia (`chainId 11155111`, the default chain) first and read `gasUsed` from the launch tx.
- **[FACT] Cost.** 0.5 IMD per paid action on Ethereum mainnet via x402/Permit2 (CAPS: `amount 500000000000000000`, token `0xd34a…63b7`, payTo `0x4e0f…dbc`). Five steps = **2.5 IMD**, plus schedules at 0.5 IMD per run. Robinhood gas for deployment is paid by the launch wallet up to the ceiling (D:§Payment: "The server's wallet pays the gas"). A safe or contract wallet cannot pay (D:§POST /requests/:id/submit).

## Q5: post-deploy calls

**[FACT]** `evm_contracts` launches call nothing after deployment (D:§Launch fields). A univ4_hook launch only initializes its own pool. So none of the BLACKOUT wiring can be done by the launch job; it needs an ordinary wallet (keeper or anyone). Access rules come from BLACKOUT source; platform-side ones from chain simulation.

| Order | Call | Who can call | Source |
|---|---|---|---|
| 1 | `GameRegistry.register(role, launchNumber, index, creationCode)` × 14 | anyone (proof-based) | `src/GameRegistry.sol` L75 |
| 2 | `SwarmDesk.bind(registry, registryCode, paramsCode)` | anyone, once (`AlreadyDone`) | `src/SwarmDesk.sol` L181 |
| 3 | `V4Market.bindFeeRouter(router, registryLaunch, registryIndex)` | anyone, once; router must have code | `src/V4Market.sol` L117 |
| 4 | `LF.setRequester(tokenLaunchNumber, FeeRouter)` | **only the current requester (paying wallet)**, otherwise `NotRequester` | simulated on LF (Q3e) |
| 5 | Move the 20%: either nothing (direct `remainderTo`) or `EndowmentEscrow.forward(...)` (proposal) | anyone | Q1 |
| 6 | `RewardPool.fundEndowment()` | anyone; succeeds only once the full principal is present | `src/RewardPool.sol` L64 |
| 7 | `LF.claimFees(tokenLaunchNumber)` periodically | anyone | simulated (Q3d) |
| 8 | Keeper: epoch advance, `askBackup`, execute stored answers | anyone (gas only) | `launch-v37.md` step 8; `SwarmDesk.askBackup` L234 |

## Q6: oracle heartbeat

- **[FACT] Schedules can't deliver to another chain.** CHECK on `schedule.create` with your exact `docs/oracle-v37/event.json` plus `deliver:{chainId:4663,…}` returned `blockers:[{code:"invalid_input", detail:"input: Unrecognized key: \"deliver\""}]`. The same body without `deliver` returned no blockers, as did the same body with `consumer:{chainId:4663, verifyingContract:…}`. So `schedule.create` cannot hand results to Robinhood via IntakeDelivery. It produces an attestation readable over HTTP (`GET /oracle/requests/:id/attestation`) that is signed for whatever `consumer` you pin. `deliver` is a feature of the **on-chain Intake** path (D:§A result on another chain). Jobs, launches and workflows are not sold on chain (D:§What it sells).
- **[FACT] SwarmDesk can't take a relayed answer.** `SwarmDesk.onOracleResult` accepts only `msg.sender == intake || msg.sender == delivery` (`src/SwarmDesk.sol` L267–268), and there is no public `submit(attestation, signature)`. Scheduled answers therefore cannot reach the Desk today. The docs recommend exactly such a public submit for missed callbacks (D:§From a contract, "Missed").
- **[PROPOSAL] Two ways to work:**
  - **(a)** Add a permissionless `submit` to Desk that runs the same checks already in `onOracleResult`: attester signature, pinned questionHash, slot/epoch freshness, once per UUID. Then use `schedule.create` (paid on Ethereum, `consumer` = Desk on 4663), and let a keeper relay each attestation.
  - **(b)** Keep the current code and use only `askBackup`, i.e. Robinhood Intake `requestWithFailure` (same-chain callback, 0.5 **Robinhood** IMD per ask, paid from Desk's donated balance and triggered by a keeper). Today this is capped by the code at one ask per stream-slot, at least one hour into the slot.
- **[FACT] Body format for numeric multi-field answers.** `answerType` is one of `bool | address | bytes32 | uint256 | address[] | bytes32[]`. There is no tuple and no `uint256[]` (D:§Ask the oracle). Your 7-word / 17-word `bytes32[]` with `head` = full length is the right shape. CHECK accepted it with `evidence:"panel"`, `allowAmbiguous:true` and the fixed window 26122900–26122901. The answer is `abi.encode(bytes32[])`, `answerType` code 5 (D:§The attestation).
- **[FACT] Attester vs writer.** The attester (EIP-712 signer) is **`0x5598aa9146215bc13eb26f2c692ad1461fd32982`**: `GET /oracle/requests` → `attester`, the sole `signer` across the latest 100 requests. The transport writer, the only caller of Intake `complete` and IntakeDelivery `deliver`, is **`0x3d3c0df7c1a17d384545e9d7c8228897bd9625cb`** (D:§Wallets). The domain is `{name:"IdentityMD Oracle", version:"2", chainId, verifyingContract = consumer}` (D:§The attestation). `launch-v37.md` matches all of this.
- **[FACT] Panel.** `panelSize` 2–100 (min 5 enforced at check). `quorum` is the count of matching answers needed, and every one must match. `quorum_unreachable` is refused at quote when it exceeds the seats active in the last 24h. `panelSize`, `quorum` and `agreed` are signed (D:§Ask the oracle, §The attestation). Your 5/4 is allowed, but the docs warn that "a small panel is cheap to fill" (D:§What a callback proves).
- **[FACT] Latency.** Across the latest 100 oracle requests, attested requests took a median of **1.3 min**, p90 3.6 min and a max of 9.6 min from creation to attestation (n=76). Cross-chain delivery is a separate later tx, not atomic (D:§A result on another chain). The docs say answers come "minutes after the ask, once, and can be late or missing" (D:§What a callback proves).
- **[FACT] Failure.** Network-wide: 7,406 attested, 226 disagreed, 23 blocked, 2 mismatch, 1 refused (`GET /oracle/counts`). In the latest 100, 24 disagreed. Payment buys the question, not an answer, and nothing is refunded (D:§Ask the oracle, §The answer). Failure callbacks are unsigned (D:§When no answer comes). For schedules: a failed run costs nothing, three failures in a row pause the schedule until a top-up, `previous_in_flight` slots are skipped, and missed slots after an outage fire once, late (D:§Schedules). A real example: schedule `3dee67ee…` paused after three `ambiguous_question` failures.
- **[FACT] Cost and refills.** `schedule.create` costs 0.5 IMD (Ethereum) × runs, paid up front, with no refund of unused runs. Floors: 10 min between questions. `schedule.topup {scheduleId, runs}` can be paid by any wallet. The owner has no pause/cancel controls (D:§Schedule work, §Topping up). The Robinhood Intake costs 0.5 IMD of `0x5f7b…7127` per ask; IMD has no `permit`, so the contract approves per ask (D:§What it sells; CAPS `onchain.chains[4663]`). Your cadence arithmetic (4/day + 1/week = 14.5 IMD/week) is correct for the price.
- **[FACT] Callback gas.** 200,000 gas on Robinhood and Ethereum (1,000,000 on Sepolia), once, inside a try (D:§The answer).

## Q7: swarm share

- **[FACT] Fixed at 10%** (`SWARM_BPS() = 1000` on LF and PF, read on chain; D:§Launch fields "The swarm always takes ten percent").
- **[FACT] How it's paid.** The full 100M is transferred to the launch's `MerkleDistributor` in the launch tx (L1316, L1300, L1015 receipts). It is split per POL 30 `rewardRule: equal_connected`: **2%** split equally among wallets with accepted work on the launch, and **8%** split equally among seats connected at admission (`recentContributorWindowSeconds 43200`, `perWalletCapBps 3000`). Contributors claim it themselves with proofs from `GET /launches/:id?claims=1`. L1316 calldata shows `contributorLockSeconds 3600` and a claim window of 31,536,000 s (1 year). **[INFERENCE]** what happens to unclaimed tokens after the window is not documented.
- **[FACT] Interaction with your allocations: none beyond taking 10% off the top.** Your `poolBps` and `remainderTo` divide the remaining 90%: poolBps 7000 leaves 20% for `remainderTo`. Swarm holders can sell into your pool from 1 hour after launch. Plan for up to 100M of sell pressure (INFERENCE).

## Q8: Identity MD holder snapshot

- **[FACT] Contract.** IMD NFT (identity.md, symbol IDMD) on **Ethereum mainnet, chain 1**, `0x0000ec93127baa929e58e97dd0095a2bfb38ec1d` (D:§Contract addresses). It is ERC-721 (`supportsInterface(0x80ac58cd)` = true) and **not** Enumerable (`0x780e9d63` = false). `totalSupply()` = 2000, token ids **0–1999** (`ownerOf(0)` exists, `ownerOf(2000)` reverts `TokenDoesNotExist`). `GET /seats/owners` reports 827 distinct holders at 2026-10-11T18:54Z.
- **[PROPOSAL] Reproducible procedure:**
  1. Pick an Ethereum block **N** that is already `finalized`. It was 26,171,048 when checked; that is a reading, not a recommendation. Record its hash.
  2. `cast call 0x0000ec93…ec1d 'ownerOf(uint256)(address)' <id> --block N` for id 0..1999, using an archive-capable RPC.
  3. Optionally de-duplicate holders, then build the leaves and root with your existing Merkle tools, and publish `(chainId 1, contract, N, blockHash, leaves, root)`.
  4. Cross-check against `GET /seats/owners`. That endpoint is timestamped, not block-pinned, so use it only for comparison.
- **[FACT] Watch out:** `GameRegistry`'s `snapshotBlock` is a bare number. Robinhood blocks (~86M) and Ethereum blocks (~26M) differ by an order of magnitude, so document it as an **Ethereum** block everywhere (UI, proofs, constructor docs).

## Q9: conflicts between `launch-v37.md` and how IMD actually works

| # | launch-v37.md says | Reality | Severity |
|---|---|---|---|
| C1 | Schedules carry `deliver` to Desk on 4663 (lines 52–67) | `schedule.create` refuses `deliver` (CHECK, FACT). Desk has no relay path (FACT). | **Blocker** |
| C2 | "Reserve a small Desk bootstrap plus jobs A and B", "reserved launch numbers/indices" (steps 2–4) | No reservation exists. Numbers come from one global counter and are assigned by the plane (FACT). Indices are just array positions (FACT). | **Blocker** |
| C3 | Hook takes fee/network args and implements the *total* fee | `V4Market` requires `fee_ == 0`. The platform pool is 12,500 on every current 4663 hook launch (FACT). It would also duplicate the 0.25% network fee. | **Blocker** |
| C4 | "1% project to the predicted FeeRouter" | The 1% goes to the paying wallet. It can only be redirected after the fact via `LF.setRequester`, signed by that wallet (FACT). Fees collected before the redirect go to the payer (INFERENCE). For an ETH pair the FeeRouter receives native ETH and needs `receive()` (INFERENCE). | High |
| C5 | Pinned canonical artifacts built with `via_ir = true`; "never recompile" | The verifier rebuilds from source with its own toolchain (L1316: `viaIR false`, `bytecodeHash none`), and the docs require `bytecode_hash = "none"`. `adapt-contract-project` will change the config, the bytecode changes, and `SwarmCode.REGISTRY/PARAMS` hashes and every prediction go stale. **[UNKNOWN]** whether via_ir is honoured at all. Workaround: set `bytecode_hash = "none"` now, re-pin, and rehearse on Sepolia to read the attested `creationCodeHash`. | High |
| C6 | "Separately authorized launcher: pre-fund the predicted RewardPool" (step 6) | The supported path is `remainderTo`, inside the same launch tx, at quote-pinned values. There is no separate pre-funding step and no way to change the recipient later (FACT). | High |
| C7 | "Register and bind" as part of job A/B (job drafts) | `evm_contracts` "nothing is called after deployment" (FACT). These are wallet or keeper transactions. | Medium |
| C8 | `AlreadyLaunched` as the factory error | Not found as `AlreadyLaunched()`/`(uint64)` in either runtime. Single use is still enforced by `isRecorded` + deployer-only + CREATE2 (FACT/UNKNOWN name). | Low |
| C9 | "official launch/hook identities" for authenticated init | For univ4_hook the initializer is LaunchFactory `0xa25b…4645`. `PoolInitializationGuard` is not involved (FACT). | Low (clarify) |
| C10 | Attester `0x5598…2982`, writer `0x3d3c…25cb`, selectors `0x510379c7`/`0xa7980e31`, 200k gas, action id padding, 0.5 IMD | All confirmed (FACT). | OK |

---

## Launch runbook that matches the real platform

Nothing in this runbook was executed. Steps marked ⛔ are blocked until the listed blocker is fixed.

1. **Fix the source (code job, `job.continue` on project 03cb04ff, payer wallet only).**
   - `V4Market` must accept `fee_ = 12500` (or derive its own surcharge on top of the platform fee) and drop its own 0.25% network share.
   - Add a permissionless attested `submit` to SwarmDesk (Q6a).
   - Replace constructor-frozen launch coordinates with bind-time proofs against `PFR.isRecorded` + `PF.predictContract` (Q2).
   - Add the `EndowmentEscrow` (Q1).
   - Set `bytecode_hash = "none"`, then re-pin the code hashes.
2. **Rehearse on Sepolia (11155111)** with the same manifests: bootstrap, token, A, B. Read the attested `creationCodeHash` values, `gasUsed` against the 0.01 ETH ceiling, and the `afterInitialize` `sender`. (Each action still costs 0.5 IMD; the payer decides whether to spend it.)
3. **Freeze the snapshot and roots.** Ethereum chain 1, contract `0x0000ec93…ec1d`, finalized block N + hash (Q8). Build the starter and free-pack roots. These are values only the requester can supply.
4. **Escrow and SwarmDesk bootstrap.** One or two `launch.open` `evm_contracts` on 4663. All addresses are static literals: Intake `0xa43e…de82`, IntakeDelivery `0xce0e…8ccb`, attester `0x5598…2982`, Robinhood IMD `0x5f7b…7127`, PF `0x9c9d…265e`. Record the deployed addresses from `GET /launches/:id`.
5. **Token launch.** `launch.open` `univ4_hook`, `chainId 4663`, `pairWith eth`, `economics {poolBps 7000, remainderTo: <escrow address>}`, hook args with `$poolManager`, `$token`, `$factory` (= LaunchFactory, which is also the initializer) and the gameConfigHash words. Opens at 10 ETH FDV, LP fee 1.25%, tick spacing 60 as observed. The swarm takes 10% automatically.
6. **Job A, then job B.** Each a `launch.open` `evm_contracts` with 8 contracts, ≤16 static args each. Literal token/hook/Desk addresses; `$contract:` only within a launch. Make **B** a `workflow.open` (`permissions.onchain {kind:"evm_contracts", chainId:4663}`, `ipfs:true`) if you want the site built against live addresses in the same order.
7. **Wiring (any wallet or keeper, in this order):** 14 × `register` → `SwarmDesk.bind` → `V4Market.bindFeeRouter` → `EndowmentEscrow.forward` → `RewardPool.fundEndowment`. Then the **paying wallet** signs `LF.setRequester(tokenLaunch, FeeRouter)`. After that, anyone can call `LF.claimFees`.
8. **Oracle.** Donate Robinhood IMD to the Desk for backups, and/or buy `schedule.create` on Ethereum with `consumer:{4663, Desk}` and **no `deliver`**, plus a keeper that relays attestations (only after step 1's `submit` exists). Run the `POST /requests/check` preflight first.
9. **Site.** If not done in step 6: `job.continue` with `build-website`/`frontend-for-contract` and `ipfs`, paid by the same wallet.

## Blockers (requester decisions or inputs needed)

1. **Launch-number dependency (C2, Q1e, Q2).** The plan cannot pre-compute RewardPool, Params, Registry, FeeRouter or SwarmDesk coordinates. Needs the design change in runbook step 1, or an IMD-side reservation feature, which is not documented to exist.
2. **Hook fee incompatibility (C3).** `V4Market` reverts or mismatches at the platform's fixed 12,500 fee.
3. **Heartbeat delivery (C1).** Scheduled answers cannot reach the Desk. Needs a relay `submit` or a backup-only operation.
4. **Fee recipient (C4).** The 1% lands in the paying wallet until that wallet signs `setRequester`. If you want zero personal-wallet involvement, that is not achievable on today's factory.
5. **Toolchain and pins (C5).** The verifier's rebuild settings will invalidate pinned hashes unless they are re-pinned against an attested build.
6. **Requester-only values.** Starter/free roots, snapshot block, final names/symbol, and the paying wallet's choices. None were invented here.
7. **Unknowns to rehearse.** Gas fit under 0.01 ETH for 8-contract launches; whether `tickSpacing` other than 60 is honoured; the exact `AlreadyLaunched` error name; post-window handling of unclaimed swarm tokens.

## Method and limits

- Docs were fetched 2026-10-11 from `https://imd.fun/docs/llms.txt` (126 KB), with CAPS, `/openapi.json`, `/launch/policies` (40 versions), `/launches?limit=500` (455 launches), `/oracle/requests`, `/oracle/counts` and `/schedules`.
- On-chain reads used `https://rpc.mainnet.chain.robinhood.com` and `https://ethereum-rpc.publicnode.com` with cast 1.8.4.
- Worker schemas are from the public bundle, not the plane's source. The plane's own evaluator and screens may refuse things the schemas allow.
- The factory ABI names come from a selector database. Behaviour was verified by calls and traces, but the sources are unverified.
- This is not an audit of BLACKOUT, and no BLACKOUT tests were run.
