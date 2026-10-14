# Independent review: BLACKOUT v3.8 → v3.9 (job 14aa1d96, commit 5cc9f59)

Reviewer: second contributor (v3.10 job), not the author of v3.9. Scope: the full v3.8 → v3.9 diff
(`git diff 73ec53e 5cc9f59`): hook and FeeRouter fees, toolchain pins, GridOperator severity floor, keeper relay
and wiring, EndowmentEscrow, and the `Desk.bind` twin front-run. Method: line-by-line reading of the diff
against `.imd/reads/skills/eth-security` and the oracle-consumer reference, rebuilding under both toolchains,
compiling the flattened `launch/V4Market.sol` under the verifier settings, and running the suites. This is a
bounded contributor review, not an external audit. Slither, Mythril and live-chain tests were not run.

## Result

| Id | Severity | Title | Status |
|---|---|---|---|
| T-1 | High (launch blocker) | Test suite did not compile under the IMD verifier settings (stack too deep) | **Fixed** (tests only) |
| M-1 | Medium | Schedule bodies generated with `deliver`, which `schedule.create` refuses | **Fixed**, regression test |
| M-2 | Medium | Twin registry can capture the Desk before `Desk.bind` if the game configuration is public | **Open by design**, mitigated operationally, regression test for the bounded part |
| L-1 | Low | Dual toolchain pins: a repository-built registry binds the Desk but never the hook | Documented, pin-consistency test added |
| I-1 | Info | Fee rework matches the brief | No change |
| I-2 | Info | Severity floor and Desk band | No change |
| I-3 | Info | EndowmentEscrow refactor is behaviour-preserving | No change |
| I-4 | Info | SwarmDesk constructor repacking | No change |

No contract source was changed. Every module, Registry, Params, Desk, escrow and hook build is byte-identical
to the v3.9 pins (`tools/pin_module_code.py --check`, `tools/pin_swarm_code.py --check`).

## T-1 — the launch toolchain could not build the tests (fixed)

`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none forge build` failed with "Stack too deep" in
`test/EndowmentEscrowV38.t.sol:86` (the v3.9 artifact `forge-test-launch.txt` recorded this). Fixing it showed
three more: `test/LazyAccounting.t.sol` (`_eager` reference model), and two functions in
`test/SwarmDeskV37.t.sol`. The verifier runs `forge test` with exactly those settings, so v3.9 would have been
rejected. Fix: helpers (`_freshGame`, `_registryArgs`, `_lookalike`), a struct (`Ev`) with two helper functions
for the reference model, and scoped blocks. Assertions are unchanged. Both toolchains now build and pass.

## M-1 — schedule bodies carried `deliver` (fixed)

`tools/make_oracle_bodies.mjs <DESK>` still wrote `schedule.create` bodies with
`deliver: {chainId: 4663, ...}`. The platform research (job b94e6839, C1) showed `schedule.create` refuses that
key ("Unrecognized key: deliver"). The v3.9 keeper and runbook expect `consumer {chainId: 4663,
verifyingContract: Desk}` and no `deliver`, so the generator contradicted them. An operator following the
generator would get a refused schedule; the free preflight catches it, but a paid submission skipping it would
lose time on launch day. Fix: `tools/schedule_bodies.mjs` builds the body with `consumer` and refuses a zero or
malformed Desk address and a body that already carries routing. `make_oracle_bodies.mjs` uses it.
Regression: `test/oracle-v310.test.mjs` checks there is no `deliver`, the consumer, the cadence (event
`5 */6 * * *` 28 runs, regulator `5 0 * * 4` 4 runs), that the question hash is unchanged by routing, and the
failure cases. The committed bodies and `oracle-config.json` are byte-identical after regeneration.

## M-2 — Desk.bind twin front-run (open by design)

`SwarmDesk.bind` accepts the first registry that is a factory CREATE2 result of the pinned code at a recorded
launch, whose configuration hashes to `gameConfigHash` and whose Params points at the Desk. Launch numbers cannot
be reserved (v3.8 brief), so nothing on chain tells the honest job A from a twin launched through the same
factory. A twin needs the real token and hook addresses (public after M3) **and** `starterRoot`, `freeRoot`,
`snapshotBlock`, `endowment` (only their hash is on chain until job A). If an attacker has those and binds
first, `EndowmentEscrow.forward` sends the endowment to the twin's RewardPool and the hook binds to the twin's
FeeRouter.

