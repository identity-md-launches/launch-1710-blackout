# M-2 twin front-run of `SwarmDesk.bind`: trust assumption (for the audit judge)

BLACKOUT v3.16. Source only. The binding checks require a hook with matching Desk, token and game configuration
(v3.14), the LaunchFactory's own launch record naming that hook for the registry's token (v3.15, audit 031c93c4
finding 1) and, since v3.16 (import audit 10bfac6d), a caller equal to the Desk's pinned `binder`. This document
covers finding M-2 of the v3.10 independent review ([docs/review-v39-independent.md](review-v39-independent.md))
and its v3.16 resolution. It says what an attacker who wanted to win the `SwarmDesk.bind` race could do before
v3.16 and what is left now, rates the severity, and gives the operational responsibilities the runbook
([launch-v39.md](../launch-v39.md), L3 and post-L4 wiring) applies. Every claim below cites the code or a test.
The tests run offline (`test/ForeignTokenTwin.t.sol`, `test/TwinCaptureV312.t.sol`, `test/AuditV315.t.sol`,
`test/EndowmentEscrowV38.t.sol`); the rehearsal on a fork of 4663 (`test/fork/RehearsalV311.t.sol`) ran the honest
order against the real factory with the binder signing the bind.

## 1. The race, and why there is none since v3.16

`SwarmDesk.bind` (`src/SwarmDesk.sol`) runs once. **Since v3.16 it reverts `Unauthorized` for every caller except
the immutable `binder`**, the eighth constructor word (the project wallet `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`
for the launch; the constructor refuses a zero binder). For that caller it accepts the first candidate registry
that meets all of these, exactly as in v3.15:

- `keccak256(registryCode)` and `keccak256(paramsCode)` equal a pinned GameRegistry / Params creation hash
  (`SwarmCode.isRegistry`, `SwarmCode.isParams`);
- `registry.factory()` is the ProjectFactory `0x9c9d…265e` compiled into the Desk;
- `keccak256(abi.encode(starterRoot, freeRoot, snapshotBlock, endowment))` equals the Desk's `gameConfigHash`;
- the Params is the factory's CREATE2 result for the pinned Params code with constructor `(Desk, 200, 1e18)` at
  the given launch coordinates, it has code, and `swarmWallet()` is the Desk;
- the registry is the factory's CREATE2 result for the pinned registry code and its constructor tuple at the
  given coordinates, and it has code;
- its market has code, `IBoundHook(market).desk()` is this Desk, `token()` equals the registry token,
  and `gameConfigHash()` equals the Desk commitment; mismatches revert `InvalidProof`;
- `LaunchFactory.positionOf(tokenLaunch)`, the record `claimFees(tokenLaunch)` keys on and only the factory's
  `launch` writes, names the registry's token as currency1 of an ETH-paired pool (currency0 == address(0); launch
  832 on 4663 reads `(0x0, 0xa160…7e8D, 12500, 60, 0x8892…60cc)` exactly like 1316) and the registry's market as
  its hook. A market that merely echoes the three values has no record naming it and reverts `InvalidProof`.

IMD launch numbers cannot be reserved, so nothing on chain separates the honest job A from a byte-identical
"twin" job launched through the same factory. Before v3.16, whoever called `bind` first with a valid registry
won. Now nobody but the binder can call it, so a twin, genuine-token or foreign-token, **cannot bind**
(`ForeignTokenTwinTest.testForeignTwinCannotBindFromTheAttacker`, `testNoNonBinderCanBindEitherRegistry`,
`TwinCaptureV312Test.testTwinCannotWinTheBindRace`).

## 2. What the v3.15 proofs could not tell apart (import audit 10bfac6d)

The v3.15 record proof says "the LaunchFactory deployed this hook for this token". It does not say which token is
BLACKOUT's. An attacker could:

1. launch their **own** univ4_hook token through the LaunchFactory with a V4Market naming this Desk and the public
   `gameConfigHash` (both are on chain from L1 and L2);
2. after L3 makes the roots public, launch Params + GameRegistry (+ RewardPool) on **their** token through the
   ProjectFactory;
3. call `bind` with their registry and their launch number.

Their record is self-consistent: ETH-paired, their token as currency1, their hook, so every v3.15 proof passed
(`ForeignTokenTwinTest.testForeignTwinIsSelfConsistentAndPassesEveryProofExceptTheBinder` checks every proven
value). The Desk would have been captured forever and `EndowmentEscrow.forward` could never have forwarded the
genuine remainder, since it requires `Desk.registry()` to be the registry it pays. The realistic hook shape
reports the attacker's token (a hook is built for one token), which `test/AuditV315.t.sol`
`testAttackerLaunchRecordNamesAnotherTokenAndIsRefused` now models.

The v3.16 fix is the caller restriction, nothing else: no requester check was added, no proof was weakened or
reordered, and the keeper's wiring key never sends the bind (it prints the calldata for the binder to sign).

## 3. What the remaining trust is: the binder key

