# BLACKOUT v3.9 / v3.10 / v3.11 / v3.12 report

Source only. No deployment, broadcast, oracle purchase, schedule, token action or mint. v3.10 finishes v3.9
(job 14aa1d96). **No contract source changed in v3.10**: every module, Registry, Params, SwarmDesk,
EndowmentEscrow and hook build is byte-identical to the v3.9 pins. The v3.8 report is archived at
[docs/report-v38.md](docs/report-v38.md); earlier ones are in `docs/`.
https://playblackout.xyz · https://playblackout.xyz/freepack

## Changes

### v3.9 (job 14aa1d96, contracts)
- **Fees.** The hook has no network share. After the 30-minute stepped launch tax (90/50/25%, all to rewards)
  it adds exactly 1% to rewards on every swap, plus the progressive sell surcharge (cap 15%). `FeeRouter._base`
  sends 100% to reward ETH. The team's swap income is the platform 1% via `LaunchFactory.claimFees`. Pool fee
  12500.
- **Toolchain pins.** `ModuleCode`/`SwarmCode` pin both the IMD verifier build (viaIR false, bytecode_hash
  none) and the repository's via-IR build. Every runtime is under 24,576 bytes on both (FarmCore 21,987 /
  24,330). The SwarmDesk constructor is twelve words.
- **Severity floor 3000** in GridOperator; the Desk band is 5000–7000.
- **Keeper:** attestation relay, `wire` command (bind-desk with `Desk.registry()` check, register,
  bind-router, forward, fund, claim-fees). UI wiring status. Simulation `sim/run_v39.py`.

### v3.10 (this job, tests, tools, docs)
- **Launch toolchain tests.** The suite now compiles and passes with `FOUNDRY_VIA_IR=false
  FOUNDRY_BYTECODE_HASH=none`. Four stack-too-deep sites were refactored in tests only:
  `EndowmentEscrowV38.t.sol`, `LazyAccounting.t.sol` and two in `SwarmDeskV37.t.sol`.
- **Review fix M-1.** `tools/schedule_bodies.mjs` and `make_oracle_bodies.mjs` now generate `schedule.create`
  bodies with `consumer {4663, Desk}` and no `deliver`. `test/oracle-v310.test.mjs` covers it.
- **Regression tests.** `test/V310.t.sol` checks that the build's own 14 modules plus Registry and Params match
  one toolchain's pins together. `testTwinWithForeignTokenCannotDrainEscrow` covers the bounded part of M-2.
- **Docs.** [launch-v39.md](launch-v39.md) is the final ordered runbook (fork rehearsal since v3.11, then 4663) with
  objective texts, inputs and on-chain checks per step. [docs/review-v39-independent.md](docs/review-v39-independent.md)
  is the review.

## Tests on both toolchains

| Check | IMD verifier toolchain (`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none`) | Repository toolchain (`foundry.toml`, via-IR) |
|---|---|---|
| `forge build` | Passes (v3.9: failed, stack too deep) | Passes (~10 min compile) |
| `forge test` | **262 passed, 0 failed, 1 skipped** (optional live-RPC fork), 45 suites | Full suite 259/0/1 before the v3.10 additions. The four changed or new suites were re-run afterwards: 36/36 passed. Total 262 passed, 0 failed, 1 skipped |
| `forge fmt --check` | Passes | same |
| Pins (`tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check`) | All 14 modules plus Registry/Params match; every runtime ≤ 24,576 | same |
| Flattened `launch/V4Market.sol` | Byte-identical to `src/V4Market.sol` and embeds `REGISTRY_LAUNCH` | n/a |
| Node: `oracle-v37`, `keeper-v39`, `oracle-v310` | Pass | — |
| v3.11 fork rehearsal `test/fork/RehearsalV311.t.sol` (needs a 4663 fork; skips offline) | 5 passed on the anvil fork (`artifacts/v311/rehearsal.log`) | compiles; skips offline |

Logs are in `artifacts/v310/`. The repository toolchain's full run was not repeated after the last test edits
because of its ten-minute compile; the edited suites were re-run on it.

## Simulation (Balanced, 35 days, five seeds, medians; from `artifacts/v39/simulation.md`)

| Scenario | v3.6 team ETH | v3.9 team ETH (swarm sells 50% day 1) | v3.6 drawdown | v3.9 drawdown | v3.6 week-1 payback | v3.9 week-1 payback |
|---|---:|---:|---:|---:|---:|---:|
| steady | 3.579 | 3.586 | 1.8% | 7.5% | 3.75 d | 3.75 d |
| weak | 0.917 | 0.914 | 0.7% | 11.2% | 4.25 d | 4.25 d |
| hype | 4.996 | 5.008 | 1.9% | 2.2% | 3.50 d | 3.25 d |

v3.6 used 11.1 ETH FDV and no swarm sales; v3.9 uses 10 ETH FDV and the swarm's 10% claimable after one hour.
The fee rework does not move team income: the team gets 1% of volume plus 10% of packs and of the surcharge
in both. The swarm sales set the larger drawdown in the first day. These are conditional model outputs, not
predictions. v3.10 did not re-run the simulation because no economics changed.

## Review result

The second-contributor review of v3.8 → v3.9 is in [docs/review-v39-independent.md](docs/review-v39-independent.md):
- **T-1** (launch blocker): tests did not compile on the verifier toolchain. Fixed.
- **M-1**: schedule bodies with `deliver`. Fixed, with a regression test.
- **M-2**: twin front-run of `Desk.bind`. Open by design, mitigated operationally (see below).
- **L-1**: mixed-toolchain artifacts would strand hook fees. Documented, with a pin-consistency test.

Fees, severity floor, escrow refactor, Desk constructor packing and keeper relay/wiring had no findings.

## v3.11 fork rehearsal (job 2f166600)

Source only; nothing deployed or broadcast; no contract logic changed (the rehearsal found no bug in the
contracts). `tools/rehearse_v311.sh <4663 rpc>` starts a local anvil fork of Robinhood Chain, builds with the IMD
launch toolchain (`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none`) and runs `test/fork/RehearsalV311.t.sol`,
which executes runbook steps M1–M13 in order through the **real** ProjectFactory, its registry, LaunchFactory,
PoolManager, Intake and IntakeDelivery addresses, impersonating the platform deployer `0xcECc…a551` where the
platform deploys or initializes. Throw-away roots, a test attester key and launch numbers 777001–777005 (asserted
unrecorded) were used; the test skips on any chain other than 4663, so the offline suite is unchanged. The log
with every address, call and check is `artifacts/v311/rehearsal.log` (5 passed, 0 failed, fork block 86865884,
2026-10-12). The factory ABIs were recovered from the runtime selectors and the calldata of recorded launches
1015, 1271, 1300 and 1316; the factory sources remain unverified.

| Check (brief §2) | Result on the fork |
|---|---|
| `Desk.registry()` = job A registry after `bind`; wrong coordinates and a non-registry refused; second bind refused | passed |
| `register` 0–13: factory CREATE2 addresses equal `predictContract`; duplicate role refused | passed, 14 registered |
| `bindFeeRouter`: non-router refused; `fees()`/`params()` set; `flushFees` no longer `NotConfigured` | passed |
| `escrow.forward`: wrong pool index refused; full balance (200,560,364e18) to the authenticated RewardPool; second call refused | passed |
| `fundEndowment` starts the drip (42 days); second call refused | passed |
| First pack only after launch + 1h (`TooEarly` before); entropy captured via the ArbSys clock | passed |
| Buys at +5/+15/+25 min pay 90/50/25% to rewards; +31 min exactly 1%; net sell carries the surcharge (cap 15%); `flushFees` lands in the FeeRouter | passed |
| Attested answer relayed by an arbitrary wallet via `SwarmDesk.submit`; forged signature refused; replay ignored; plan severity clamped to 7000 (band 5000–7000) for epochs e+1, e+2 | passed |
| Keeper `advanceEpoch` at `epochEnd` resolves the event with revealed entropy (seed ≠ 0), epoch 2 starts | passed |
| `LaunchFactory.claimFees(N_T)` pays the paying wallet: 0.0198 ETH after a 2 ETH buy (≈ 1%) | passed |

The four items v3.10 marked unproven:

