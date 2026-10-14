# BLACKOUT v3.6 implementation report

Source-only extension of job b29c69c8 (v3.5). No deployment, broadcast, token action or mint. Build configuration and dependencies unchanged. v3.5 behavior is kept except as listed.

## Changes (phased release)

- `Civic` is the feature-flag registry: eight features (0–2 dormant modules unchanged; 3 enhancement, 4 locks + district stake + lobby, 5 billboards, 6 season token pot, 7 reserved Heatwave/Festival plans). Swarm `announce(feature, letter)` once, anyone `enable(feature)` after 48 hours, no disable path exists. `FarmCore` is untouched (24,330 bytes, 246 headroom); checks live in Enhancement.commit, Economy.lock / lobbyQuote (Core's lobby reverts through it), Billboards.bidBillboard, FeeRouter._route (pot share follows v3.4 routing into reward buys while disabled, `potEnabled()` view) and GridOperator.submitPlan (reserved kinds). New error `FeatureDisabled`. `IGameRegistry.registeredModule` exposed so FeeRouter never reverts on an unregistered Civic. Module pins regenerated.
- Launch core active at launch: packs, ETH zap, gifts, rooms, mining, repair/auto-repair, ordinary events, scrap, free pack, starters, referrals, season best district + lottery, 1% best-farm prize. +12/+16 caps keep the existing announce/activate path.
- Tests: `test/PhasedReleaseV36.t.sol` (launch-core fixture with nothing enabled): every flag disabled by default and core still mines; each feature reverts `FeatureDisabled` then works after enable; pot routing equals v3.4 while disabled; reserved plans; notice/once/never-off/swarm-only; fuzzed unannounced enable. Legacy fixtures enable 3–7 through the real notice path (`Base.enableFeature`). 223 tests pass, 1 optional fork test skipped; invariants unchanged and passing.
- Launch kit: `keeper/` (Node 22+, zero dependencies, own keccak/secp256k1/RLP; env file outside the repo; `status`, `once`, `run`, `--dry-run`; systemd unit; README). Signing was smoke-tested against a local anvil (sent transaction confirmed, sender recovered). `launch-v36.md`: ordered checklist and the two application-job objective drafts.
- Simulation `sim/run_v36.py` → `artifacts/v36/simulation-phases.md`: Balanced core alone (steady/weak/hype/drop50) then each phase. Maintain-only players stay profitable in every phase (steady core: 58.1M tokens mined net of repair, week-1 payback 3.75 days, team 3.58 ETH, 1.8% drawdown; drop50 49.4%). The model holds the 1.4× grower budget fixed, so core-only demand flows into packs/rooms; real willingness to spend without growth features is an open demand question.
- `ui/`: reads Civic flags; disabled features render as "coming soon" teasers without details; dormant modules never shown.

## Open questions

1. Independent second-contributor review of the v3.6 diff has not happened inside this job; it is required before launch (docs/review-v35-independent.md covers v3.5 only).
2. Reserved events: v3.5 never allowed planning Heatwave/Festival; v3.6 reads "disabled at launch" as "plannable by the swarm once feature 7 is enabled". Confirm.
3. Feature enabling after the notice is permissionless (keeper does it); only the announcement is swarm-only. Confirm this matches "the swarm role enables".
4. Requester-only values remain unsupplied: swarm wallet, launcher/hook identities, Identity MD root/snapshot, allowlist, launch numbers.

---

# BLACKOUT v3.5 implementation report (previous)

Source-only extension of job 3470cfdb. No deployment, broadcast, token action, token replacement or mint was performed. The existing compiler, dependencies and build configuration remain unchanged.

## Delivered behavior

- Token-denominated packs and yield-day VRGDA profiles, gifts and atomic official-pool ETH zap. Readiness still requires authenticated launch +1h, funded endowment and exact hook/router binding; it additionally requires explicit profile selection.
- 88/10/2 token pack/lobby routing, bounded official-pool system sales with only normal fees, 30-minute quote and 150 bps floor, five-minute cadence and live-depth sizing. Heartbeat retains its 1 ETH cap. Other spending recycles entirely to rewards; no token burns.
- Tiered output, 1% active-epoch wear, six-hour-per-10% repair quote (bounded 4–8), optional credit-funded auto-repair, yield-priced room purchases behind existing gates, full mining for free starter items.
- Committed future-block enhancement through +16, launch cap +8, exact failure/destruction table, level gates, re-arm without refund/retry, upward-only announced 30-day cap increases and shared enhancement/combo/set cap.
- Escrowed 7/14/30-day locks, fixed-emission hash redistribution, capped district stake, three-day token lobby stability, corrected positive weighting for both Green wave and Cheap tariff.
- Weekly token pots funded by half of sell surcharge, 40/30/30 allocation, distinct lottery winners, four-week claim expiry and rollover, existing separate best-farm mining prize, paid-only starter/prize scrapping.
- Maximum-500 one-time Merkle allowlist, root publication within seven days and day-30 claim closure. On-chain soulbound item JSON/pixel SVG, owner enumeration, glow at +12, eight weekly token billboard auctions and moderation without fund control.
- Reserved zero-weight Heatwave/Festival, once-per-season bounded district promotion, offline-tested dormant features in the existing Civic module. Dormant features are omitted from the public UI/game guide; operating details are in `operations/dormant-v35.md`.
- Dependency-free `ui/` with token/gift/zap purchases, actual-list free claims, inventory/install/repair/enhancement, rooms/locks/lobby, entropy reveal, pot claims and billboard interaction. UI requires the published real registry and actual allowlist proofs; none were guessed.
- Two application jobs of eight contracts each, plus separate custom-hook infrastructure if required. Exact creation-code registration and authenticated binding remain enforced. No upgrades or mutable registry setter exist. Core's registry reference is constructor-only storage to avoid Solidity 0.8.26's immutable patch-table compiler limit.

## Economic results and pack decision

Full reproducible tables: [simulation](artifacts/v35/simulation.md), [raw JSON](artifacts/v35/simulation.json), `python3 sim/run_v35.py`. Five deterministic seeds per profile/scenario, 35 days. The model includes hype/steady/weak, an external 50% price shock, join-week 1/2/3 payback, team ETH, drawdown, repair groups, enhancement caps, sinks, locks, token conservation and pot funding. These are conditional sensitivity results, not promised returns.

| Pack profile | Start / floor / ceiling (average farm yield days) | Hourly decay / target per hour | Start-price maintenance payback |
|---|---|---|---|
| Accessible (0) | 3 / 1.5 / 6 | 3% / 20 | 3.42 days |
| Balanced (1), recommended | 5 / 2.5 / 10 | 2% / 20 | 5.70 days |
| Scarce (2) | 7 / 3.5 / 14 | 1% / 15 | 7.98 days |

The requester chooses; `selectProfile` can switch before the first sale. No deployment choice was made. Balanced gives median steady cohort cash-equivalent payback of 3.75/3.75/3.75 days as the curve decays, team receipts around 3.497 ETH over 35 days, and 1.3% model drawdown; the external 50% shock case has 49.4% drawdown. Cash-equivalent payback includes unsold tokens at the current price, all external funding including repairs, and the mature minimum withdrawal tax; early actual withdrawals can take longer. Token price movements and different demand can make real outcomes worse.

Default six-hour repair at an 80% threshold yields 87.75% of ideal after maintenance over 25 days, versus 53% unrepaired; repair costs 11.5% and incremental output is 4.02× cost. Governance extremes do not all meet the 85–90% target: four hours nets 91.6%, eight hours 83.9%. Floors can break profitability in exhausted/thin mining; there is no subsidy or guarantee.

The separate discrete 35-day growth playbook produces 1.434× spending/mining (30.2% net market funding) with one enhancement attempt every two days, plus yield-priced rooms, inventory packs, weekly lobby and billboards, without forcing a spending ratio. Faster daily enhancement overspends that range; a three-day cadence falls below it. The city model’s growers use an explicit spending budget of 1.4× mined tokens: the resulting net market funding gap is 28.6% of spending, before recoverable lock capital. This demonstrates the desired required purchase share conditional on willingness to grow; it does not prove player demand. Balanced steady five-week sinks are approximately 65.3M packs, 16.7M repair, 24.8M rooms, 24.8M enhancement, 9.9M lobby and 5.0M billboards. Peak escrow is 20.0M tokens; system sales are 9.0M, 4.7% of mining.

At assumed steady taxable turnover of 4 ETH/day and 3% surcharge, the weekly pot receives 0.421–0.435 ETH before token-buy execution. A 0.3–1 ETH/week pot needs about 20–66.7 ETH/week taxable sells at that surcharge. The separate 90-day unlock simulation activates +12 on day 30 and +16 on day 60. The +12/+16 per-item simulations show very high destruction and low cap attainment; they are optional spending goals, not profitable maintenance. Historical v3.4 results and differing demand assumptions are retained and compared explicitly in the simulation report.

## Assumptions and open choices

1. Requester selects pack profile 0/1/2; Balanced is recommended. Review the immutable 3,000-token average-farm bootstrap floor and tiny per-hash item quote floor before a separately authorized launch.
2. Requester supplies the approved allowlist. Swarm sets its actual root once; no sample root or wallet list ships as production configuration.
3. Actual token, hook/launcher/factory identities, swarm, NFT snapshot/root and deployment coordinates remain launch inputs from the prior design. The task supplies no authority to deploy or change those existing identities. Follow [launch-v35](docs/launch-v35.md) and verify real platform prediction and funding guarantees.
4. Ten-percent district influence caps use uncapped district escrow as the denominator; excess capital remains refundable. This makes district bootstrap possible. Lock hash expires at maturity; grid stake persists until withdrawal. War chest score uses the same convention and frozen hash/rate.
5. Pot expiry is four weeks after the competition settlement deadline (week end plus its existing seven-day grace). Claimable items and token awards revert together on inventory failure. Unused slots and rounding remain for rollover.
6. Future native-block randomness preserves the brief and prior architecture; it remains sequencer-influenced, without a claim of production VRF. The keeper needs continuous block capture; expiry re-arms committed outcomes. No arbitrary caller seed, cancel or refund is added.
7. Economic simulations are aggregate models, not full EVM strategy replay. Growth spending is a stated demand assumption; price shock is external repricing, not an impossible synthetic single trade. Full-rate maintenance percentages exclude unchanged withdrawal charges and use mild event damage.

## Validation and independent review

The pinned compiler is Solidity 0.8.26. Tests include success/failure paths for new purchases, escrow, slippage, pause, room/level gates, auto-repair, enhancement expiry/burn/caps, allowlist proofs/windows/provenance, pot allocation/rollback/rollover, billboard refunds and dormant operations. Existing hook-binding, actual local v4 PoolManager, endowment, lazy settlement, referrals, keeper economics, gas, pause and entropy suites remain. Stateful invariants reconcile supply/reserves, quote bounds, lock escrow, allowlist immutability and pot liabilities.

A second contributor reviewed the implementation independently. War outcome dependence on late finalization, auto-repair season credit and item-yield floor precision were fixed, with permanent regression coverage. Zero-output tax redistribution was also corrected to follow productive hash. The review also caught Core runtime size; logic was split into existing modules to respect EIP-170. See [review record](docs/review-v35-independent.md). Tests are not a substitute for the separately authorized pre-release audit.

Final local verification with the unchanged pinned configuration:

| Check | Result |
|---|---|
| `forge clean` followed by `forge build` | Passed, Solidity 0.8.26 |
| `forge test` | 215 passed, 0 failed, 1 optional historical fork skipped; 39 suites |
| Stateful invariants | All seven passed; 128 runs × 64 calls, including supply, pricing, locks, allowlist and pots |
| Fuzz cases | 256 runs per fuzz test, including independent eager/lazy settlement and reserved Festival bounds |
| `forge fmt --check` | Passed |
| `python3 tools/pin_module_code.py --check` | All fourteen module hashes match final artifacts |
| Python unit tests | 34 passed |
| Node UI/reveal test files | 2 passed |
| `python3 sim/run_v35.py` | Reproduced 60 city runs and repair, enhancement, growth and unlock studies |
| `git diff --check` and protected-path comparison | Passed; no protected configuration/dependency changes |

[Machine-readable verification and byte sizes](artifacts/v35/verification.json) records every launch contract. All runtimes fit 24,576 bytes, all creation bytecodes plus constructor arguments fit 49,152 bytes, constructors have at most eight arguments, and no external library links remain. The largest module, `FarmCore`, is 24,330 runtime bytes, leaving 246 bytes of headroom. The flattened hook source was refreshed from the final source. The local actual-v4-PoolManager suite ran; live-chain execution, Slither and Mythril were not performed.
