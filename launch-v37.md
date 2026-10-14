# BLACKOUT v3.7 — source-only launch and oracle runbook

No deployment, broadcast, schedule purchase, token launch, transfer or mint was performed by this assignment. This supersedes `launch-v36.md` and the older wallet-based launch steps. X: https://x.com/IMDBlackout · https://playblackout.xyz · https://playblackout.xyz/freepack.

## What is frozen

SwarmDesk is the immutable `Params.swarmWallet`; all other swarm-gated modules resolve it through Params. It has no owner, signer setter, proxy, arbitrary-call executor, asset withdrawal or EOA bypass. The oracle's external attester is a protocol trust dependency, not a game administrator. Endpoint/action/asset/signer changes require a separately reviewed application replacement; old games continue their existing no-answer fallback. This explicitly overrides the reference consumer's owner-settable configuration example.

Balanced profile 1 is fixed immediately. The free-pack root, Identity MD root and snapshot block are GameRegistry constructor arguments. Free claims close at authenticated launch +30 days; the existing Identity MD window (48 hours through day 16) remains unchanged. Billboard moderation is removed; bids, display, settlement and refunds remain. Letters are off-chain; modules receive only the attested letter hash rendered as hex.

## Verified protocol configuration

Checked 2026-10-11 against [current docs](https://imd.fun/docs/#onchain) and [capabilities](https://api.imd.fun/requests/capabilities). Oracle struct/domain/signature are copied from the supplied canonical reference. The pinned OZ version has only the memory signature checker, so a small internal adapter preserves the canonical call's semantics without changing dependencies.

| Field | Robinhood launch value |
|---|---|
| Consumer chain | 4663 |
| Intake v2 | `0xa43e6f75ee006411f79ac1c84120606c2330de82` |
| IntakeDelivery | `0xce0e6a670aa75e161d02aca3c7f00b94ca428ccb` |
| Oracle attester | `0x5598aa9146215bc13eb26f2c692ad1461fd32982` (pinned reference and live attestation signer verified) |
| Intake transport writer (read-only verification) | `0x3d3C0Df7C1a17d384545e9D7C8228897bD9625CB` — distinct from the attester |
| Backup payment asset | Robinhood IMD `0x5f7bb59365ce557c26dbcaa4ee9d39a4b95b7127` |
| Ethereum schedule payment asset | IMD `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Action | UTF-8, right-padded `bytes32("oracle.request@oracle-1")`, **not keccak** |
| Backup maximum price | `500000000000000000` atomic IMD (0.5 IMD); actual price read from `priceOf(action,asset)` |
| Result selector | `0x510379c7` |
| Failure selector | `0xa7980e31` |
| Panel | At least five seats, quorum at least four, agreed >= quorum and <= panelSize |

Canonical callback: `onOracleResult(bytes32,(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64),bytes)`. The brief calls the signer the Intake writer; the live protocol separates the EIP-712 attester from the transaction writer. SwarmDesk trusts the attester signature and requires the callback contract as msg.sender. The intake id (first argument) differs from the attested request UUID. Failure: `onOracleFailure(bytes32,uint8,bytes32,uint16,uint16,bytes)`. The EIP-712 domain is `IdentityMD Oracle`, version `2`, destination chain id, and **SwarmDesk**, never Intake.

## Exact questions, bodies, schedules and cost

The exact, compact, UTF-8 bodies are [event.json](docs/oracle-v37/event.json) and [regulator.json](docs/oracle-v37/regulator.json). Preserve every byte for backup calls (including the absence of a trailing newline). The complete constructor oracle config and both question/body commitments are [oracle-config.json](docs/oracle-v37/oracle-config.json). Regenerate reproducibly, offline, with `node tools/make_oracle_bodies.mjs`; `node test/oracle-v37.test.mjs` checks them and five independent official hash vectors.

Event question text: “What is the current BLACKOUT v3.7 six-hour event plan vector [UTC slot, base epoch, event kind, severity, district hint, swarm number, letter hash], following the definitions exactly?”

Weekly question text: “What is the BLACKOUT v3.7 weekly regulator vector of exactly 17 words [UTC week slot, eight packed Params updates, feature code, cap step, district boost, pause code, war code, collapse goal, lot code, letter hash], following the definitions exactly?”

Definitions are part of the question commitment, not optional commentary. The supplied launch policy uses the existing fallback-kind table for event proposals, severity 9000, epoch modulo 8 as an advisory district, and the public epoch number as salt. Valuable event outcomes still use v3.6 future-block entropy and weighted district selection; this is not VRF. The weekly policy gently returns eight Params to conservative defaults and announces growth features at minimum ages 7, 21, 35, 42 and 63 days (ids 3,4,5,6,7). It announces cap 12 from day30, cap16 from day60, subject to existing gates. Dormant features 0–2 remain disabled initially and become eligible for oracle notice at days90/120/150, respectively. Once enabled, the policy may start a weekly war, a collapse at most every fourth week when idle, and a weekly Rare limited lot. Boost/pause proposals are zero in this initial policy. These delayed eligibility choices are explicit deployment-policy assumptions, not new hard-coded module gates. Changing the immutable question policy after deployment is impossible. Review policy before freezing constructor hashes.

Both bodies use `evidence:"panel"` with fixed absolute Ethereum context blocks **26122900–26122901**. These existing blocks also appear in the official [fixed-context recurring-observation example](https://api.imd.fun/oracle/requests/fbc6c024-726e-496d-918d-aa4c69046bc2?members=0). Definitions explicitly ask for current BLACKOUT state from the request's consumer on Robinhood, at native latest minus5 soft confirmations with an epoch recheck. Do not use the RPC finalized tag: observed finalized state lagged latest by about20 minutes during review and would miss current epochs. They do not ask about historical game state at the anchor. No Desk or Registry address occurs in immutable question text or the backup body, avoiding a CREATE2 dependency cycle. Intake supplies consumer metadata from the callback; schedules supply it through `deliver`.

This is deliberate: schedules freeze inputs and cannot substitute epoch ids or absolute windows. A relative window changes questionHash every run. Here, a recurring question is accepted once **per signed UTC slot**, and each oracle UUID and transport request id is accepted once. An unrelated payer can pay for this exact question and deliver first; they cannot change its definitions, answer format, slot or contract domain. Freshness is bounded independently of expiry. Event answers must name the current game epoch and current six-hour UTC slot; regulator answers must name the current seven-day UTC slot and be at most one day old. UTC week slots begin Thursday. Two streams share their quota across schedules and backups.

For a real predicted/deployed Desk, run locally:

```sh
node tools/make_oracle_bodies.mjs REAL_SWARM_DESK_ADDRESS
```

This writes exact full `schedule.create` request bodies `docs/oracle-v37/event-schedule.json` and `regulator-schedule.json`; it creates no schedule or payment. They wrap the committed question as follows:

```json
{
  "action": "schedule.create",
  "input": {
    "label": "BLACKOUT v3.7 event",
    "action": "oracle.request",
    "cadence": {"cron": "5 */6 * * *", "tz": "UTC"},
    "runs": 28,
    "input": "THE FULL event.json OBJECT WITH deliver ADDED"
  }
}
```

The quoted placeholder above describes composition, not a submit-ready body; use the generator for the full body. `deliver` is `{ "chainId":4663, "target":REAL_SWARM_DESK_ADDRESS, "selector":"0x510379c7", "onFailure":"0xa7980e31" }`. The regulator uses cron `5 0 * * 4`, label `BLACKOUT v3.7 regulator`, and `runs:4`. `deliver` is excluded from questionHash. Never add a same-chain callback alongside it. Schedules are bought using the Ethereum paid-request flow from the docs; no wallet belongs to the swarm. Anyone may pay to top up a schedule with `{"action":"schedule.topup","input":{"scheduleId":"ACTUAL_SCHEDULE_UUID","runs":28}}`. Do not submit a made-up UUID.

Cadence is four event questions/day plus one weekly question. At the verified price: **2 IMD/day +0.5/week =14.5 IMD/week ≈2.07143 IMD/day**, or 62.5 IMD in a 30-day interval containing five weekly runs. Initial suggested purchases are 14 IMD for 28 event runs (7 days) and 2 IMD for four weekly runs. Work may be refused or fail to reach agreement; the price is spent once opened and no refund is promised. Skipped schedule slots are not queued. Schedule overhead is included in the per-run price; keeper/delivery gas is separate.

Backup Intake asks use `requestWithFailure`, exact committed bodies, exact temporary allowance and a fresh price check. Anyone can top up the Desk with Robinhood IMD. At most one backup per UTC stream slot is payable, at least one hour into the slot, and only before an answer was accepted. Worst-case optional backups add another 14.5 IMD/week, so the combined ceiling is 29 IMD/week at today's price. Anyone can consume this explicitly budgeted backup quota; do not fund an unrestricted treasury. Failures do not allow same-slot retries. There are no withdrawals or administrative transfers.

`POST /requests/check` is a free preflight, **not** the full oracle input endpoint: it takes question, panelSize and optional answerType/evidence/chainId/toleranceBps/head only. Sending the full body there yields `invalid_request`; the docs state this distinction. Schedule preflight takes the complete schedule body. A separate launch operator must verify current admission/available seats with these exact definitions before buying; this assignment bought nothing.

## Numeric answer layout

All values are `bytes32[]` (type code5), encoded as `abi.encode(bytes32[])`. `head` equals the entire array length, so agreement covers every word. No invented tuple or unsupported `uint256[]` answer type is used.

Event: exactly seven words: `[floor(now/21600), currentEpoch, kind, severity, districtHint, publicSalt, letterHash]`. Kind clips to 0–7 until feature7 is enabled, then 0–9; severity clips to 5000–10000; district hint clips to0–7 and never overrides weighted selection. One answer submits to the original base+1 and base+2 through `submitPlan`; already-submitted or begun epochs are not overwritten. Delayed execution cannot retarget new epochs. No answer leaves the existing fallback table and quotas intact.

Regulator: exactly 17 words:

| Words | Meaning |
|---|---|
| 0 | `floor(now/604800)` |
| 1–8 | Packed Param update `(key+1)<<248 | target`. Zero key skips; key clips to1–45. Target clips to hard bounds and ±10%; unchanged/cooldown updates skip. Zero target means propose the lower bound, not no-op. |
| 9 | Feature id+1, zero skips; clips1–8 then calls announce once |
| 10 | Zero skips; nonzero requests the next cap step (8→12→16), never jumps or lowers |
| 11 | `(district+1)<<128 | boostBps`; bounded district0–7, boost0–1500; once/week |
| 12 | 0 none,1 unpause, otherwise pause seconds+1 clipped to1–72h; existing cooldown applies |
| 13 | `(districtA+1)<<128 | (districtB+1)`; both bounded0–7; existing war state and feature gates apply |
| 14 | Collapse goal in token units, zero skips; bounded1–100 current average farm yield-days; existing civic gate applies |
| 15 | `(kind+1)<<16 | rarity<<8 | supply`; kind0–11, rarity1–3, supply1–3; once/week, feature gate applies |
| 16 | Off-chain letter hash, zero means none |

Optional civic actions that cannot currently run emit `ActionSkipped` and do not prevent a valid notice/Params update. Receipt and execution are separate; only receipt runs inside the writer's 200,000 gas. All execution bytes must match the stored commitment. Anyone may execute or expire a stored answer; late answers never revive old actions. Unsigned direct failure clears only a pending ask made by this Desk; delivery failure only emits telemetry. Permissionless timeout clearing handles lost callbacks.

## Ordered launch steps and responsibilities

1. **Contributor/reviewer: freeze and verify source.** Use pinned solc0.8.26 and unchanged Foundry config. Run `forge fmt`, `forge build`, `python3 tools/pin_module_code.py`, rebuild, then `python3 tools/pin_swarm_code.py`, `forge fmt`, rebuild. Check both pin scripts with `--check`, `forge test`, `forge fmt --check`, `python3 tools/check_v37_authority.py`, and Node tests. Regenerate `launch/V4Market.sol` with `forge flatten src/V4Market.sol --output launch/V4Market.sol`. Archive the canonical Foundry artifacts for deployment. The flattened file is a source reference only: independently compiling it changes embedded GameRegistry metadata/creation code and breaks authenticated binding to the canonical Registry. Any Solidity metadata change requires reviewing pins and predictions again.
2. **Requester: freeze actual inputs.** Supply actual existing/predicted BLACKOUT token, both final Merkle roots and Identity snapshot block, official launch/hook identities, application factory and reserved launch numbers/indices. Roots cannot be corrected later. Build and publish approved proofs using the existing Merkle tools. No fake root, empty allocation list, test signer, EOA swarm address or guessed deployment coordinate is acceptable. The code deliberately takes constructor inputs; none was guessed here.
3. **Launcher: reserve a small Desk bootstrap plus jobs A and B.** There are now 17 contracts; the application factory permits at most8 per launch. A standalone one-contract SwarmDesk bootstrap is required in addition to the existing two eight-contract jobs. Do not silently exceed the limit or put an EOA in Params. Desk BindingConfig commits factory, Registry/Params coordinates, heartbeat values and `keccak256(abi.encode(token, starterRoot, freeRoot, snapshotBlock, endowment))`.
4. **Launcher: predict in dependency order.** Use the exact accepted canonical artifacts from step1, including V4Market; never substitute a separately compiled flattened hook. First SwarmDesk from its fourteen static constructor words (encoding below); then Params(Desk,200,1 ether); then the custom market/hook with its gameConfigHash; then Registry, RewardPool and FeeRouter using `PredictGame` and the factory's read-only `predictContract`. `PredictGame.commitment` and `V4Market.bindFeeRouter` now also include freeRoot. Desk deliberately does not commit market address because the market already commits Params. This breaks the transitive CREATE2 cycle.
5. **Launcher: verify canonical factory trust.** Live Robinhood factory `0x9c9d2fcb75c2c132c0ac0c42df3819a42347265e` authenticates its deployer and rejects a recorded launch number (`NotDeployer`, `AlreadyLaunched`). Binding trusts that unique admission at the reserved coordinates. A permissionless factory that can deploy alternate initcodes at the same coordinate is unsuitable. Compare the actual factory and canonical code before launch. Desk separately verifies pinned Registry/Params creation code, frozen roots/token/endowment and exact prediction, so callers cannot choose a replacement registry or Params. Constructors make no external calls.
6. **Separately authorized launcher: pre-fund the predicted RewardPool.** Retain the v3.6 chosen 20% (200M of1B) endowment and other approved allocations; no token change is authorized by this job. **If the launcher cannot allocate directly to the predicted RewardPool, do not launch.** Use a separately reviewed launcher path supporting direct predicted-address allocation, or request a revised launch plan. Never route endowment through a swarm wallet or fake recipient. The contract no longer pulls missing principal from the caller; ordinary donations/revenue do not count toward it.
7. **Separately authorized launcher: create bootstrap/A/B, register and bind.** Each canonical module takes Registry only; Registry now takes eight args. Anyone can register the14 exact modules. Anyone can call Desk.bind with canonical Registry/Params creation bytes once. Bind FeeRouter through the authenticated market path. Check Params.swarmWallet==Desk, all modules reference the canonical registry, both roots and code sizes, profile==1, and all features disabled. `script/Deploy.s.sol` rehearses this locally, without environment reads or broadcast, with ABI-encoded OracleConfig in Config.oracle to avoid a solc0.8.26 nested-tuple codegen limit.
8. **Anyone: activate funded endowment and start epoch/keepers.** `fundEndowment()` succeeds only if all unaccounted principal is already in the pool; anyone may activate the drip. Pack readiness still requires correct hook binding, funded endowment and the one-hour authenticated launch delay. No profile/root/admin transaction exists. Execute stored answers before advancing due epochs; capture entropy promptly. Oracle execution/backup calls have no new game bounty; operator gas sponsorship is required.
9. **Requester/payer: create two schedules with actual Desk routing.** Review generated full bodies and current prices; fund their Ethereum IMD run balances. Optionally top up Desk's Robinhood IMD backup balance. This is external payment responsibility, not a signing capability of the swarm. Public status and fallback continue if either balance is empty.
10. **Site/operator: publish Registry and frozen proofs.** Deploy the updated static `ui/` through a separately authorized website job. It shows last accepted oracle values, pending execution and the next epoch's submitted plan/fallback. Run `keeper/keeper.mjs status` then `once --dry-run`. Keep two independent permissionless gas payers if desired; neither can create a plan or notice without an attested answer.

## Objective drafts for later, separately authorized jobs

**Bootstrap prerequisite:** Deploy only SwarmDesk from the accepted v3.7 commit using the fourteen flat words encoded from reviewed OracleConfig and BindingConfig, actual reserved A coordinates and canonical factory. No key, owner, upgrade, token operation or placeholder. Record its address and require it to equal the reviewed prediction. This draft is not deployment authorization.

**Job A:** BLACKOUT application job A, after the reviewed SwarmDesk bootstrap. Use exactly the accepted v3.7 bytecode with solc0.8.26: Params, GameRegistry, RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim. Params(Desk,200,1000000000000000000). GameRegistry(actual token,Params,actual hook,Identity starterRoot,freeRoot,snapshotBlock,200000000000000000000000000,applicationFactory). Other constructors take Registry. Both lists are frozen before deployment. Check every predicted address, especially RewardPool. No token deployment, replacement, mint, swarm EOA, owner or upgrade. Balanced packs are fixed; roots cannot be set later. Register exact modules and verify Desk binding when prerequisites exist. Stop on any mismatch. Project https://playblackout.xyz / https://x.com/IMDBlackout.

**Job B:** BLACKOUT application job B from the same accepted v3.7 commit: FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards. Every constructor takes actual Registry from A. Require FeeRouter to equal the approved fee recipient prediction. Finish permissionless registration of all14 roles, Desk's authenticated bind and hook/router binding. Swarm authority is solely SwarmDesk via Params. All8 features start disabled; oracle announcements retain48h notice and cap timing. No token operations, admin wallet, profile selection or free-root setter. Deliver addresses/ABIs to the separately authorized site operator. This draft alone does not authorize transactions.

## Constructor encoding for the launcher

The launcher's manifest encoder accepts at most sixteen **static words**, not tuple or array arguments. SwarmDesk therefore takes fourteen ordinary address/bytes32/uint256 arguments. `OracleConfig` and `BindingConfig` are convenient internal/getter types, not constructor ABI tuples. The canonical encoder is `script/SwarmArgs.sol`; the offline equivalent is:

```sh
node tools/swarm_constructor_args.mjs docs/oracle-v37/oracle-config.json approved-binding.json
```

`approved-binding.json` must contain the actual `factory`, `registryLaunch`, `registryIndex`, `paramsLaunch`, `paramsIndex`, `gameConfigHash`, `heartbeatBps` and `heartbeatCap`. The launch default is 200 bps and exactly 1000000000000000000 wei; no example address/root/coordinate is supplied. This command prints a `constructorArgs` array for review and makes no manifest, payment or transaction.

| Word (zero-based) | Type and value |
|---|---|
| 0–3 | address: Intake, IntakeDelivery, attester, Robinhood IMD |
| 4–5 | bytes32 action; uint256 maximum price |
| 6 | uint256 context: `questionChain | fromBlock<<64 | toBlock<<128`; bits192–255 zero |
| 7–8 | bytes32 event and regulator question hashes |
| 9–10 | bytes32 exact event and regulator backup body hashes |
| 11 | address authenticated application factory |
| 12 | uint256 binding: `registryLaunch | registryIndex<<64 | paramsLaunch<<72 | paramsIndex<<136 | heartbeatBps<<144`; bits160–255 zero |
| 13 | bytes32 `keccak256(abi.encode(token,starterRoot,freeRoot,snapshotBlock,endowment))` |

Chain/window/launch numbers occupy64 bits, indices occupy8 bits but must be0–7, and heartbeat bps occupies16 bits with its existing200–5000 bound. The heartbeat cap is derived as exactly1 ether. Nonzero high padding bits revert; neither encoder silently truncates oversized values. Concatenated ABI words are448 bytes. Confirm getters reproduce the approved input after deployment.

## Open launch inputs and operational limits

Actual deployment coordinates, token/hook identifiers, frozen eligibility lists/roots/snapshot, and future schedule ids remain requester/launcher inputs. The constructor scheme and offline scripts make this implementation reviewable without inventing them. A launcher that cannot pre-fund the predicted pool is an explicit launch stop. Current API admission/consumer-context availability and live callback routing must be confirmed by a separately authorized launch rehearsal; local mocks prove code behavior, not production panel liveness. The unchanged future-block randomness is sequencer-influenced. Oracle truth relies on a5-seat panel and one attester key; failures/withholding leave bounded fallback behavior. The second contributor's findings and local test results are in the v3.7 report/review. This work is not a comprehensive external security audit.