| Item | Fork result |
|---|---|
| Attested creation-code hashes vs the real factory | Every deployed contract's initcode prefix hashes to the launch pins (`SwarmCode.*_LAUNCH`, `ModuleCode.launchHash(0..13)`), and the factory's CREATE2 addresses match `predictContract`, so the Desk, hook, Registry and escrow proofs all pass against the real factory. |
| `afterInitialize` sender | **LaunchFactory `0xa25b…4645`** (trace: `PoolManager.initialize` inside the LaunchFactory's launch tx, hook called with that sender). `initializedAt` set. |
| Gas per launch vs the 0.01 ETH ceiling | Desk 5,415,993; Escrow 1,743,701; token + hook 7,220,053; job A 21,411,808; job B 19,523,888 gas. At the fork basefee (0.0206 gwei) the dearest launch costs about 0.00045 ETH; it fits under the ceiling up to ≈ 0.47 gwei. |
| Constructor encoding through the real launcher | Twelve-word Desk, three-word escrow, eight-word hook (`$poolManager`, `$token`, `$factory`), job A/B words: all decoded as intended. |

Where reality differed (folded into `launch-v39.md`, no code change): the LaunchFactory's launch tuple names the
pair currency explicitly and every recorded 4663 hook launch so far was IMD-paired, so BLACKOUT's ETH pairing
must carry the zero address there (with IMD the hook's key check reverts the launch, as first observed on the
fork); `remainderTo` receives the 20% plus whatever pool dust the position did not seed (≥ 200,000,000e18, as
the runbook's checks already allow); and the keeper's first `advanceEpoch` must land before packs open at +1h.

The Sepolia rehearsal of v3.10 is replaced by this fork rehearsal: the same checks ran against the real 4663
platform contracts and bytecode, without spending IMD on Sepolia launches. What a fork cannot prove: the plane's
admission (audit panel, manifest, stand-in checks), the plane's own liquidity/price figures for the ETH pair,
live oracle schedules and the real attester, and the gas price on launch day.

## v3.12 launch-ready source (job c36ea654)

Source only. No deployment, broadcast, token action or oracle purchase. No contract changed.

**1. foundry.toml: not changed (blocked).** The brief asked for via_ir false and bytecode_hash "none" in the
root profile. This job type protects `foundry.toml`, and the previous attempt was rejected
(`path_violation: foundry.toml`), so the file is unchanged: `via_ir = true` and no `bytecode_hash`. The IMD
imported-launch check will keep blocking on bytecode_hash until the requester gets the change made in a job
where `foundry.toml` is writable, or by the platform. The edit needed is exactly two lines in
`[profile.default]`: `via_ir = false` and `bytecode_hash = "none"`. The rest of the profile (solc 0.8.26,
cancun, optimizer true, 200 runs) already matches. Until then the launch build uses the documented overrides
(`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none`, `out-launch/`), which produce the bytecode below.

**2. Pins unchanged.** Creation-code hashes of the launch build (`artifacts/v312/launch-creation-hashes.txt`),
all equal to research 4e478378 §3:

| Contract | Creation hash (launch toolchain) |
|---|---|
| GameRegistry (`SwarmCode.REGISTRY_LAUNCH`) | `0xee08039e9860c09d55aefe5cd2d9ffd5993f3fe60a1d606549902f56188418cb` |
| Params (`SwarmCode.PARAMS_LAUNCH`) | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` |
| SwarmDesk | `0x9e0cf571a687b4e79948f2af5fd2095058226c11bd002342955d6022ddeda214` |
| EndowmentEscrow | `0xeeb7a2c17455a83fd04d6ab155c2c580720bd0d3c02d95a6bc0e9cd213491610` |
| V4Market | `0x758e2ab5a6db72b6c5192702ecb0fcb291101c599f91e1bbee1cc36091e3a974` |
| `ModuleCode.launchHash(0..13)` | unchanged; `tools/pin_module_code.py --check` passes on both builds |

The via-IR repo pins (`REGISTRY_REPO`, `PARAMS_REPO`, `ModuleCode.repoHash`) **stay**. Removing them would
change contract bytecode: `SwarmCode.isRegistry/isParams` are inlined into SwarmDesk and EndowmentEscrow, and
`ModuleCode.matches/repoHash` into GameRegistry and EndowmentEscrow. Dropping them would move the SwarmDesk,
EndowmentEscrow and GameRegistry launch pins, and through `REGISTRY_LAUNCH` the V4Market pin. The repository's
own via-IR build also still needs them, because `foundry.toml` is via-IR.

**3. Checks** (logs in `artifacts/v312/`):

| Check | Result |
|---|---|
| `forge build` (plain `foundry.toml`, via-IR, no env) | passes (16 min compile) |
| `forge test` (plain `foundry.toml`, no env) | 265 passed, 0 failed, 6 skipped (same skips), 47 suites, including the new `TwinCaptureV312` |
| `forge test` (launch toolchain overrides) | 265 passed, 0 failed, 6 skipped (the 5 fork-rehearsal tests and the optional live-RPC test skip offline), 47 suites |
| Fork rehearsal `tools/rehearse_v311.sh https://robinhood.drpc.org` (anvil fork of 4663, block 87346575) | 5 passed, 0 failed (`artifacts/v312/rehearsal.log`); M1–M13 against the real ProjectFactory, registry, LaunchFactory, PoolManager |
| `forge fmt --check` | passes |
| `pin_module_code.py --check`, `pin_swarm_code.py --check` | pass, both toolchains |
| Node (`keeper-v39`, `oracle-v310`, `oracle-v37`, `reveal`, `ui-v35`) | all pass |
| Python `unittest` (`test/python`) | 34 passed |

New test (test only): `test/TwinCaptureV312.t.sol`, three tests behind the M-2 document (honest path, twin
orphans the honest game, twin cannot pay the attacker).

**4. IMD public check (`/requests/check`) for M1, M2, M3, M4, M7: not run.** The check runs against the new
commit, and that commit exists only after this job is delivered. This worker cannot push, and the steps
(audit-imported-code, adapt-contract-project, adversarial-review) would see the unchanged `foundry.toml`. The
expected result is the known bytecode_hash blocker, which item 1 could not clear. Run it once the delivered
commit is public and the profile change has landed, and record `blockers` per launch.

**5. M-2.** [docs/m2-trust-assumption.md](docs/m2-trust-assumption.md) is written for the audit judge. A twin
capture cannot pay the attacker: the escrow forwards only to a pinned RewardPool, and that pool pays only by
the mining rules. It is griefing (the honest modules are orphaned), rated low as a platform trust assumption,
and mitigated by binding right after job A and checking `Desk.registry()` before `forward`. One correction to
the brief: capturing the Desk and the forward needs a paid factory launch of at least Params, GameRegistry and
RewardPool. A twin that should also run as a game needs the full 8-contract job A shape.

**6. Runbook.** `launch-v39.md` has the research corrections: named `$contract:Params` /
`$contract:GameRegistry` references, the ProjectFactory registry `0xf52b…8406` for proofs, the M3 request
fields (no owner, no `initialMarketCapWei`), objective texts for M1, M2, M4 and M7 with one common paragraph,
the M-2 pointer in M1 and M4, and timing (1-contract median about 63 min; 8-contract unknown, budget 2 h; about
7–9 h from M1 to M10).

**Open items (v3.12):**
1. `foundry.toml`: apply `via_ir = false` and `bytecode_hash = "none"` in a job where the file may be edited.
   The launch pins above stay valid (they are the override build). After the change, the via-IR repo pins can
   only be dropped together with a re-pin (see 2). **Done by the requester (commits 94d5371, e0c09d4) and
   re-pinned in v3.13 below.**
2. Run the IMD public check for M1, M2, M3, M4 and M7 against the delivered commit and record the blockers.
3. Research 4e478378 was not in this workspace. Compare the objective texts in `launch-v39.md` with its
   recommended texts before pasting.
4. Still open from v3.11: the requester inputs (snapshot, roots, keeper wallet, Ethereum IMD), the plane's
   admission on the live path, and launch-day gas.

## v3.13 HeartbeatBps wired and re-pinned (review finding 6d1287b0)

Source only. No deployment, broadcast, token action or oracle purchase. Decision taken: option (a), fix it in
this job, since nothing is on chain and re-pinning is free.

**1. The fix.** `FeeRouter._route` and `routeTokens` credit `Params.HeartbeatBps` (packed regulator key 41,
bounds 200–5000, 200 at launch) instead of a literal 200 bps, through the new view `HEARTBEAT_BPS()`. The 1 ETH
cap (`HeartbeatCap`), the 10% team share, the 50% pot share and the `executeSells` rules are unchanged; the
remainder of each split goes to reward buys as before, so a raised heartbeat share comes out of reward buys
only. One guard was added: with the pot enabled, team and pot take 60% first, so a heartbeat share above 40%
is clipped to what is left instead of underflowing (only reachable above 4000 bps, which takes 34 daily
regulator steps). At 200 bps every existing split test is byte-for-byte the same.

**2. Tests** (`forge test`: 273 passed, 0 failed, 6 skipped as before, 48 suites, `artifacts/v313/forge-test.txt`):
- `test/HeartbeatBpsV313.t.sol`: default split unchanged; swarm-set 220 bps credits 0.022 ETH of a 1 ETH
  surcharge and 0.022e18 of 1e18 routed tokens with team and pot unmoved; the raised share still stops at the
  1 ETH cap and routed tokens carry no heartbeat at the cap; walking back to the 200 floor and refusing 199;
  5000 bps with the pot on is clipped to 0.4 ETH and rewards get 0 (tokens: 0.5 / 0.1 / 0.4); fuzzed
  conservation of every wei for any share and amount with team and pot exact; non-swarm, >10% step, above
  ceiling and second step inside 24 hours all revert.
- `SwarmDeskV37Test.testDeskSetHeartbeatBpsMovesFeeRouterShare`: a Desk-executed regulator vector carrying
  packed key 41 → 220 sets the value, then the FeeRouter credits 0.022 ETH and 0.022e18 tokens.
- `V310` and `Registry` pin tests now assert one toolchain (see 3).

**3. Re-pin, launch profile = `foundry.toml`.** The requester's commits 94d5371 and e0c09d4 set `via_ir = false`
and `bytecode_hash = "none"` in `foundry.toml`, which closed v3.12 open item 1. The repository build and the
launch build are therefore one toolchain and `tools/pin_module_code.py` / `pin_swarm_code.py` write the same
hash into both pins of every role (`launchHash == repoHash`, `*_LAUNCH == *_REPO`). The two-pin structure is
kept because the tools, the registry views and the escrow accept it unchanged; the launch overrides are no-ops.
New creation-code hashes (solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none;
`artifacts/v313/launch-creation-hashes.txt`, `module-pins.txt`):

| Contract | Creation hash (v3.13) | Was (v3.12) |
|---|---|---|
| FeeRouter (`ModuleCode.launchHash(6)`) | `0x47dc548c7cf7f4f190a5edaf16e1c7a0233492ed470e03afa80426417e7c0bda` | `0xfdc39970…8093ae` |
| GameRegistry (`SwarmCode.REGISTRY_LAUNCH`) | `0xedcb22640cb6434636d72a457d6557987e40dbfcd8dcea4355ab7d525cef2b22` | `0xee08039e…8418cb` |
| Params (`SwarmCode.PARAMS_LAUNCH`) | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` | unchanged |
| SwarmDesk | `0x65968358bcf87aa8839b8bce6b2d339493deac3f77d75a3ff0b3ad4f35955745` | `0x9e0cf571…deda214` |
| EndowmentEscrow | `0x4a39e28d9eb7fc03582b549a2022859f7586ce9bcb4f1ab3712f0329d0502ef3` | `0xeeb7a2c1…491610` |
| V4Market (`src/` and flattened `launch/V4Market.sol`) | `0x4610352776e29437b7b1acf74fdd11c85ff3cb3d79135c75ddb702edcb391392` | `0x758e2ab5…e3a974` |
| `ModuleCode.launchHash(0..5, 7..13)` | unchanged | unchanged |

Why each moved: FeeRouter is the source change; GameRegistry inlines `ModuleCode`; SwarmDesk and
EndowmentEscrow inline `SwarmCode.REGISTRY_LAUNCH`; V4Market embeds `type(GameRegistry).creationCode`. Params
inlines none of them. `launch/V4Market.sol` was re-flattened (`forge flatten`) and compiled on its own in a
scratch project: its creation hash equals the `src/` build above. The twelve SwarmDesk constructor words
(`tools/swarm_constructor_args.mjs` over `docs/oracle-v37/oracle-config.json`) contain no code pin and stay as
given. `pin_module_code.py --check` and `pin_swarm_code.py --check` pass; every runtime fits EIP-170.

**4. Reserved Params keys.** [docs/params-keys-v313.md](docs/params-keys-v313.md) lists every key with its
reader. Seventeen keys have none and are documented as reserved (no effect): 3 PriceFloor, 4 PriceCeiling,
5 PriceStart, 7 PriceDecayBps, 8 RepairBps, 9 LobbyKBps, 10 LobbyMinWeight, 24 SellHourBps, 25 SellDayBps,
26 SellDeviationBps, 28 ExpansionPrice, 29 MergePrice, 30 OverclockPrice, 33 MeasureBounty, 34 CreditBounty,
35 AuditBounty, 38 SeasonScoreBounty. None is wired here: each needs a design decision no brief has made, and
removing them would move the Params pin and the key numbering of every regulator body.

**Reported: the committed regulator vector proposes one reader-less key.** `docs/oracle-v37/regulator.json`
proposes `(8, 250)`, index 8 = `RepairBps`, which nothing reads. It is harmless as committed (250 is the
default, so `SwarmDesk._regulate` skips it; any other value would only burn that key's 24-hour cooldown) and it
is **not** changed here, because the body hash and question hash are `oracle-config.json` `bodies[1]` /
`questions[1]`, two of the twelve constructor words this job keeps. Removing it is a re-cut of the regulator
body in a job that also re-cuts the M1 objective. The other seven proposals (0, 1, 31, 23, 40, 27, 44) all
have readers, 40 since this version.

**5. Checks** (`artifacts/v313/`): `forge build`; `forge test` 273 passed / 0 failed / 6 skipped (the 5
fork-rehearsal tests and the optional live-RPC test, offline); `forge fmt --check` clean; both pin checks;
`tools/check_v37_authority.py`; `node test/oracle-v37.test.mjs`; `python3 -m unittest discover -s test/python`
34 passed. The fork rehearsal was not re-run (no network in this job); the pinned-hash path it proved is
unchanged in shape, only the five values above moved.

**Operational responsibilities (v3.13).** The regulator may now move the heartbeat share: 10% per 24 hours
within 200–5000 bps, with a public letter; every basis point above 200 is taken from reward buys, never from
the team or the pot. The keeper budget in `regulator.md` ("incremental share comes from reward buys") is now
true in code. Before each paid launch step compare the attested creation-code hash with the v3.13 table above,
not the v3.12 one.

## Still open

1. **M-2 twin front-run** (trust assumption, [docs/m2-trust-assumption.md](docs/m2-trust-assumption.md)). It cannot be closed without an on-chain fact only the honest launch has. Mitigation:
   keep `starterRoot`, `freeRoot`, the snapshot block and the lists private until `Desk.registry()` equals the
   job A registry; bind immediately after job A; never forward otherwise. If the requester wants a code fix,
   they must decide the anchor (for example a factory record of the payer). That changes the Desk pin.
2. **Requester inputs:** snapshot block, the two Merkle roots, the keeper wallet and its RPC, the Ethereum IMD
   for the schedules, and the Sepolia platform addresses (read and verified at rehearsal time).
3. **Fork rehearsal done, live platform path not.** The fork proved the creation-code pins, the `afterInitialize`
   sender, gas per launch, the relay and `claimFees` against the real 4663 contracts (above). Still unproven: the
   plane's admission and manifest checks, its liquidity/price figures for the ETH pair, the live attester and
   schedules, and launch-day gas.
4. Slither/Mythril and live oracle schedules were not run. This is not an external audit.

## Responsibilities

The requester pays and approves each launch job and the schedules, and supplies the inputs above. Anyone may send
the permissionless wiring calls; the keeper wallet only pays gas and holds no game power. SwarmDesk acts only on
attested oracle answers within hard-coded bounds. Nothing is upgradeable or owned.

## v3.14 — launch-ready source, four launches, deploy-gate fix

This source change is based on `24bfb1d700159042da4b08262927727d37170540`. Nothing was deployed or sent on chain. The protected build configuration and dependencies are unchanged. The supplied pre-launch audit findings and launch-1557 refusal are implemented below; the external `Identity-md/research/files/AUDIT.md` URL returned HTTP 404, so no claim is made to have read additional findings from that unavailable file.

**Audit fixes.** V4Market's buy and sell quotes include the 12,500 ppm LP fee in the requested order. The 10 ETH full-range pool regressions use an actual v4 PoolManager: at spot = TWAP, a 0.05 ETH reward buy with `quote * 9850 / 10000` succeeds and reduces rewardETH; a depth-capped system sell succeeds at the same tolerance, while an unfillable minimum rolls back. Desk binding now checks the hook's code, Desk, token and game hash after the factory/registry proofs. Foreign-market, foreign-token, EOA and wrong-config tests fail with `InvalidProof`, then the honest registry binds. The matching-twin limitation remains accepted in `docs/m2-trust-assumption.md`.

FeeRouter recomputes each sell's safe amount at execution from the actual queue and depth; it rejects an empty batch and enforces minOut against that amount. Caller dust cannot consume a cadence with a partial batch. FarmCore retirement requires the farmer. The regulator ignores encoded keys 0 and >45. Reward vintages retain the earlier credit timestamp. Lottery item claims create PackSale reward receipts, preserving future entropy and allowing claims with full inventory; capture/resolve and duplicate/failure paths are tested. Economy insertion rejects a 33rd traversal, with tests for the exact boundary, atomic rollback, list/accounting integrity and success after an earlier lock exits.

**Constructors and gate.** `src/lib/Robinhood.sol` pins all eight supplied protocol endpoints for chain 4663. SwarmDesk has seven non-address words, EndowmentEscrow one Desk word, GameRegistry seven words without a factory argument, and V4Market seven words with `$poolManager`, `$token`, `$factory` retained as permitted platform placeholders. The factory is compiled into every registry proof, including the hook and escrow reconstruction. Modules retain their single registry argument. All 19 launch constructors are tested with no protocol code on the local chain. The Node gate checks every constructor in a launch document and rejects every supplied protocol address, including case variations, padded ABI words and decimal encoding. The default four-launch plan passes.

**Four-launch handoff.** `launch-v39.md` contains complete L1–L4 objective texts, each under 8000 characters, with exact ordered constructor words, creation hashes, **NO SOURCE CHANGES**, and the eight accepted low/info lines copied verbatim from `docs/accepted-v314.md`. `docs/launch-v314-plan.json` is a source plan, not a platform manifest. L1 deploys Desk then escrow via `$contract:SwarmDesk`; L2 is token + hook, ETH-paired, poolBps 7000, remainder to that escrow; L3/L4 deploy job A/B using named intra-launch references. No new manifest, token source or dependency is introduced.

GAME_CONFIG_HASH remains **0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3**. The roots and snapshot were already private runbook inputs; their placeholders retain that same approved preimage and must be checked against the unchanged hash before L3. Test-only fork roots never substitute for them. Oracle question/body inputs are unchanged.

**Creation hashes.** Built under the unchanged foundry.toml: solc 0.8.26, optimizer 200, Cancun, viaIR false, bytecode_hash none. Both artifact directories agree. The changed module pins propagate through GameRegistry, SwarmDesk, EndowmentEscrow and the hook; the standalone flattened hook has identical creation bytes. Hashes below exclude constructor words; full initcode hashes depend on the recorded launch outputs.

| Launch | Contract | Creation-code hash (without constructor words) | Runtime bytes |
|---|---|---|---|
| L1 | SwarmDesk | `0x2573ebbe036cbb372112a707611204bbc7f679484b83d99f387cb2dad0e1135e` | 21412 |
| L1 | EndowmentEscrow | `0x8120758fa38683db9af5b5dbd28c6bd5682f58f160e36b1fc951815082101087` | 5008 |
| L2 | V4Market | `0xb3a295abe415ce500a185349e2b831e67d06993d647b3831babacdfc96fb00d3` | 21259 |
| L3 | Params | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` | 3118 |
| L3 | GameRegistry | `0xb763989d9f8be8f545dd607d7bc7810001086e9e65bdf6fe9521e5ec9ddc5c88` | 2864 |
| L3 | RewardPool | `0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de` | 4234 |
| L3 | FarmRewards | `0xf8f9f93e6bd8df85caaf5c508a71fb285a2f6229a5ef54023ac49ba66a14a001` | 16350 |
| L3 | FarmCore | `0xd6b7d7555a5865832a6d352b2a0bfa96ea10857b076a4cc156d5ad78cd1044fa` | 22027 |
| L3 | FarmItems | `0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76` | 13861 |
| L3 | PackSale | `0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a` | 12538 |
| L3 | StarterClaim | `0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90` | 5477 |
| L4 | FeeRouter | `0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af` | 11750 |
| L4 | GridOperator | `0xf21418187e35f2785dfd16075ad4b1bf855552ac4b413592f29d7222777974e9` | 9364 |
| L4 | Season | `0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83` | 11933 |
| L4 | FarmEngine | `0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c` | 10783 |
| L4 | Economy | `0x071421985d28e92da4caf5c8f17148d0cc9a8be8af66e7852d909d0a867b7e5d` | 10746 |
| L4 | Enhancement | `0x19ff379fb18f8649bc3889c3f8981bcf40d7c4045fe066dde9014b55b9751689` | 6858 |
| L4 | Civic | `0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2` | 13019 |
| L4 | Billboards | `0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60` | 6031 |

**Checks.** Evidence is in `artifacts/v314/`: `forge build` passed; full `forge test` passed **286 tests / 0 failures / 6 skipped** in 50 suites, including the 128-run, depth-64 invariant campaign and 256-run fuzz tests. The six offline skips are the five rehearsal tests plus the optional RPC-only test. `forge fmt --check`, both pin checks, the authority check, deploy gate, and independent standalone flattened build all passed. Node: **9 test entries passed**, including the four new deploy-gate cases. Python: **34 tests passed**. Every launch runtime is below EIP-170. No Slither/Mythril or live oracle/schedule execution was performed.

**Operational responsibilities.** The requester resolves the existing private roots/snapshot and prior launch output addresses, pays the four separate launch jobs and oracle schedules, and funds the keeper's gas. Keepers bind immediately after L3, register all modules, verify the bound registry before forwarding the escrow, activate the endowment, and advance the first epoch before packs are announced. Answers stored before L4 must wait for registration before execution. Lottery callers now receive a pack receipt and must capture/resolve it. Operators accept the precise eight findings in `docs/accepted-v314.md`; the runbook describes lock insertion limits and plain-transfer shortfall repair. The fixed oracle endpoints have no rotation authority. Test signer shims are confined to `test/` and never shipped as launch constructors or production substitutes.


**Fork rehearsal passed.** `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v314/rehearsal.log` completed **5 tests / 0 failures** on 2026-10-13 at RPC fork block **87523437**, basefee **20,148,000 wei (0.020148 gwei)**. It deployed L1 Desk + escrow atomically through the real ProjectFactory, L2 token + hook through LaunchFactory/PoolManager, and L3/L4 through ProjectFactory; then proved and registered the modules, bound the Desk/router, forwarded the entire endowment plus dust, funded the drip, exercised the oracle relay and epoch/entropy paths, tested launch taxes and system fees, and paid the platform fee share to the paying wallet. All transactions stayed on the local fork. The attester address stayed fixed in Desk bytecode/configuration; the test installed a signature-validating ERC1271 fixture there, and controlled native-L2 entropy, solely inside the fork.

| Launch | Measured factory-call gas | Cost including 21,000 gas at fork basefee (ETH) |
|---|---:|---:|
| L1 Desk + escrow | 6,773,836 | 0.000136902355728 |
| L2 token + hook | 7,096,407 | 0.000143401516236 |
| L3 job A | 21,498,901 | 0.000433582965348 |
| L4 job B | 19,711,879 | 0.000397578046092 |

All four calls fit the 0.01 ETH ceiling at the observed basefee; the largest fits up to about **0.464686152 gwei**. This is a measured rehearsal estimate, not a launch-day gas guarantee. An earlier attempt found the rehearsal's obsolete five-entry loop and it was corrected to the four-launch array length. Two subsequent public-RPC attempts reported unavailable historical state; compiling before starting Anvil avoided snapshot aging during compilation, and the final complete run passed. Paid platform admission and the live signer/schedule services remain operational checks outside this source-only assignment.

## v3.15 — audit 031c93c4 finding 1 (medium): `SwarmDesk.bind` proves the hook against the LaunchFactory record

Source only, based on `210eafe33ecc3a083e14a2b2c77b3b2584eaaa43` (v3.14). Nothing was deployed or sent on chain. The protected build configuration and dependencies are unchanged. **Only `src/SwarmDesk.sol` changed under `src/`**; `src/lib/Robinhood.sol`, `foundry.toml` and every other contract are untouched, and the creation code of EndowmentEscrow, V4Market, Params, GameRegistry and all fourteen modules is byte-identical to v3.14 (`artifacts/v315/launch-creation-hashes.txt`, both pin checks pass).

**The problem.** v3.14 `bind` accepted any `registry.market()` that echoed `desk()`, `token()` and `gameConfigHash()`. A registry built on the launched token but naming such a copy as its market passed every proof, captured the escrowed endowment through `EndowmentEscrow.forward` (which trusts the bound registry), and permanently blocked `V4Market.bindFeeRouter` on the genuine hook, since the hook accepts only the registry the Desk bound to.

**Path used: 1, the on-chain launch record.** The live LaunchFactory `0xa25b02a1e93903b790e6aaf7da1b8b8d50294645` exposes `positionOf(uint64 launchNumber)` (selector `0xfb2c8e23`, resolved with its other 79 selectors from the runtime bytecode at block 87548403). It is the position `claimFees(launchNumber)` collects from and `setRequester(launchNumber, …)` edits: eight static words `(currency0, currency1, fee, tickSpacing, hooks, tickLower, tickUpper, requester)`. Read at block 87548403: `positionOf(1316)` = (IMD, `0xc400…332e`, 12500, 60, `0x0bb8…60cc`, −887220, 128940, `0x5779…1eac`), i.e. exactly the token and hook that launch 1316 deployed (the research record in `docs/research/b94e6839-platform-report.md`); launches 1300 and 1015 read the same shape; an unrecorded number (0, 777002) reads all zeros. Only `launch` writes it, in the transaction that deploys the token and the hook, so it names the genuine hook of the genuine token. Because path 1 is available, the path-2 fallback (hook self-reports plus a PoolManager `extsload` price read) was **not** used: values a hook returns about itself prove nothing, and the brief allows path 2 only when no record exists.

**The fix.** `bind` gained an eighth argument, `uint64 tokenLaunch_` (zero reverts `InvalidValue` with the other zero coordinates). After the unchanged v3.8–v3.14 proofs (pinned registry/Params code, factory CREATE2 at the supplied coordinates, frozen configuration, Params naming the Desk) and the v3.14 market checks (code, `desk()`, `token()`, `gameConfigHash()`), `_proveHook` reads `ILaunchRecords(Robinhood.LAUNCH_FACTORY).positionOf(tokenLaunch_)` and reverts `InvalidProof` unless `currency0 == address(0)` (ETH-paired, as the plan's L2 and the hook's own `PoolKey` require), `currency1 == registry.token()` and `hooks == registry.market()`. The Desk stores `tokenLaunch` (public) for keepers. To stay inside the legacy (non via-IR) stack limit the registry proofs moved verbatim into `_proveRegistry`; no check was weakened or reordered. The runtime grew to 22,104 bytes (limit 24,576). No new storage is written before the proofs pass, and the new call is a `view` read of a compiled-in address, so no reentrancy or ordering change.

**Residual risk.** (1) The ABI of `positionOf` is recovered from bytecode and live reads, not verified source; the Desk pins its eight-word static layout, so a factory upgrade that changed or removed it would make `bind` revert and the Desk unbindable (the same class of dependency as the compiled-in `predictContract`). The runbook therefore has the keeper read `positionOf(N_TOKEN)` with `cast` before binding. (2) The record proves "the LaunchFactory deployed this hook for this token in launch N"; it does not prove which launch job paid, so the M-2 matching twin (same token, same hook, same private roots, a paid ProjectFactory launch, landing before the keeper's bind) remains accepted as griefing exactly as in `docs/m2-trust-assumption.md`, now with the escrow only ever forwardable to a pinned RewardPool of a game built on the genuine token and hook. (3) The check requires an ETH-paired record; a future IMD-paired launch would need a Desk source change, which the hook's `PoolKey(address(0), token, …)` already requires.

**Tests.** `test/AuditV315.t.sol` (5 tests): a MockMarket that echoes the three values, behind a pinned registry at valid factory coordinates, reverts `InvalidProof` under the genuine token launch, under an unrecorded number, and `InvalidValue` under zero; an attacker's own record (their token, the echo as hook) is refused, as is a registry naming the attacker's token; a record naming the token with another hook, or a non-ETH pair currency, is refused; a genuine `V4Market` (`TestV4Market`) recorded by the fixture LaunchFactory binds once, emits `Bound`, sets `tokenLaunch`, then `AlreadyDone`; the base fixture's own binding is checked against its record. The fixture `LocalLaunchFactory` (`script/Deploy.s.sol`, etched at `Robinhood.LAUNCH_FACTORY` like the ProjectFactory fixture) reproduces the live eight-word layout and reads zeros for unrecorded numbers. Existing bind callers in `SwarmDeskV37`, `TwinCaptureV312`, `EndowmentEscrowV38`, the deploy fixture, the keeper (`bind-desk` now requires `wiring.tokenLaunch`) and the keeper calldata vector were updated to the eight-argument signature.

| Check | Result |
|---|---|
| `forge build` (repo profile = launch profile) | passes; `out/` and `out-launch/` creation code identical for all 19 contracts (`artifacts/v315/forge-build.txt`, `creation-hashes.json`) |
| `forge test` | **291 passed, 0 failed, 6 skipped** in 51 suites (`artifacts/v315/forge-test.txt`); the skips are the five rehearsal tests offline and the optional RPC-only test |
| `forge fmt --check` | clean (`artifacts/v315/forge-fmt.txt`) |
| `tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check` | pass, pins unchanged |
| `node tools/check_deploy_gate.mjs` (JSON plan) | PASS, 19 constructors (`artifacts/v315/deploy-gate.txt`) |
| Node tests (`test/*.test.mjs`) | 9 passed, including the regenerated bind vector (`artifacts/v315/node-tests.txt`) |
| Python tests | 34 passed (`artifacts/v315/python-tests.txt`) |
| Fork rehearsal `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v315/rehearsal.log` | **5 passed, 0 failed** at anvil fork block **87556133**, basefee 20,772,000 wei; `LF.positionOf(777002)` named the rehearsal token, hook and paying wallet; the fake-market registry launched through the real ProjectFactory as 777005 was refused, as were launch 1316's real record and an unrecorded number for the honest registry; then the honest bind set `tokenLaunch() == 777002` and L4 wiring, forward, funding, swaps, oracle relay and `claimFees` passed as in v3.14 |

| Launch (fork) | Measured factory-call gas | Cost including 21,000 gas at fork basefee (ETH) |
|---|---:|---:|
| L1 Desk + escrow | 6,924,029 | 0.000144262142388 |
| L2 token + hook | 7,099,650 | 0.000147910141800 |
| L3 job A | 21,539,742 | 0.000447859732824 |
| L4 job B | 19,781,673 | 0.000411341123556 |

All four fit the 0.01 ETH ceiling; the largest fits up to about 0.4638 gwei. L1 grew by about 150k gas with the larger Desk.

**Creation hashes.** SwarmDesk is now `0x3731f03eac78693477b4630fa5ebb8768bad1fbbc8f0e8d6904e12db2a76cc91` (runtime 22,104 bytes) in `launch-v39.md` and `docs/launch-v314-plan.json` (version 3.15, file name kept because the tools default to it). The other 18 hashes are unchanged and were compared one by one against `artifacts/v314/creation-hashes.json`.

**Docs.** `docs/accepted-v315.md` carries the eight v3.14 lines plus 031c93c4 low 2 (`GameRegistry.register` prefill by an identical copy), low 3 (`Season.rollover` before `finalize`, mitigated by the keeper finalizing every week), low 4 (`FeeRouter.executeSells` sweep rollback), info 5 and info 6; the four objectives in `launch-v39.md` copy that list and stay under 8,000 characters (5,481 / 4,755 / 5,646 / 5,316). **Only the numbers of info 5 and info 6 were supplied to this job, so their two lines are placeholders that the requester must replace with the audit's text before pasting the objectives.** `launch-v39.md` line 9 now says the deploy-gate tool takes the JSON plan, not the markdown; the L1 and L3 objectives and wiring step 3 carry the eight-argument bind with `N_TOKEN`; `docs/m2-trust-assumption.md` and `keeper/README.md` describe the record proof.

**Operational responsibilities (new in v3.15).** The keeper records the L2 launch number as `wiring.tokenLaunch` before L3, reads `positionOf(N_TOKEN)` with `cast` and checks it names `(ETH, TOKEN, 12500, 60, HOOK)`, then binds with it; `bind-desk` refuses to run without it. Everything else in the v3.14 responsibilities list stands. Out of scope here, as before: Slither/Mythril, the live attester and schedule services, paid admission and launch-day gas.

## v3.16 — import audit 10bfac6d (medium): `SwarmDesk.bind` is restricted to one pinned binder

Source only, based on `30e314bc9dac4b53fbc85612f1763486b6d730ae` (v3.15). Nothing was deployed or sent on chain. The protected build configuration and dependencies are unchanged. **Only `src/SwarmDesk.sol` changed under `src/`**; `src/lib/Robinhood.sol`, `foundry.toml` and every other contract are untouched, and the creation code of EndowmentEscrow, V4Market, Params, GameRegistry and all fourteen modules is byte-identical to 30e314b (`artifacts/v316/creation-hashes.json` compared one by one against `artifacts/v315/creation-hashes.json`; both pin checks pass).

**The problem.** The v3.15 record proof says "the LaunchFactory deployed this hook for this token"; it does not say which token is BLACKOUT's. An attacker launches their own univ4_hook token with a V4Market naming this Desk and the public `gameConfigHash`, then Params + GameRegistry on that token once the roots are public at L3. Their `LaunchFactory.positionOf` record is self-consistent (ETH-paired, their token as currency1, their hook), so every v3.15 proof passes: the Desk is captured forever and `EndowmentEscrow.forward` can never forward the genuine remainder. `ForeignTokenTwinTest.testForeignTwinIsSelfConsistentAndPassesEveryProofExceptTheBinder` checks each proven value of such a twin.

**The fix.** The Desk takes an **eighth constructor word, `address binder_`** (zero reverts `InvalidValue`), stored `immutable` and exposed as `binder()`. `bind` now starts with `if (msg.sender != binder) revert Unauthorized();` and is otherwise unchanged: every v3.15 proof (pinned registry/Params code and factory coordinates, frozen configuration, Params naming the Desk, hook echoes of desk/token/hash, the `positionOf` record with `currency0 == address(0)`, `currency1 == registry.token()`, `hooks == registry.market()`) runs for the binder exactly as before. No requester check was added; the constructor reads no code, so the empty-chain launch check still holds (`DeployGateV314Test`). Runtime grew from 22,104 to 22,226 bytes.

**Binder for the launch.** `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, the project wallet that pays the launches and receives the platform fee share; not an IMD protocol address (`tools/swarm_constructor_args.mjs` and `script/SwarmArgs.sol` refuse a zero or protocol-address binder; `node tools/check_deploy_gate.mjs` passes on the plan with the word in it).

**Fork read (task item 4).** `LaunchFactory.positionOf(832)` on Robinhood Chain (4663) at block 87583728, through the local 4663 endpoint equivalent to `https://robinhood.drpc.org`: `(currency0 0x0000000000000000000000000000000000000000, currency1 0xa160A8305249E3A07bCf8723ca5803B5a2737e8D, fee 12500, tickSpacing 60, hooks 0x8892AEC7ceb014eb002E25905E29c244634E60cc, tickLower -887220, tickUpper 184200, requester 0x39E3414e7a43DE41675e9bEC52F7C9F6ae489CB6)`. An ETH-paired univ4_hook launch records `currency0 == address(0)`, so the v3.15 check is kept as is. For comparison, 1316 (IMD-paired) reads `currency0 == 0x5F7B…7127` (IMD), `currency1 0xc400…332E`, hook `0x0BB8…60cc`, tickUpper 128940, as in v3.15.

**Tests.** `test/ForeignTokenTwin.t.sol` (6 tests, permanent): a complete pinned-code game on a foreign token with a genuine-code hook (`TestV4Market`) and a self-consistent fixture record passes every proof; the attacker's bind reverts `Unauthorized` and the escrow stays untouched; bystanders, the keeper hot wallet and the test contract are refused for the twin and for the genuine registry; the binder binds the genuine registry once (emits `Bound`, sets `tokenLaunch`), then `AlreadyDone` for everyone including the binder, and the escrow forwards only to the genuine pinned pool; the binder cannot bypass a proof (wrong record, wrong coordinates, unrecorded number, zero, a genuine-token registry naming the attacker's hook); a zero binder reverts at construction, through the fixture factory and the offline encoder, and the eight-word shape is checked. `test/AuditV315.t.sol` line 118 now builds the realistic attacker hook (reporting the attacker's token): a genuine-token registry naming it fails the token/hook consistency check, and the attacker's self-consistent foreign registry is refused as `Unauthorized`. `TwinCaptureV312` now shows a genuine-token twin cannot win the race and keeps the capture analysis as the residual "binder key chose the twin" case. `SwarmDeskV37`, `EndowmentEscrowV38`, `DeployGateV314`, `OracleConformanceV37`, the deploy fixture (its own address is the fixture binder) and the rehearsal were adapted to the eight-word constructor; the keeper calldata vector is unchanged (the bind signature did not change).

| Check | Result |
|---|---|
| `forge build` (repo profile = launch profile) | passes; `out/` and `out-launch/` creation code identical for all 19 contracts (`artifacts/v316/launch-creation-hashes.txt`) |
| `forge test` | **298 passed, 0 failed, 6 skipped** in 52 suites (`artifacts/v316/forge-test.txt`); the skips are the five rehearsal tests offline and the optional RPC-only test |
| `forge fmt --check` | clean (`artifacts/v316/forge-fmt.txt`) |
| `tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check` | pass, pins unchanged (`artifacts/v316/*-pins-check.txt`) |
| `node tools/check_deploy_gate.mjs` (JSON plan, now with the binder word) | PASS, 19 constructors (`artifacts/v316/deploy-gate.txt`) |
| Node tests (`test/*.test.mjs`) | all pass, including the eight-word encoder checks and the binder refusals (`artifacts/v316/node-tests.txt`) |
| Python tests | 34 passed (`artifacts/v316/python-tests.txt`) |
| Fork rehearsal `tools/rehearse_v311.sh <4663 rpc> artifacts/v316/rehearsal.log` | **5 passed, 0 failed** at anvil fork block **87590429**, basefee 20,748,000 wei: `binder() == 0x6d51…d007` after L1; the platform deployer and a keeper hot wallet refused `Unauthorized` with the complete correct proof; the fake-market registry (777005) refused from its launcher (`Unauthorized`) and from the binder (`InvalidProof`); 1316's real record and an unrecorded number refused; the binder's bind set `tokenLaunch() == 777002`; L4 wiring, forward, funding, swaps, oracle relay and `claimFees` passed as in v3.15 |

| Launch (fork) | Measured factory-call gas | Cost including 21,000 gas at fork basefee (ETH) |
|---|---:|---:|
| L1 Desk + escrow | 6,952,268 | 0.000144681364464 |
| L2 token + hook | 7,079,886 | 0.000147329182728 |
| L3 job A | 21,290,968 | 0.000442180712064 |
| L4 job B | 19,521,699 | 0.000405471918852 |

All four fit the 0.01 ETH ceiling; the largest fits up to about 0.4692 gwei.

**Creation hashes.** SwarmDesk is now `0x81b258d403f90ab53a3c52d0b5ee895e57b2c80667b6fb82b637c3cf92a17b59` (runtime 22,226 bytes) in `launch-v39.md` and `docs/launch-v314-plan.json` (version 3.16, file name kept because the tools default to it), with its eight constructor words. The other 18 hashes are unchanged.

**Docs.** `docs/accepted-v316.md` keeps every v3.15 accepted item, writes 031c93c4 info 5 and info 6 out in full from the audit (`Identity-md/research`, job `031c93c4-9b85-454d-be7d-7537822de932`, `files/AUDIT.md`), and adds the binder-liveness line. The four objectives in `launch-v39.md` carry that list with info 5 and info 6 abridged to the audit's finding statement so each objective stays under the 8,000-character limit (7,021 / 5,993 / 7,048 / 6,554 characters; the file is named as the verbatim source); every x.com link was removed from the runbook and only https://playblackout.xyz remains. `docs/m2-trust-assumption.md` says twins (genuine or foreign token) can no longer bind and that the remaining trust is the binder key, which can only choose among registries that pass every proof. `keeper/README.md` and `keeper/keeper.mjs`: `bind-desk` simulates the bind from `Desk.binder()`, prints the transaction for the binder to sign and never sends it; `bind-router` and `forward` wait until `Desk.registry()` is the wiring registry.

**Operational responsibilities (new in v3.16).** The requester keeps the binder key `0x6d51…d007` available for one transaction right after L3; the keeper prints the calldata (`wire --step bind-desk`), the binder signs and sends it with its own tooling, and the keeper is re-run to verify `Desk.registry()` before `register` continues into `bind-router` and `forward`. If the binder key is lost before binding, the Desk never binds and the endowment stays in the escrow; no owner, rotation or fallback exists. The keeper's `bind-desk` printing path was syntax-checked and its encoder is covered by the `cast` vectors; it was **not** run against a live chain in this job (the rehearsal binds through forge with the binder pranked). Out of scope here, as before: Slither/Mythril, the live attester and schedule services, paid admission and launch-day gas.

## v3.17 — launch-1593 farmDaily port and pre-token audit 339b6b19 (1 medium, 3 low), re-pinned before L2

Source only, based on `15100e6af0893008f2f09d534604dcc6c1e008b4` (v3.16). Nothing was deployed or sent on chain; the fork rehearsal lands only in a local Anvil fork. The protected build configuration and dependencies are unchanged; `src/lib/Robinhood.sol` is untouched. L1 is redeployed for v3.17, so pins were allowed to change and were regenerated with the repository tools.

**Port (first).** `src/FarmRewards.sol` and `test/FarmDailyBasisV317.t.sol` are taken byte-for-byte from `identity-md-launches/launch-1593-blackout-v3-16-l1-robinhood` at `1e4490923f20a389ecb6be136121f4eea65db3b1` (a merge whose tree carries the fix; the diff against 15100e6 is the `FARM_DAILY_DECAY = 96` constant and the `_reward` basis update): a higher settled yield becomes `lastFarmDaily` at once, a lower one decays the previous basis by 1/96 per settled epoch, and a pro-rata entry epoch is scaled by `EPOCH / entrySeconds` to its full-epoch equivalent. The five ported tests pass unchanged.

**Audit 339b6b19 fixes.**

1. *Medium, Enhancement re-roll.* `capture` no longer re-arms an attempt whose 256-block window lapsed. `_lapse` settles it immediately as a failure with the worst outcome its level allows (`worstOutcome(level)`: never a success; targets 1–3 keep the item's level, 4+ lose one, any level with a burn chance burns the item), clears `pending[item]`, and emits `EnhancementLapsed` plus `EnhancementResolved(success = false)`. `capture` is now `external nonReentrant` over a private `_capture` that `resolve` shares, so a lapsed attempt cannot be re-entered. `EnhancementRearmed` is gone. `test/AuditV317.t.sol::testEnhancementRearmGrind` runs every target level 1–8: the lapsed outcome equals the worst outcome, and six different block hashes per level all resolve at least as well (success > keep > drop > burn), so lapsing is never better than resolving. The legacy test in `test/EconomyV35.t.sol` that asserted the re-arm now asserts the lapse.
2. *Low, GridOperator fallback.* `_resolve` returns `bool`; when the hash window lapsed it re-arms `target` to `number + 2` (`EventRearmed`) and returns `false`, keeping the submitted plan, severity and number for the fresh hash. The fixed fallback seed (`keccak(this, e, "fixed fallback")`) is removed, so no seed computable before the epoch is ever used, with or without a plan; the fixed `fallbackKind` table still decides the kind of an unplanned epoch. `FarmRewards.advanceEpoch` checks the return value first and, when the event was re-armed, emits `EpochCloseDeferred` and returns without touching state, so the epoch closes on the next call once the fresh hash exists. `GridOperator.eventTarget(e)` exposes the current target. Tests: `testSubmittedPlanDiscardedAfterHashWindow`, `testUnplannedLapsedWindowAlsoRearmsAndNeverUsesAPrecomputableSeed`, `testAdvanceEpochDefersUntilTheRearmedEventResolves`; `test/Events.t.sol` and `test/SwarmDeskV37.t.sol` fallback tests updated to the re-arm.
3. *Low, Economy.unlock while stale.* `unlock` calls `syncFor` only when `_canResync` holds (`live()` and `lastSettled(p) >= settledEpoch()`); otherwise it skips the weight resync and still deletes the lock, fixes the district list and totals, and returns the principal. `boostAt` already reports zero past `end`, and the next owner action re-syncs the weight. Tests: `testUnlockBlockedWhileEpochStale` (stale epoch), `testUnlockWhileBehindReturnsPrincipalAndSkipsResync` (29 epochs behind), `testUnlockLiveAndCaughtUpStillResyncsWeight` (boost removed on the live path; stranger and double unlock still revert `TooEarly`).
4. *Low, destroyed item keeps weight.* `FarmCore.process` calls `rewards().flagResync(p)` when it removes a destroyed item. `FarmRewards._settle` re-commits the farm from `FarmCore.committedHash(p)` (allocation hash of the loadout with the current boost) as soon as the farm is caught up (`cursor >= settledEpoch`), which takes effect next epoch through the existing bucket accounting, so `nextTotalHash` and the district hash stop counting the item; `setWeight` clears the flag. The commit is deliberately deferred until the farm is caught up because only two weight generations are tracked; `testDestroyedItemResyncWaitsUntilTheFarmIsCaughtUp` shows every settled epoch still balances (`settledHash == raw`). Tests drive the destruction through the engine's real Surge path (`testDestroyedItemWeightStale`, `testOwnerActionClearsThePendingResync`).

**Accepted.** `docs/accepted-v317.md` carries every v3.16 line, 339b6b19 info 5–8 (Civic.claimWar rounding dust, no max-cost bound on openPack/buyTokenPack, unused minter/caller permissions, dead fields) and the L1 judge items (PackSale.buyPacksFor gifting, one-shot escrow, Festival band, Economy._insert 33-tie lock griefing, stream-0 answers before role 1). The four runbook objectives carry the same list abridged (5,465 / 4,437 / 5,492 / 4,998 characters, under the 8,000 limit), keep the eight Desk words and the binder `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, and contain no x.com link.

**Creation hashes (all 19 regenerated, `artifacts/v317/launch-creation-hashes.txt`, `out/` and `out-launch/` identical).** Nine changed, ten did not.

| Contract | v3.17 creation hash | Changed? |
|---|---|---|
| SwarmDesk | `0x1d8e1afa90ba7a4c436fa2406f52743c97f7e6d9add372516144cadcb0795879` | yes (SwarmCode pins) |
| EndowmentEscrow | `0xe7a48446223ad53d50a9a9372c5552b70fb94e4f03c0f9f45298f7e5d2036368` | yes (SwarmCode/ModuleCode pins) |
| V4Market | `0x17e05386811fe526f0f44b95338a881b74127920e0f0587dbd1f798028b09931` | yes (GameRegistry/ModuleCode pins; `launch/V4Market.sol` re-flattened) |
| Params | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` | no |
| GameRegistry | `0xe41104da4edfb9a746e9080ce7b1885b5fe7609674a3a68fc5addbfd5a871531` | yes (ModuleCode pins) |
| RewardPool | `0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de` | no |
| FarmRewards | `0xfa1a4087722916aeefae66aaf3400299a5e4cb8f4fc8e516a17cec7754e07506` | yes (port, deferral, resync; runtime 17,002) |
| FarmCore | `0xc390b07ef7a9ab65bef3a1ec3b39c1a16e117543c9565fedc9342526aa57aa47` | yes (flagResync, committedHash; runtime 22,361) |
| FarmItems | `0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76` | no |
| PackSale | `0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a` | no |
| StarterClaim | `0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90` | no |
| FeeRouter | `0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af` | no |
| GridOperator | `0x931bdfaeeacadb7c8014ce1411671d0045013c2b373d95bbf0bb83dfce0b7c74` | yes (re-arm; runtime 9,519) |
| Season | `0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83` | no |
| FarmEngine | `0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c` | no |
| Economy | `0x105f9f29d79579fa33ff8e11d4d86847dd7d9f59bd681500553a3844db50ccc9` | yes (unlock; runtime 11,097) |
| Enhancement | `0x31242676dd3a728a2ad32a5cb300166020e87831b0f547756fa0bab88cedea38` | yes (lapse; runtime 7,112) |
| Civic | `0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2` | no |
| Billboards | `0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60` | no |

`launch-v39.md` (table and all four objectives) and `docs/launch-v314-plan.json` (version 3.17, file name kept because the tools default to it) carry these hashes; the constructor words are unchanged.

| Check | Result |
|---|---|
| `forge build` (repo profile = launch profile) | passes; all 19 creation codes identical in `out/` and `out-launch/`; every runtime under EIP-170 (largest FarmCore 22,361) |
| `forge test` | **315 passed, 0 failed, 6 skipped** in 54 suites (`artifacts/v317/forge-test.txt`); skips are the five rehearsal tests offline and the optional RPC-only test |
| `forge fmt --check` | clean (`artifacts/v317/forge-fmt.txt`) |
| `tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check` | pass (`artifacts/v317/*-pins-check.txt`) |
| `node tools/check_deploy_gate.mjs` | PASS, 19 constructors (`artifacts/v317/deploy-gate.txt`) |
| `tools/check_v37_authority.py` | passes after updating its constructor assertion to the eight-word Desk (it had asserted seven words since v3.16 and failed at 15100e6) |
| Node tests (`test/*.test.mjs`), Python tests | all pass, 34 Python tests (`artifacts/v317/node-tests.txt`, `python-tests.txt`) |
| Fork rehearsal `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v317/rehearsal.log` | **5 passed, 0 failed** at anvil fork block **87728112**, basefee 20,148,000 wei: L1 (777001) deployed the eight-word Desk and escrow, non-binder senders refused `Unauthorized`, the binder's bind set `tokenLaunch() == 777002` with the real `LaunchFactory.positionOf(777002)` record, the fake-market registry (777005) refused, roles 0–13 verified, `bindFeeRouter`, `forward` and the first pack entropy completed |

| Launch (fork) | Measured factory-call gas |
|---|---:|
| L1 Desk + escrow | 6,952,280 |
| L2 token + hook | 7,089,377 |
| L3 job A | 21,628,498 |
| L4 job B | 19,828,437 |

All four stay under the 0.01 ETH ceiling at the fork basefee.

**Assumptions and deployment parameters.** Constructor words are exactly those of v3.16 (eight Desk words with the binder last, escrow `$contract:SwarmDesk`, hook seven words, Params three, GameRegistry seven, every module `$contract:GameRegistry` or `<L3_GAME_REGISTRY>`); only the creation hashes above changed. `FARM_DAILY_DECAY = 96` is a constant (about 4% a day). An enhancement attempt that is not captured within 256 blocks of its target now loses by rule; the UI and keeper should capture promptly, as they already do for packs. A grid event whose window lapses needs a second transaction at least two blocks later; `advanceEpoch` is a no-op-with-re-arm until then and pays no bounty for that call.

**Operational responsibilities (new in v3.17).** The keeper's epoch pass must treat an `EpochCloseDeferred` / `EventRearmed` log as "retry `GridOperator.resolve(epoch)` or `advanceEpoch()` within the new 256-block window" (`keeper/README.md`). The keeper keeps capturing enhancement attempts inside their window; a lapsed one needs no further action beyond the first `capture`/`resolve` that settles it. Settlement remains permissionless; anyone settling a farm whose item was destroyed triggers its weight resync. Players unlocking an expired lock while the game is stale get their principal without a resync and should `sync()` once caught up. The binder key `0x6d51…d007` is still required once, right after L3, with the v3.17 artifacts.

## v3.18 — L2 import audit a3749636 (medium) in V4Market only, before L2

Source only, based on `e17f0ef7bd7d188949eb4dc91e3eb0540c94cbf3` (v3.17). Nothing was deployed or sent on chain; the fork rehearsal lands only in a local Anvil fork. The protected build configuration and dependencies are unchanged; `foundry.toml` and `src/lib/Robinhood.sol` are untouched. **Only `src/V4Market.sol` changed under `src/`**, plus tests, docs, the runbook, the plan and the re-flattened `launch/V4Market.sol`. L1 is deployed as launch 1628 (SwarmDesk `0x5cb0686a4475d1f8a6c6e5240579080a4a05b609`, EndowmentEscrow `0x11947494c0ba91508eb7409648193818c36521fb`); its creation hashes and every other pin are byte-identical to e17f0ef.

**Finding.** `beforeSwap` charged the stepped launch tax (90/50/25%) and the 1% project share on the full exact-input amount. v4 applies a hook's before-swap delta to the specified currency and the pool only then swaps the remainder up to `sqrtPriceLimitX96`, so a buy whose limit is reached paid tax on ETH the pool never consumed. Reproduced on e17f0ef against the real v4 PoolManager (1000e18 full-range liquidity at price 1, limit 0.9995 × spot, first tax step): 10 ETH specified, the pool consumed 0.5066 ETH, the buyer was debited 9.5066 ETH and `heldLaunchTax` was 9 ETH. A front-run moving spot past a slippage-derived limit puts any such buy in that state.

**Path taken: refusal, not after-swap charging.** The preferred fix (charge in `afterSwap` from the swap delta) is not sound under the v4 delta rules. A hook's `afterSwap` return delta applies only to the *unspecified* currency, which for an exact-input ETH -> token buy is the token output; the ETH charge can only be sized in `beforeSwap`, before consumption is known. Taking ETH inside `afterSwap` would leave the hook with an unsettled negative delta (the router settles only its own `swapDelta`), and refunding the over-charge to the swapper is impossible because deltas are per address. Charging the tax in tokens would change the streams. So V4Market now:

1. reverts `PriceLimitedBuy(sqrtPriceLimitX96)` in `beforeSwap` for any buy whose limit is not `BUY_PRICE_LIMIT = 4295128740` (`TickMath.MIN_SQRT_PRICE + 1`), the extreme bound at which an exact-input swap consumes its whole input; v4-periphery's `V4Router` sends exactly this bound for exact-input swaps and protects the buyer with `amountOutMinimum`, so the standard router path is unaffected;
2. reverts `PartialFill(consumed, expected)` in `afterSwap` unless the pool's ETH delta equals the specified input net of the tax (`ethIn - ethIn * bps / 10000`), the direct statement of the invariant "no tax on unconsumed ETH"; this only triggers if the full-range liquidity were exhausted, which the extreme bound otherwise cannot do;
3. keeps everything else: exact-input only, the same `heldLaunchTax` / base stream / sell-surcharge streams, the stepped bps, the `LaunchTax` event, the 0.5 ETH reward-buy batch of the FeeRouter (V4Market itself has no max-buy cap since v3.9: `maxBuy()` is `uint256.max`), and the whole public interface used by FeeRouter, GameRegistry, SwarmDesk and the keeper (`desk()`, `token()`, `gameConfigHash()`, `launcher`, `manager`, `initializedAt`, `bindFeeRouter`, `flushFees`, `launchStatus`, `spot`, `fees`, `quote`/`buy`/`sell` paths). Sells are charged in `afterSwap` on the ETH the pool actually paid and may carry any limit, as before.

**Low (manager float): accepted.** The take still happens in `beforeSwap`, before the swapper settles, so the PoolManager must hold the tax as float during the swap; it is repaid within the same unlock by the hook's positive before-swap delta. The live Robinhood PoolManager holds about 24,500 ETH; a manager without the float makes the buy revert, never lose funds. Removing the float would mean holding the tax as ERC-6909 claims and adding an unlock to `flushFees`, a larger change not made here. Recorded in `docs/accepted-v318.md`.

**Tests (`test/AuditV318.t.sol`, real v4 PoolManager unless noted).** `testAuditPriceLimitedBuyRevertsInsteadOfPayingTaxOnUnconsumedEth` (the audit input: 10 ETH, limit reached, now reverts with no ETH moved and nothing held), `testPriceLimitedBuyRefusedAfterLaunchWindowToo` (1% window, limit at spot − 1 and at the extreme bound + 1), `testBeforeSwapNamesThePriceLimitedBuyError`, `testFullFillTenEthBuyPaysExactlyNinetyPercentInTheFirstStep` (buyer debited exactly 10 ETH, 9 ETH held, flushed to rewards), `testFullFillBuysPayEachStepExactly` (9000/5000/2500/100 bps), `testFuzzOnlyTheExtremeBoundBuysAndPaysTheFlooredTax` (256 runs with the verifier's seed: every other limit reverts, the extreme bound debits exactly the input and holds `floor(in × bps / 1e4)`), `testSystemRewardBuyStillFills` (FeeRouter.executeBuys), `testPriceLimitedSellStillFillsPartiallyAndIsChargedOnActualOutput`, `testPublicInterfaceUnchanged`; through the mock manager, `testAfterSwapRefusesAPartialFill` (`PartialFill(0.5e18, 1e18)`, off by one wei also refused, exact fill recorded), `testAfterSwapAcceptsExactFillAtEveryStep`, `testMockBeforeSwapRefusesNonExtremeLimitAndKeepsExactOutputRefusal`. `test/V39.t.sol` now presents the mock after-swap delta as the pool would (input net of the 1%). All earlier V4 tests are unchanged and pass.

**Creation hashes (`artifacts/v318/launch-creation-hashes.txt`, `out/` and `out-launch/` identical).** One changed, eighteen did not; each was compared one by one against `artifacts/v317/creation-hashes.json`.

| Contract | v3.18 creation hash | Changed? |
|---|---|---|
| V4Market | `0x8d6e02398e351aa4c28486a92d7ec60baf7edc67ccaaa88eed4bd61e9b9092a4` | yes (runtime 21,534, was 21,259); `launch/V4Market.sol` re-flattened and compiles to the same hash |
| SwarmDesk, EndowmentEscrow, Params, GameRegistry, RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim, FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards | as in `report.md` §v3.17 | no |

`launch-v39.md` (header, table, all four objectives) and `docs/launch-v314-plan.json` (version 3.18, file name kept because the tools default to it) carry the new hash. The L2 objective and plan entry carry the deployed L1 addresses literally (`<L1_SWARM_DESK>` -> `0x5cb0…b609` in the hook's sixth word, `remainderTo` -> `0x1194…21fb`); the L1 objective is marked deployed. Neither file contains an x.com link (none was present).

| Check | Result |
|---|---|
| `forge build` (repo profile = launch profile) | passes; all 19 creation codes identical in `out/` and `out-launch/`; every runtime under EIP-170 |
| `forge test` with `FOUNDRY_FUZZ_SEED=0xc048a7c9…89ced` | **327 passed, 0 failed, 6 skipped** in 56 suites (`artifacts/v318/forge-test.txt`); skips are the five rehearsal tests offline and the optional RPC-only test |
| `forge fmt --check` | clean (`artifacts/v318/forge-fmt.txt`) |
| `tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check` | pass (`artifacts/v318/*-pins-check.txt`) |
| `node tools/check_deploy_gate.mjs` | PASS, 19 constructors (`artifacts/v318/deploy-gate.txt`) |
| Node tests (`test/*.test.mjs`) | pass (`artifacts/v318/node-tests.txt`) |
| Fork rehearsal `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v318/rehearsal.log` | **5 passed, 0 failed** at anvil fork block **88100745** (2026-10-14, basefee 20,298,000 wei): L2 deployed the v3.18 hook through the real LaunchFactory, the stepped tax then exactly 1% on extreme-bound buys, surcharge unchanged, bind, roles, `bindFeeRouter`, `forward`, entropy |

| Launch (fork) | Measured factory-call gas | v3.17 |
|---|---:|---:|
| L1 Desk + escrow | 6,952,280 | 6,952,280 |
| L2 token + hook | 7,143,830 | 7,089,377 |
| L3 job A | 21,561,311 | 21,628,498 |
| L4 job B | 19,753,231 | 19,828,437 |

All four stay under the 0.01 ETH ceiling at the fork basefee.

**Assumptions and deployment parameters.** Constructor words are unchanged (hook: `$poolManager`, `$token`, 12500, 60, `$factory`, the deployed Desk `0x5cb0686a4475d1f8a6c6e5240579080a4a05b609`, GAME_CONFIG_HASH). `BUY_PRICE_LIMIT` is a constant equal to v4-core's `TickMath.MIN_SQRT_PRICE + 1`; any router that sends a tighter limit on a buy must switch to the extreme bound plus a minimum output. Partial fills of a buy are impossible with the launch pool's full-range liquidity at the extreme bound; the `PartialFill` guard is defence in depth. The manager float assumption is stated above.

**Operational responsibilities.** After L2, check `V4Market.BUY_PRICE_LIMIT() == 4295128740` alongside the existing checks and tell integrators (UI, aggregators) that buys use the extreme bound with a minimum output; a `PriceLimitedBuy` revert in a user's wallet means their router set a price limit and is not a hook fault. The keeper's reward buys and sells are unchanged (the hook's own `unlockCallback` already uses the extreme bounds). Nothing else in the keeper runbook changes.
