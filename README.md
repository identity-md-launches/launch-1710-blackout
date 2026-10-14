# BLACKOUT v3.8 (source v3.18)

**Current BLACKOUT token + hook delivery:** the Robinhood Chain 4663 `univ4_hook`
launch uses `src/LaunchToken.sol:LaunchToken` (BLACKOUT/BLACKOUT, 1 billion fixed
supply) and the pinned `src/V4Market.sol:V4Market`, with only the requested
permissions struct/getter added. See [the current launch handoff](docs/blackout-hook-launch.md)
for constructor words, pool key, source/hash checks, allocation, accepted constraints,
and post-launch binding responsibilities. The 20% remainder goes to the paying
wallet, which subsequently transfers 200 million BLACKOUT to the existing escrow.
Launch 1628 is the existing bootstrap; this token/hook launch number and deployed
addresses are assigned and returned by IMD after admission. The older release
notes and plans below are preserved as upstream history.

**v3.18 (L2 import audit a3749636, medium, fixed in source; L1 is deployed as launch 1628).** A buy whose
`sqrtPriceLimitX96` stopped the swap early paid the launch tax and the 1% share on ETH the pool never consumed. V4Market
now accepts buys only at the extreme bound `BUY_PRICE_LIMIT = 4295128740` (`PriceLimitedBuy` otherwise, what v4 routers
send) and `afterSwap` refuses a partial fill (`PartialFill`); full-fill buys pay exactly as before and sells are
unchanged. Only the V4Market creation hash changed; the other 18 are byte-identical to e17f0ef. The audit's low (tax
taken from the PoolManager float in beforeSwap) is accepted. See `report.md` §v3.18, [launch-v39.md](launch-v39.md) and
[docs/accepted-v318.md](docs/accepted-v318.md).

**v3.17 (pre-token audit 339b6b19 and the launch-1593 farmDaily port, fixed in source).** `FarmRewards.lastFarmDaily`
is a sticky basis: a higher settled yield replaces it at once, a lower one only decays it by 1/96 per settled epoch, and
a pro-rata entry epoch is scaled to a full epoch. An enhancement attempt whose 256-block window lapses is settled as the
worst outcome of its level instead of re-arming (lapsing is never better than resolving). A grid event whose window
lapses re-arms to a fresh block and keeps the submitted plan; `advanceEpoch` then returns without closing the epoch
until the fresh hash exists. `Economy.unlock` always returns an expired lock's principal and skips the weight resync
while no epoch is live or the account is behind. An item destroyed by an event leaves the farm's committed weight at the
next epoch. Nine of the 19 creation hashes changed; see `report.md` §v3.17, [launch-v39.md](launch-v39.md) and
[docs/accepted-v317.md](docs/accepted-v317.md).

**v3.16 (import audit 10bfac6d, fixed in source).** `SwarmDesk.bind` is restricted to one pinned binder, the
Desk's eighth constructor word (the project wallet `0x6d51…d007` for the launch); every v3.15 proof still runs for
that caller and anyone else gets `Unauthorized`. The keeper's `bind-desk` prints the calldata for the binder to
sign and never sends it. See `report.md` §v3.16, [docs/accepted-v316.md](docs/accepted-v316.md) and
[docs/m2-trust-assumption.md](docs/m2-trust-assumption.md).

**v3.13 (review finding 6d1287b0, fixed in source).** `FeeRouter` now reads `Params.HeartbeatBps` (packed
regulator key 41, bounds 200–5000, 200 at launch) for the heartbeat share of the sell surcharge and of routed
tokens instead of a literal 200; the 1 ETH cap and every other split are unchanged. Every creation-code pin was
regenerated under the launch profile, which `foundry.toml` now *is* (via_ir false, bytecode_hash none), so the
repository build and the launch build are one toolchain. Params keys without a reader are documented as reserved
in [docs/params-keys-v313.md](docs/params-keys-v313.md); the twelve SwarmDesk constructor words are unchanged.
See `report.md` §v3.13 for the new hashes.

