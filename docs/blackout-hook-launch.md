# BLACKOUT token and hook launch

This delivery prepares the **univ4_hook** launch for [BLACKOUT](https://playblackout.xyz)
on **Robinhood Chain, chain ID 4663**, paired with native ETH. IMD performs the actual
launch after admission. This repository does not contain a new launch manifest or a
broadcast transaction.

## Source and reproducibility

The baseline is
[`identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood` at
`86e71d47b12094dc6a37c6a05cd4f84f2f970b78`](https://github.com/identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood/tree/86e71d47b12094dc6a37c6a05cd4f84f2f970b78).
The pinned commit's archive was extracted without Git metadata, GitHub configuration,
environment files, or node_modules. All build dependencies are ordinary files under
`vendor/`. There was no top-level `lib/` in that commit; `src/lib/` is preserved.

The only changes to existing contract source are the requested `HookPermissions`
struct immediately after the Errors import and `getHookPermissions()` immediately
after `V4Market.receive()`. Their whitespace follows `forge fmt`; all original source
bytes remain intact. `src/LaunchToken.sol` is the sole added production contract.
The compiler configuration and vendored dependencies are byte-identical to the baseline:
Solidity **0.8.26**, Cancun, optimizer enabled with 200 runs, `via_ir = false`,
`bytecode_hash = "none"`.

| Artifact | Required result |
| --- | --- |
| Hook source / contract | `src/V4Market.sol:V4Market` |
| Hook creation-code keccak256, before constructor arguments | `0xedb2d58fb4632f2ef5a81b58ea05dcff0f5510e5448c6766539f89379109af10` |
| Hook runtime length | 21,982 bytes |
| Hook address mask | `uint160(hook) & 0x3fff == 0x10cc` |
| Token source / contract | `src/LaunchToken.sol:LaunchToken` |

`docs/launch-upstream-sha256.json` records the baseline hashes of all existing
contracts, source/dependency files, and `foundry.toml`. The offline checker removes
only the two exact permitted additions before comparing the hook to its baseline.
Historical flattened contracts in `launch/` and old deployment plans remain unchanged;
the deployable hook for this assignment is the root Foundry build's **src/V4Market.sol**.
Do not use the historical flattened hook or `test/mocks/MockToken.sol` for this launch.

## Launch parameters

| Field | Value |
| --- | --- |
| Launch type | `univ4_hook` |
| Chain | Robinhood Chain / `4663` |
| Project | `https://playblackout.xyz` |
| Token contract | `LaunchToken` |
| Name / symbol | `BLACKOUT` / `BLACKOUT` |
| Decimals | `18` |
| Fixed supply | `1000000000000000000000000000` minor units (1,000,000,000 tokens) |
| Token constructor arguments | None |
| Supply recipient at construction | `msg.sender`, the launch factory |
| Owner field | Omitted; neither the token nor hook has an owner |
| Pair | `eth`, native ETH |
| Pool fee | `12500` (1.25%, in v4 millionths) |
| Tick spacing | `60` |
| Hook flags | `0x10cc` (decimal 4300) |
| Economics `poolBps` | `7000` |
| Pool allocation | 700,000,000 BLACKOUT (70%) |
| Swarm allocation | 100,000,000 BLACKOUT (10%), distributed by the platform |
| Remainder | 200,000,000 BLACKOUT (20%) to the paying wallet, using the form default |

The token is the standard OpenZeppelin ERC-20 already vendored by the project, with
one constructor mint. It has plain transfers/allowances and no external mint, burn,
ownership, upgrade, pause, fee, or blacklist functions. All supply distribution is the
factory's work; the token does not reserve or automatically send an endowment.

The hook constructor words are exactly, in order:

```json
["$poolManager","$token","12500","60","$factory","0x5cb0686a4475d1f8a6c6e5240579080a4a05b609","0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3"]
```

The Solidity types are `(address,address,uint24,int24,address,address,bytes32)`.
`$poolManager`, `$token`, and `$factory` are platform-resolved constructor words,
not missing requester inputs. There is no `$owner` argument. The SwarmDesk address
and gameConfigHash are the values supplied by the requester, preserved exactly.
The constructor performs no outside contract calls and does not require Desk code
to be present during empty-chain admission checks.

The resulting pool key is:

```text
currency0   = 0x0000000000000000000000000000000000000000  (native ETH)
currency1   = the deployed LaunchToken address ($token)
fee         = 12500
tickSpacing = 60
hooks       = the deployed V4Market address with flags 0x10cc
poolId      = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks))
```

The zero currency is the actual v4 native-ETH identifier. ETH sorts before the
nonzero token address. The platform's nominal `initialPrice` field is
`79228162514264337593543950336`; the launch factory derives its actual opening price
from the policy's 10 ETH opening market cap and the deployed token. The 1:1 price in
local tests is a fixture, not a production-price prediction.

## Hook behavior retained

The permissions ABI reports only `afterInitialize`, `beforeSwap`, `afterSwap`,
`beforeSwapReturnDelta`, and `afterSwapReturnDelta`. These total `0x10cc`.
`afterInitialize` authenticates both PoolManager and the factory's `sender`, checks
the exact pool key, and starts the one-time launch clock. All implemented callbacks
reject callers other than PoolManager with `Unauthorized`. No liquidity-removal
callbacks are enabled, so the factory can collect LP fees with a zero liquidity change.

Buy charges are the existing total steps: 90% before 10 minutes, 50% from 10 to
20 minutes, 25% from 20 to 30 minutes, then 1%. During the first 30 minutes the whole
buy charge is accounted as `heldLaunchTax`; after that the 1% is `heldBase`.
The schedule is not an extra 1% added on top of 90/50/25%. Sells accrue the 1% base
share plus the existing progressive surcharge, capped at 15% combined, on actual
ETH output. The separate pool LP fee remains 1.25%.

Exact-input swaps only are supported (`amountSpecified < 0`). A buy must carry
`sqrtPriceLimitX96 = 4295128740`; otherwise it reverts `PriceLimitedBuy`.
`afterSwap` reverts `PartialFill` unless the pool consumes exactly input minus tax.
Routers must enforce the buyer's minimum token output themselves. Price-limited
sells may partially fill because their charge uses actual ETH output.

Fees are held as native ETH in the hook. `bindFeeRouter` proves the canonical
Desk-bound registry, committed game configuration, factory deployment coordinates,
Params, and enrolled FeeRouter. The binding is permissionless and one-time; no
caller can choose an arbitrary recipient. After binding, a separate permissionless
`flushFees()` forwards the held streams. Launch tax and the 1% base stream fund
reward buys; the sell surcharge follows the unchanged FeeRouter allocation to
rewards, team credit, capped heartbeat, and the season pot when enabled.
A failed receiver call reverts the entire flush and preserves its balances;
receivers are not called during external pool swaps.

## After launch

1. IMD records and returns this launch's number, token address, hook address,
   complete pool key and pool ID after deployment and initialization. The current
   task prepares those contracts; it cannot assign the number or predict concrete
   addresses without the platform's resolved deployment inputs and CREATE2 salt.
   **1628 identifies the existing L1 bootstrap launch, not this new token launch.**
   L1/L2/L3 here are application launch stages, all on the specified chain.
2. The paying/project wallet transfers **200,000,000 BLACKOUT** after launch to the
   already deployed EndowmentEscrow **`0x11947494c0ba91508eb7409648193818c36521fb`**
   from bootstrap launch 1628. The escrow is not the factory's `remainderTo` in
   this task. The project is responsible for this transfer; no contract in this
   delivery performs it automatically.
3. After L3, the pinned binder **`0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`**
   binds the existing SwarmDesk **`0x5cb0686a4475d1f8a6c6e5240579080a4a05b609`**
   to the canonical game using its existing proof requirements. This is a Desk
   responsibility, not ownership of the token or hook.
4. Once the canonical FeeRouter is enrolled and the Desk is bound, anyone may call
   `V4Market.bindFeeRouter(router, registryLaunch, registryIndex)` with the actual
   factory-recorded coordinates, then call `flushFees()`. Keepers continue flushing
   accumulated streams and executing the existing reward-buy/season operations.
5. The existing escrow's permissionless `forward` proves the canonical registry
   and RewardPool using their actual factory launch coordinates and pinned
   creation code, and forwards its entire token balance once. Fund it before
   forwarding; verify receipt and the canonical target from the recorded launch.

The existing source's fixed application-factory constants and the requester's
Desk/escrow addresses are retained. No live-chain verification or transaction was
performed in this task. The platform's deployment rehearsal validates their live
code, Desk state, factory configuration, opening price, liquidity and fee tier.

## Accepted constraints and validation

- **a3749636 low:** buys take tax from PoolManager's ETH float before settlement.
  A manager without enough float reverts the buy atomically. No claim fallback was
  added; the accepted audited behavior is preserved. A token-only local pool test
  covers this failure alongside successful funded-manager buys.
- **420b1475 low:** fees accumulated while unbound have no recovery route if the
  Desk never binds. The pinned binder's prompt post-L3 action is required for
  liveness. The hook has no administrative rescue function.
- Exact-input-only behavior, `PriceLimitedBuy`, and `PartialFill` are intended.
- Binding is post-deployment wiring. Launch-window sell volume is recorded gross.
  The first swap after an idle gap updates a bounded observation ring and costs
  more gas. Pool fee 12500 must match the launch platform's LaunchFees value.

Run from the repository root (Foundry and Solidity 0.8.26 must be installed):

```sh
forge build
FOUNDRY_FUZZ_SEED=0x4ab8f1c0387753e39590f1961532a526e94ef3612744e5a68cf61e25cc23a3af forge test
forge fmt --check
python3 tools/check_launch_source.py --artifacts
```

No package download, environment-dependent test configuration, FFI, or filesystem
permission grant is needed. `test/LaunchToken.t.sol` checks factory minting, metadata,
allocation/escrow transfers, events, allowance success/failure, conservation fuzzing,
and absent administrative/supply-changing entry points. `test/LaunchHook.t.sol`
deploys the production hook at a CREATE2-mined address and exercises its pinned
hash/size, v4-core permission ABI, real initialization, caller/pool authentication,
tax/settlement conservation, intended refusals, held fees, and factory LP-fee collection.
The complete unchanged upstream suite includes binding success/failure, launch-step
boundaries, partial fills, reward routing, and game invariants. Historical fork tests
are opt-in and skipped by the ordinary offline run.

Local validation on 2026-10-14, using Foundry 1.8.5 and Solidity 0.8.26:

| Check | Result |
| --- | --- |
| `forge build` | Passed; existing compiler/lint warnings remain |
| Full `forge test` with the seed above | 355 passed, 0 failed, 6 skipped, across 58 suites |
| Added launch tests | All 13 token tests and 15 production-hook tests passed |
| Upstream invariants | All seven passed; 128 runs, 8,192 calls, 0 reverts reported |
| `forge fmt --check` | Passed |
| Source comparison | 512 baseline files preserved, allowing only the specified hook additions |
| Hook artifact | Exact requested creation hash and 21,982-byte runtime |
| Existing binding pins | All fourteen module hashes plus GameRegistry/Params matched both build directories |

The six skipped tests are the five historical launch rehearsal tests in
`test/fork/RehearsalV311.t.sol` and the ArbOS RPC test in
`test/fork/RobinhoodFork.t.sol`. These are not reported as successful live-chain
tests. The binding-pin check additionally used
`forge build --out out-launch --cache-path cache-launch --skip test --skip script`,
then `python3 tools/pin_module_code.py --check` and
`python3 tools/pin_swarm_code.py --check`; neither pin source was regenerated.

These local checks are not a new independent security audit. Live-chain fork
rehearsal, independent review, source verification, and launch attestation remain
the platform's release steps. Slither, Mythril and formal verification were not run
as part of this bounded source-preserving import.