What bounds it, verified:
- A twin with any other token cannot drain the escrow: `forward` reads the bound registry's token and finds no
  balance (`testTwinWithForeignTokenCannotDrainEscrow`, new).
- A twin with a different root, snapshot or endowment cannot bind (`testEmptyChainConstructorAndAuthenticatedBindingRejectSpoofs`).
- `bind` is permissionless and one transaction; the keeper's `bind-desk` step checks `Desk.registry()` and
  stops before `forward`.

Why not fixed in code: closing it needs an on-chain fact that only the honest launch has (a reserved launch
number, or a factory record of the payer). The v3.8 brief removed the first and the factory interface in this
repo has no second. Adding either is a requester decision and would change the Desk pin. Operational
mitigation (now in `launch-v39.md` §0, M4–M5, M9): keep the roots, snapshot and lists unpublished until
`Desk.registry()` is the job A registry; bind right after job A; never forward otherwise. Residual risk: whoever
sees the job A objective text before it executes (the platform) could race it.

## L-1 — two pins per role (documented)

v3.9 lets `GameRegistry.register`, `SwarmDesk.bind` and `EndowmentEscrow.forward` accept either the launch
pin or the repository (via-IR) pin. `V4Market` checks the registry against `type(GameRegistry).creationCode`
of its own build. A registry built with the other toolchain would bind the Desk but never the hook, and the
hook's base fees would stay unflushable. It is not exploitable beyond M-2: an attacker who can bind a twin
already wins. The honest launch uses one toolchain. Verified: the flattened `launch/V4Market.sol` compiled with
the verifier settings is byte-identical to `src/V4Market.sol`'s launch build and embeds exactly
`SwarmCode.REGISTRY_LAUNCH`. Added `test/V310.t.sol`: whichever toolchain compiles the suite, all 14 modules,
Registry and Params must match that toolchain's pins together (catches pin drift and mixed artifacts). The
runbook requires `out-launch` artifacts for every step.

## Items checked without findings

- **I-1 Fees.** `V4Market` no longer has `NETWORK_BPS`, a network recipient or a network credit. After 30
  minutes, buys pay `PROJECT_BPS = 100` (1%), all to `heldBase`. Sells pay 1% base plus the progressive
  surcharge, capped at `TOTAL_CAP_BPS = 1500`. `storedFeeWad` starts at 100e18, consistent with the 1% base.
  The stepped launch tax 90/50/25% is unchanged and fully held as launch tax. `quote()` deducts 1%.
  `FeeRouter._base` credits 100% to `rewardETH`; `team` keeps only its pack and surcharge shares. The pool fee
  stays pinned to 12500. Tests: `test/V39.t.sol`, `Market`, `V4Integration`, `HookBinding`.
- **I-2 Severity.** `GridOperator.SEVERITY_FLOOR = 3000` with ceiling 10000; the Desk clamps attested
  severities to 5000–7000; the fallback table is unchanged.
  `testGridAcceptsSeverityFromThreeThousandAndRejectsBelow` and the relay clamp test cover it.
- **I-3 Escrow.** `_proveRegistry` / `_provePool` are a stack-depth refactor of the v3.8 checks in the same
  order (pins, Desk binding, Params→Desk, recorded launches, CREATE2 predictions, pool code present). The
  `forwarded` flag is set before the transfer under `nonReentrant`.
- **I-4 Desk constructor.** Twelve words; `policyWord` packs chainId (32 bits), fromBlock and toBlock (48),
  maxPrice (96) and heartbeatBps (16), with the top 16 bits required zero. The ranges cover 4663, 1, 11155111 and
  0.5e18. The heartbeat cap is the constant 1e18. The JS encoder enforces the same widths
  (`test/oracle-v37.test.mjs`).
- **Keeper relay and wiring.** The relay refuses documents for another contract or question locally, and the
  Desk re-verifies everything. Wiring steps are idempotent and simulated first. `bind-desk` checks
  `Desk.registry()`. Encoders match `cast` vectors (`test/keeper-v39.test.mjs`). No signing authority is
  created.