Source-only continuation of v3.7 against the real IMD platform (research job b94e6839): no launch number is known at construction, the 20% endowment goes through an ownerless `EndowmentEscrow`, the hook matches the platform pool fee 12500, and the Desk accepts relayed attestations through `submit`. See [launch-v38.md](launch-v38.md) for what is done and what is still open. No deployment, broadcast, token launch or mint. [playblackout.xyz](https://playblackout.xyz) · [free pack claim](https://playblackout.xyz/freepack).

Packs, rooms, repairs, enhancement and lobbying use the existing token. Prices follow the last settled mining yield with explicit floors. Packs and lobbying send 88% to rewards, 10% to the team and 2% to the capped heartbeat; the latter two shares queue for bounded sales through the official pool. Other spending returns entirely to rewards. ETH purchases use an atomic swap-and-pack zap with minimum output. The normal swap fee schedule is retained.

Active items wear 1% each six-hour epoch and use output tiers. Optional auto-repair spends available mining credits at settlement. Enhancement replaces overclock, starts capped at +8, and uses committed future-block entropy. Locks redistribute the fixed mining budget and support district stability; both Green wave and Cheap tariff favor stable districts. Rooms retain age and level gates and require a yield-priced purchase after the free first room.

Weekly token pots receive half the sell surcharge, with 40% for the best farm, three 10% lottery shares, and 30% for the best district's paying farms. The existing best-farm mining allocation remains additional. Free allowlist and Identity MD items mine normally and remain unscrappable until the farm's first paid purchase. Items remain soulbound and now carry on-chain pixel SVG/JSON metadata. Eight district billboards run weekly token auctions.

The code retains immutable deployment identities, exact creation-code enrollment, authenticated pool launch time, endowment funding and hook/router binding gates, lazy settlement, idle expiry, capped governance steps and pull payments. There are no upgrades. Purchases may pause for at most 72 hours with automatic expiry; claims and settlement remain available.

- [Implementation report and open decisions](report.md)
- [Pack options, simulations and limitations](artifacts/v35/simulation.md)
- [Read API and game rules](docs/api-v35.md)
- [v3.8 launch kit, blocker table and open items](launch-v38.md)
- [v3.7 launch parameters, exact oracle bodies and operations](launch-v37.md)
- [M-2 twin front-run trust assumption (v3.12)](docs/m2-trust-assumption.md)
- [Platform research report b94e6839 (copy)](docs/research/b94e6839-platform-report.md)
- [Independent v3.7 contributor review](docs/review-v37-independent.md)
- [Entropy capture operations](docs/entropy-v34.md)
- [Historical v3.4 report](docs/report-v34.md)

## Local checks

The existing compiler configuration (Solidity 0.8.26) and dependencies are unchanged. Default checks need no network or environment variables.

```sh
forge build
python3 tools/pin_module_code.py --check
python3 tools/pin_swarm_code.py --check
python3 tools/check_v37_authority.py
node test/oracle-v37.test.mjs
forge test
forge fmt --check
python3 -m unittest discover -s test/python
node test/reveal.test.mjs
node test/ui-v35.test.mjs
python3 sim/run_v35.py
```

After a Solidity change: format, build, regenerate module pins with `python3 tools/pin_module_code.py`, then `python3 tools/pin_swarm_code.py`, re-flatten the hook (`forge flatten src/V4Market.sol -o launch/V4Market.sol`), rebuild, and check pins. Since v3.13 `foundry.toml` is the launch profile, so the `out/` and `out-launch/` builds are byte-identical and both pins of every role are the same hash; the `FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none` overrides are now no-ops kept for the tools. Creation-code metadata is part of the binding. After changing pins, use a clean build before deriving launch addresses so prediction helpers cannot retain cached embedded bytecode. The opt-in historical fork test remains separate; the real PoolManager integration runs locally.

## After launch

Follow [launch-v38.md](launch-v38.md) (order, wiring calls, objective texts); `launch-v37.md` keeps the oracle bodies and question definitions. The requester supplies the existing token, launch identities and coordinates, and the frozen free-pack / Identity MD roots and snapshot. Balanced packs are fixed at deployment. No swarm wallet is supplied: every swarm authority points to the non-upgradeable SwarmDesk, whose only inputs are attested oracle answers. Both roots are constructor arguments; free claims retain the 30-day window.

Ethereum-funded IMD schedules deliver four event answers per day and one weekly regulator (about 2.0714 IMD/day). Permissionless keepers execute committed answers and enable announced phases after notice. Anyone can top up SwarmDesk with Robinhood IMD for its rate-limited backup asks. No game administrator, signer key, root setter, profile selection or moderation path exists. Oracle endpoints and signer are immutable under this explicit no-admin policy.

Publish the actual registry address for the dependency-free `ui/` app. Its wallet connection reads all modules from that registry and verifies the chain. Run native-block entropy capture continuously, epoch advancement every six hours, safe fee conversion when quotes are warm, and weekly preparation/settlement. Keepers supply gas; bounded heartbeat credits are not a service guarantee. Future-block entropy remains sequencer-influenced, not VRF.