| Effect | Can an attacker do it? | Why (code / test) |
|---|---|---|
| Bind any registry, genuine or twin | **No** | `bind` reverts `Unauthorized` unless `msg.sender == binder` (`ForeignTokenTwin`, `TwinCaptureV312`, `AuditV315`, rehearsal `_m5Bind` from the platform deployer and a keeper hot wallet) |
| Make the binder bind a registry that fails a proof | **No** | The proofs run for the binder too: wrong launch number, wrong coordinates, unrecorded record, a hook naming another token all revert `InvalidProof`; zero reverts `InvalidValue` (`ForeignTokenTwinTest.testBinderCannotBypassAnyProof`) |
| Bind the honest registry afterwards | No, for anyone | `AlreadyDone` after the one bind (`testBinderBindsTheGenuineRegistryThenAlreadyDone`) |
| Make the escrow pay an attacker wallet | **No** | `EndowmentEscrow.forward` sends only to `registry.module(0)`, the pinned RewardPool of the bound registry (`testBinderChosenTwinCannotPayAttacker`) |
| Capture the Desk with a foreign-token twin | **No** | The attacker is not the binder (`testForeignTwinCannotBindFromTheAttacker`) |

What is left is the **binder key itself**:

- **Choice among proven registries.** If the binder key chose a proven twin (genuine token, same roots; or a
  foreign-token twin whose hook names this Desk), the honest graph would be orphaned exactly as the v3.12 capture
  described (`TwinCaptureV312Test.testBinderChoosingTwinOrphansHonestGame`). The key cannot do more than that: it
  cannot pay itself, change rules or take hook fees (`testBinderChosenTwinCannotPayAttacker`). The binder is the
  project wallet that already pays the launches and receives the platform fee share, so this is the requester
  trusting their own key.
- **Liveness.** `bind` is a one-time call by the pinned binder. If that key is lost before binding, the Desk can
  never bind and the endowment stays in the escrow (no owner, rotation or fallback exists). The binder cannot
  bypass any proof. Listed in `docs/accepted-v316.md`.

## 4. Severity

**Resolved for third parties; a key-custody trust assumption for the requester.**

- Impact of a third party: none. No path binds the Desk without the binder key.
- Impact of the binder key: at most the v3.12 griefing outcome (orphaned honest launches), never fund loss; the
  binder also cannot bind anything that fails a proof.
- Liveness: the single binder key must be available once, after L3. Losing it leaves the endowment in the escrow.

## 5. Operational responsibilities (in the runbook)

1. **Keep the roots private until the bind.** Still good practice; a twin cannot bind, but publishing early gives
   no benefit.
2. **The binder signs right after job A.** Immediately after L3, run `node keeper/keeper.mjs wire --step bind-desk`.
   It simulates `SwarmDesk.bind` **from the binder** (`Desk.binder()`) and prints the transaction (to, from, data)
   for the project wallet to sign and send. The keeper key never sends it. Re-run `wire` afterwards: it reads
   `Desk.registry()` and throws `STOP` if the bound registry is not the job A registry.
3. **Check `Desk.registry()` before every forward.** The keeper refuses `bind-router` and `forward` while the
   Desk is unbound or bound to another registry. `EndowmentEscrow.forward` is never sent unless
   `Desk.registry()` is `<REGISTRY>`. If it is anything else: stop, publish nothing, escalate to the requester.
4. **Keep the binder key safe until the bind lands.** There is no replacement path; this source assignment
   authorizes no token replacement or deployment.

## 6. Evidence

| Test | Shows |
|---|---|
| `ForeignTokenTwinTest.testForeignTwinIsSelfConsistentAndPassesEveryProofExceptTheBinder` | The attacker's foreign-token twin is self-consistent against every v3.15 proof |
| `ForeignTokenTwinTest.testForeignTwinCannotBindFromTheAttacker` | The attacker's bind reverts `Unauthorized`; the escrow stays untouched |
| `ForeignTokenTwinTest.testNoNonBinderCanBindEitherRegistry` | Bystanders, the keeper hot wallet and the test contract are refused for the twin and the genuine registry |
| `ForeignTokenTwinTest.testBinderBindsTheGenuineRegistryThenAlreadyDone` | The binder binds the genuine registry once; everyone, including the binder, gets `AlreadyDone`; the escrow forwards to the genuine pinned pool only |
| `ForeignTokenTwinTest.testBinderCannotBypassAnyProof` | Wrong record, coordinates, launch number, zero and a mixed-token registry all revert for the binder |
| `ForeignTokenTwinTest.testZeroBinderRevertsAtConstruction` | Zero binder refused by the constructor and the encoder; eight static words |
| `TwinCaptureV312Test.testTwinCannotWinTheBindRace` | A genuine-token twin cannot bind; the honest bind lands afterwards and the twin is orphaned |
| `TwinCaptureV312Test.testBinderChoosingTwinOrphansHonestGame`, `testBinderChosenTwinCannotPayAttacker` | Residual: a binder-chosen twin orphans the honest game but pays only its pinned pool, nothing to the attacker |
| `AuditV315Test` | The v3.15 record proofs, now exercised for the binder, with the realistic attacker hook reporting the attacker's token |
| `RehearsalV311` (fork of 4663) | The honest L1–L4 sequence against the real ProjectFactory, LaunchFactory and PoolManager with the binder signing the bind and the platform deployer and a keeper wallet refused |
