# BLACKOUT v3.8 implementation report

Source-only extension of v3.7 (job 03cb04ff). No deployment, broadcast, oracle purchase, token action or mint. `foundry.toml`, dependencies and the 14 pinned modules are unchanged, so every `ModuleCode`/`SwarmCode` pin still matches.

## Delivered

- **No pre-known launch coordinates.** `SwarmDesk` refuses non-zero coordinates in its binding word; `bind(candidate, registryCode, paramsCode, registryLaunch, registryIndex, paramsLaunch, paramsIndex)` proves them with the ProjectFactory prediction and pinned code, then records them. `gameConfigHash` is now `keccak256(abi.encode(starterRoot, freeRoot, snapshotBlock, endowment))` (no token, no Params). `V4Market` takes the Desk and that hash instead of coordinates; `bindFeeRouter(router, registryLaunch, registryIndex)` proves the registry at bind time and accepts only the Params of the registry the Desk bound to. `MarketFactory`, `StandardMarket`, `StandardAdapter`, the deploy rehearsal and the offline encoder follow.
- **EndowmentEscrow** (`src/EndowmentEscrow.sol`): ownerless `remainderTo` target; `forward(...)` sends the whole balance once to `registry.module(0)` after proving the registry (factory prediction, pinned code, recorded launch, Desk bound to it, Params pointing at the Desk) and the pool (factory prediction with pinned RewardPool code). `RewardPool.fundEndowment` then starts the drip (tested end to end).
- **Hook fee 12500.** The constructor accepts only the platform fee; `PoolKey`/`poolId`/`key()` match the real pool; initialization is authenticated against `launcher` = LaunchFactory.
- **Heartbeat relay.** `SwarmDesk.submit(attestation, signature)` applies the same checks as a delivered result (signature in the Desk's domain, pinned question, context window, panel, slot/epoch freshness, once per UUID) and is permissionless. `askBackup` unchanged. Severity is chosen by the attested answer within 5000–7000.
- **Docs.** `launch-v38.md`: blocker table, launch order with literal addresses, wiring calls, objective texts, economy notes, open items. Research report copied to `docs/research/`.

## Tests

New: `test/EndowmentEscrowV38.t.sol` (forward once, authenticated pool funding and drip, wrong code/coordinates/unrecorded launch/look-alike registry, empty balance, constructor inputs), relay tests in `test/SwarmDeskV37.t.sol` (accept once from anyone, replay from relayer and transport, second answer per slot ignored, wrong signer, tampered answer, wrong question, wrong window, small panel, stale, wrong epoch, severity clamp), Desk bind-time coordinate tests (stale constructor words refused, wrong registry/Params coordinates, zero coordinates), strict hook twin-registry test in `test/ReviewV34.t.sol`. Existing hook, integration, Desk, factory and deployment suites updated to the new constructors and pass locally (`forge build` passes under the unchanged configuration). Full `forge test`: 251 passed, 0 failed, 1 optional fork test skipped (43 suites); `forge fmt --check` passes.

## Not done / blockers left (see launch-v38.md "Open items")

1. Hook fee math: drop the hook's own 0.25% network share, make the post-launch buy charge exactly 1% to rewards and remove the team half of `FeeRouter._base` (module re-pin, fee assertions in five test files).
2. `foundry.toml` is protected in this job: `via_ir = false`, `bytecode_hash = "none"`, re-pin, FarmCore split if needed.
3. Severity floor 3000 (GridOperator change + re-pin); the Desk band is 5000–7000.
4. Balanced simulation re-run with 10 ETH FDV and the one-hour swarm unlock; keeper relay/wiring commands and UI updates; Sepolia rehearsal; second-contributor review of this diff.
5. Residual trust: a registry twin launched through the IMD factory with identical configuration before the keeper runs `Desk.bind` could capture the Desk; wire immediately after job A and verify `Desk.registry()` before the escrow forward.

---

# Historical v3.7 report


Source-only extension of v3.6 (job c379f49a). No deployment, broadcast, paid oracle request, schedule purchase, token action or mint was performed. Existing build configuration and dependencies are unchanged. The [previous report](docs/report-v36.md) preserves historical v3.6/v3.5 results; this report supersedes their wallet-based launch instructions.

## Delivered changes

- **Oracle-only swarm authority.** New non-upgradeable SwarmDesk is Params.swarmWallet, which every swarm-gated module resolves. It has no owner, admin setter, arbitrary-call executor or withdrawal. Its permissionless one-time binding verifies canonical Registry/Params creation code, frozen game configuration, authenticated factory coordinates and Params pointing back to this Desk. The constructor makes no external calls and uses fourteen flat static words, compatible with the launcher's encoding and sixteen-word limit. Solidity and offline JavaScript helpers pack and validate the configuration. The launch uses a separate Desk bootstrap followed by the existing two eight-contract jobs because the factory admits at most eight contracts per job.
- **Attested heartbeat.** Canonical 15-field EIP-712 attestation verification accepts only Intake or IntakeDelivery callers and the two precommitted question hashes. It checks context window, chain, panel agreement, current signed slot, current event epoch and freshness. Oracle UUIDs, transport ids and stream/slot quotas prevent repeated execution. Direct results additionally require an outstanding request created by Desk. Receipt verifies and stores under the protocol's 200,000-gas stipend; permissionless execution must present the exact committed answer bytes. Stale/duplicate answers never change policy. Failure callbacks cannot authorize actions.
- **Bounded proposals.** Event vectors submit the original next two epochs without replacing an existing plan; district hints stay advisory and existing future-block entropy remains. Parameter updates retain hard bounds and 10%/24-hour steps. Civic features still require announcement plus 48 hours, and enhancement remains +8 → +12 → +16 with notice and 30-day steps. Existing optional pause, boost and dormant actions are available only through bounded oracle fields and retain module gates. No-answer event fallback is unchanged.
- **Launch administration removed.** Packs are fixed to Balanced (1); selectProfile is removed. Free-pack and Identity MD roots/snapshot are immutable constructor inputs; setFreeRoot is removed and free claims retain the 30-day window. Billboard moderation is removed. RewardPool activation requires the full endowment already at its predicted address; it never pulls missing principal from a caller or swarm wallet. Ordinary accounted donations/revenue do not substitute for principal.
- **Backup and operations.** Anyone may donate Robinhood IMD to Desk. A keeper can purchase only a byte-exact frozen requestWithFailure body, at most once per stream/UTC slot after an hour, using a price no higher than the constructor cap. Keeper status exposes the last answer, pending execution, balance and failure; its normal pass executes stored answers before advancing epochs. UI shows accepted oracle values and the next submitted plan or fallback. Gas payers receive no signing authority over proposals.
- **Launch kit.** [launch-v37.md](launch-v37.md) provides verified protocol interfaces/addresses, exact question and answer definitions, deterministic body/hash tooling, schedule cadence/costs, ordered launch steps, bootstrap and A/B objective drafts, funding requirements and responsibilities. Canonical deployment artifacts must be used: recompiling the flattened hook changes embedded Registry metadata and breaks binding. [Contract sizes](artifacts/v37/byte-sizes.json) show every launch runtime below EIP-170; FarmCore source is untouched and its runtime remains 24,330 bytes, leaving 246 bytes. SwarmDesk is 17,157 bytes.

## Protocol verification and cost

Current [IMD docs](https://imd.fun/docs/) and [capabilities](https://api.imd.fun/requests/capabilities) were checked on 2026-10-11. Intake v2, IntakeDelivery and the payment assets match the brief/reference. Read-only RPC verified the 0.5 IMD price and live Intake transport writer. The protocol attester is **0x5598aa9146215bc13eb26f2c692ad1461fd32982**, distinct from the transaction writer **0x3d3C0Df7C1a17d384545e9D7C8228897bD9625CB**. SwarmDesk uses the attester for signatures. The canonical consumer was copied with only an adapter for the existing OZ memory signature-checker API. Independent published digest/signature and five official question-hash vectors are permanent tests.

| Heartbeat | Cadence | IMD cost |
|---|---|---|
| Event | Four per day | 2/day |
| Regulator | One per week | 0.5/week |
| Scheduled total | 29 requests/week | **14.5/week, approximately 2.07143/day** |
| Initial balances in supplied schedule drafts | 28 event runs + 4 regulator runs | 14 + 2 IMD |
| Example 30-day period with five weekly runs | 120 + 5 requests | 62.5 IMD |
| Optional backup ceiling | At most another 29/week | Up to another 14.5/week |

Costs exclude chain gas and can change upstream; the fixed backup price ceiling makes a price increase fail safely. Failed requests consume their price, and no refund is promised. Relative observation windows would change question hashes, so recurring bodies use a verified fixed absolute context window and explicitly request current game state. Slot/epoch/freshness checks remain independent of that anchor. Anyone may pay for the exact pinned question; payer identity is not authenticated or claimed.

## Validation

All checks used the repository's unchanged pinned Solidity 0.8.26 configuration. No network is needed for default verification.

| Check | Result |
|---|---|
| `forge build` | Passed |
| `forge test` | **244 passed, 0 failed, 1 optional live-RPC fork skipped; 42 suites** |
| `forge fmt --check` | Passed |
| Module and Swarm creation-code pin checks | Passed |
| Authority source scan plus deployed-graph/unauthorized-selector tests | Passed |
| Python unit tests | 34 passed |
| Node oracle, reveal and UI test files | Passed |
| Keeper/UI JavaScript syntax checks | Passed |
| Protected paths and `git diff --check` | Passed |

New success/failure tests cover forged, tampered and wrong-signer/domain/caller results; unknown direct ids; wrong question/window; insufficient agreement; UUID/source/slot replay; expired/old/future answers; malformed type/length; separate receipt and execution; modified execution bytes; later-slot recovery; cold Robinhood native-block callback under 200,000 gas; paid backup approval/price/body/rate limits; unsigned failure and timeout clearing; bounded event plans and fallback; all 45 Params keys under fuzzed targets; 48-hour feature releases and 30-day cap progression; immutable roots/profile; absent moderation/admin selectors; binding tampering and unique factory coordinates. Existing economic, hook, PoolManager, lazy-settlement, conservation and stateful invariant suites remain passing. Tests demonstrate local behavior, not production panel availability.

A second contributor independently reviewed the v3.7 diff and ran focused verification: [review record](docs/review-v37-independent.md). Review corrections include packing constructor configuration into launcher-compatible static words, authenticating the factory's unique launch admission, preserving current-epoch liveness by reading native latest-minus-five rather than a lagging finalized tag, distinguishing attester from transport writer, documenting canonical artifacts, and adding adversarial tests. This is a bounded contributor review, not a comprehensive external audit. Slither/Mythril and paid production callback tests were not run.

## Assumptions, open inputs and responsibilities

1. **Requester/launcher supplies real launch inputs:** existing token/hook identities, canonical factory and reserved launch coordinates, both frozen lists/roots, Identity snapshot, and schedule target/ids. No production value was fabricated. Oracle config/body files are complete except routing that necessarily uses the real Desk address; the offline generator adds that routing when supplied.
2. **No mutable rescue authority.** Endpoint, signer, action, asset, price ceiling and question commitments are constructor-frozen, as required by the no-admin brief. This intentionally supersedes the oracle reference's owner-settable example. A protocol migration requires a separately reviewed application replacement; fallback behavior remains available in the old deployment.
3. **Initial policy is explicit.** Event proposals follow the existing fallback-kind table with severity 9000; the number is a public epoch salt. Weekly regulation targets conservative defaults, notices growth features at the documented ages, and makes dormant features eligible only at days 90/120/150. These immutable question-policy choices must be reviewed before launch. Existing on-chain safety limits apply even to a different attested numeric answer.
4. **Endowment pre-funding is mandatory.** Preserve the approved 20% endowment at the predicted RewardPool. If the launcher cannot allocate there, stop the launch and select a separately reviewed direct-allocation path or revise the launch plan. There is no swarm wallet fallback.
5. **Payers/operators own liveness.** Fund/refill Ethereum schedules and optional Robinhood backup IMD, sponsor execution gas, enable elapsed notices, capture entropy and advance epochs. Schedule creation, live admission/consumer-context rehearsal, site publishing and every transaction require separate authorization; none occurred here.
6. **Trust and entropy limits remain.** Oracle truth relies on the external panel and one protocol attester; unavailable or stale answers leave bounded fallback. Existing future-block randomness remains sequencer-influenced, without a VRF claim. Exact deployment predictions rely on the authenticated factory allowing each reserved launch only once. Frozen roots and question policy cannot be repaired after launch.
