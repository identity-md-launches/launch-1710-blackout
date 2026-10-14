# BLACKOUT adversarial tests

This suite extends the accepted tests without modifying any existing file. It uses
`src/LaunchToken.sol`, the production `src/V4Market.sol` (no subclass or overridden
checks), and the vendored Uniswap v4 `PoolManager`. The original `LaunchHookTest`
continues to check the required creation hash
`0xedb2d58fb4632f2ef5a81b58ea05dcff0f5510e5448c6766539f89379109af10`,
21,982-byte runtime, permissions and supplied production constructor commitments.

## Running

From the repository root, with the existing compiler configuration:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x4ab8f1c0387753e39590f1961532a526e94ef3612744e5a68cf61e25cc23a3af forge test
```

To run only these additions, append `--match-path 'test/blackout/*.t.sol'`.
All dependencies already exist in `vendor/`; these tests require no network, fork,
FFI, environment mutation or generated file. Scratch logs and build artifacts are
not inputs to any test.

Validated with Forge 1.8.5 and the seed above: the full 62-suite run passed 382 tests,
failed none, and skipped six existing RPC-dependent fork tests. These additions
contributed 27 passing tests as counted by Forge, including six invariant properties
grouped into two campaigns. Each campaign completed 24,576 random calls with zero
handler reverts; `forge build` also passed. No new implementation defect was found.

## Coverage

| File | Checks |
| --- | --- |
| `BlackoutFailures.t.sol` | Constructor policy and missing identities; every pool-key field; inactive unlock callback; exact wrapped buy-limit error; complete rollback on failed slippage; tax-step seconds and one-wei rounding; partial-sell refunds; no-profit buy/sell round trips; TWAP warmup and idle gaps; volume bucket expiry. Binding rejects wrong coordinates, registry, commitment, token, market, Params and unenrolled routers. Exercises real FeeRouter forwarding/reward buys and hook system buys/sells, including bounds, warmup, slippage and retry. |
| `BlackoutInvariant.t.sol` | Random buys, sells, time advances, binding, flushing, reward buys through the real FeeRouter, team withdrawals, rejected buys, token transfers and forced ETH donations. Checks independent fee receipts, whole-system conservation, router liabilities, permanent initialization/binding and sell-fee limits. Every sequence finishes by flushing fees and withdrawing the entire LP position. |
| `BlackoutTokenInvariant.t.sol` | Four-holder ledger of transfers, delegated transfers, approvals, infinite allowances, revocations, full-balance round trips, self-transfers and rejected mint/burn/overspend/zero-recipient attempts. Balances and all 16 allowances must agree with the independent history; supply stays exactly 1,000,000,000e18. |
| `BlackoutFixture.sol` | Mined production hook and real PoolManager settlement. The test router pulls only its caller's tokens and completes each unlock in one transaction. It checks all hook/router currency deltas and the manager lock before transient state disappears. |

Both invariant campaigns use 256 sequences of depth 96, with
`fail-on-revert = true` configured inline. Expected failures are checked explicitly;
valid operations cannot disappear behind empty catches. Deterministic handler
tests exercise successful accounting paths as a coverage witness. Arithmetic
properties use 1,000 cases each, alongside explicit dust and timing boundaries.

The hook campaign uses three funded trading actors, a full-range pool with 100,000
units of liquidity, individual trades up to 5 ETH/tokens, and forward time jumps up
to 26 hours. These bounds keep valid swaps executable while crossing tax, TWAP and
volume-window boundaries. Separate unit/fuzz tests exercise larger partial sells,
minimum-output failures and dust. Forced ETH is tracked independently: it must not
be misclassified as a fee liability. The model covers only assets moved by its
listed actors and contracts, not arbitrary outside protocols.

## Fixture boundaries

The binding fixture uses synthetic, explicitly test-only Merkle roots, snapshot
coordinates and a matching constructor commitment. `BlackoutDeskProbe` models the
already deployed Desk's `registry()` view; the existing `LocalApplicationFactory`
models the external platform's CREATE2 addressing. Registry, Params, FeeRouter and
RewardPool are actual production contracts, with real module enrollment. Local
registry/module coordinates 77 and 78 are test identities, not deployment claims.
The production Desk address and private commitment preimage are not reconfigured.
Live Desk authorization and chain state remain the responsibility of the existing
deployment/fork rehearsal.

The fee-deposit failure test deliberately injects a receiver revert at each of the
three real router entry points. This verifies atomic rollback and retry; it does
not allege that the immutable FeeRouter normally rejects those deposits. No hook,
token or manager storage is patched to force passing results.

The accepted manager-float limitation and unbound-Desk risk are unchanged. The
existing `testAcceptedManagerFloatConstraintOnTokenOnlyPool` covers the first;
this suite covers refusal to flush before binding and successful delivery after
binding. Offline success is not a live launch or fork result.

## Launch artifacts

The token is `LaunchToken` (BLACKOUT/BLACKOUT), and the hook is `V4Market`. On chain
4663 the intended pool key is `(native ETH, deployed LaunchToken, 12500, 60,
deployed V4Market)`, where native ETH is v4 currency address zero. This tests-only
assignment broadcasts no transaction, so deployed token/hook addresses, the final
pool ID and the new launch number are not produced here; the platform supplies
them after launch. Local fixture addresses and launch coordinates must not be
returned as production deployment results.

No production or dependency files were changed. A read-only comparison found an
already-existing line-wrapping difference in vendored `SignatureChecker.sol`
relative to the recorded upstream hash; comparison with the pinned upstream file
confirmed it is whitespace only. This suite leaves that accepted input untouched.
