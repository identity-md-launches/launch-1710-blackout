# BLACKOUT v3.3 report — no deployment

v3.3 changes the v3.2 contracts from job 9c938888 in source only. Nothing was deployed, and the token was not touched. Everything not listed below is the same as in v3.2: lazy accounting, 2% heartbeat with a 1 ETH cap, 20% endowment (poolBps 7000), 42-day drip, the one-time FeeRouter bind, the two launches (8+4) with GameRegistry, and the team address `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`. The v3.2 report is in [docs/report-v32.md](docs/report-v32.md). The launch steps are in [docs/launch-v31.md](docs/launch-v31.md), under the "v3.3 changes" section.

## What changed

### 1. Idle farms stop diluting (`FarmRewards`)
- Every owner action re-commits the farm's allocation hash for `IDLE_EPOCHS = 12` epochs (3 days), starting with the next epoch. Owner actions are `FarmCore.sync()` (new), claim, install/unplace, repair, overclock, expand, pack, token pack, lobby and scrap.
- `_commit` puts the weight in the bucket `expiring[epoch+13]` and takes the farm's previous pending bucket out. When `advanceEpoch` starts epoch *n*, it subtracts `expiring[n]` from `nextTotalHash`. That is one storage read and one delete, with no loop over farms. A test shows that 15 farms expiring together cost the same as one (`testAdvanceIsConstantInExpiringFarms`).
- `farmWeight(p, e)` returns 0 for epochs at or after the expiry. Epochs a farm earned before expiring keep their weight and stay claimable whenever they are settled. Late settlement pays exactly the same as on-time settlement (`testRewardsEarnedBeforeExpiryAreNeverLost`).
- `claim` re-commits only when the farm is fully caught up. A partial catch-up still pays out but does not re-commit (`testClaimDoesNotRecommitWhileBehind`).
- Settling someone else's farm (`settle(p, n)`) does not count as an owner action and does not re-commit it.
- An expired farm earns nothing and gets no activity XP. The engine still applies event and wear effects when its epochs are settled, as in v3.2. Players should `sync` at least every 3 days.

**Tokens returned to active players (simulation, 20% endowment, day 35):** these are the unsettled reservations held for departed farms ("stuck" envelopes).

| Scenario | v3.2 stuck | v3.3 stuck | Returned to active players |
|---|---:|---:|---:|
| steady | 176.37M | 53.92M | **122.45M** |
| hype | 228.28M | 81.52M | **146.76M** |
| weak | 136.72M | 41.98M | **94.74M** |

The v3.3 figure still includes each departed farm's last 12 epochs, which it can claim later. Those tokens are owed, not lost.

### 2. Anti-rush (`FarmCore`, `Season`)
- `level(p) = min(xpLevel(p), maxLevelByAge(p))`. The age caps are: under 1 day → 4, under 3 days → 6, under 5 days → 9, otherwise 10. In other words, level 5 needs 1 day, level 7 needs 3 days and level 10 needs 5 days. Room unlocks and rarity gates use the capped level, so paid XP cannot get around them (`testPaidXpCannotBypassAgeGates` uses the maximum paid XP every day plus all activity XP).
- Paid XP (25 per pack or token pack, plus spending XP from repair, overclock, expand, cable repair and lobby) is limited to `PAID_XP_PER_DAY = 400` per farm per UTC day. Any excess is cut off, and the purchase itself still goes through. Activity XP (100 per active epoch) has no cap.
- **Merging is removed** (`merge` and the `Merged` event no longer exist). Spare items can be installed, scrapped, or kept once inventory is expanded. Legendary and Mythic items now come only from packs (`PackSale`) and season prizes (lottery: rare/epic; district pack). Supply drops still mint only common/uncommon.
- **Best district each week:** `Season.districtScore(w,d)` is the counted spend divided by the number of farms in district *d* that were active that week (farms with at least one settled active epoch). One wallet counts for at most 10% of the counted spend. The cap *c* is the exact solution of `c = Σ min(spend_i, c) / 10`. It is computed from a top-10 spender list kept for each district and week. Only the top 10 matter, because at most ten wallets can be at or above the cap. `finalize` picks the highest score. **Consequence:** a district with fewer than 10 spending wallets has no valid allocation under the 10% cap and scores 0 (`testSingleWhaleDistrictCannotWinAlone`). If every district scores 0, district 0 wins by the existing tie rule.

### 3. Team share (`FeeRouter`)
- Packs, lobbying and the sell surcharge split **88% reward pool / 10% team (`TEAM_BPS = 1000`) / 2% heartbeat**. The heartbeat is capped at 1 ETH and anything over the cap goes to the pool.
- The swap base fee stays at 1% team / 1% reward pool.
- The new `depositLaunchTax()` (callable only by the market) sends 100% to reward buys.

### 4. Launch protection (custom hook `V4Market`, flattened as `launch/V4Market.sol`)
- The anchor is the pool's one-time `afterInitialize` timestamp (`initializedAt`). It cannot be reset, and the hook has no owner.
- **Buy tax:** `currentBuyTaxBps()` is 9000 at launch and falls linearly to the normal fee (2% project + 0.25% network = 225 bps) over `LAUNCH_TAX_DECAY = 30 minutes`. The part above the normal fee is held as `heldLaunchTax` and `flushFees()` sends it to `FeeRouter.depositLaunchTax` (100% reward pool, no team share). The normal 2% + 0.25% fee keeps its usual split.
- **Max buy:** `MAX_BUY = 0.5 ETH` of input per swap for `MAX_BUY_WINDOW = 60 minutes`. This also applies to the FeeRouter's own system buys.
- Sells pay the normal fee plus the existing progressive surcharge (15% total cap) and are not affected by the launch tax.
- Views for the site: `currentBuyTaxBps()`, `launchTaxTimeLeft()`, `maxBuy()`, `maxBuyTimeLeft()`, `sinceLaunch()`, and `launchStatus()` which returns all of them in one call.
- **PackSale** opens at `GameRegistry.launchTime + OPEN_DELAY (60 minutes)`. That time is immutable (`opensAt()`, `isOpen()`) and covers both ETH packs and token packs. The VRGDA price clock now starts when sales open, so buyers at opening do not get a decayed price.
- All constants are fixed in bytecode. Nothing about the launch tax, the max-buy window or the opening time can be changed.

### Pausing and upgrades (unchanged)
Nothing is upgradeable. The swarm role can pause only new PackSale purchases (ETH packs and token packs), for at most 72 hours. The pause expires on its own, and another pause cannot start until 72 hours after the previous one ends. Claims, withdrawals, sync, settle, advanceEpoch, entropy, buybacks and season finalize cannot be paused.

## Simulation (v3.3, 20% endowment, 42-day drip, players sync daily)

Source: `sim/blackout_sim_v33.py` (derived from the v3.2 model) and `sim/run_v33.py`. Results are in [artifacts/v33/simulation.json](artifacts/v33/simulation.json). Reproduce with `python3 sim/run_v33.py --output artifacts/v33` (standard library only, about 45 s).

| Scenario | Week-1 median payback | Repaid cohort | Stall day | Price drawdown | Team ETH | Heartbeat coverage (paid/due) | Min HB headroom |
|---|---:|---:|---:|---:|---:|---:|---:|
| steady | 22.5 d (v3.2: 28.5) | 60.6% | >35 | 29.1% | 11.16 | 100% (0.2033/0.2033) | 0.025 |
| hype | not reached | 23.2% | 18.75 | 94.0% | 15.40 | 100% (0.1931/0.1931) | 0.098 |
| weak | not reached | 18.9% | >35 | 38.0% | 2.10 | 100% (0.1647/0.1647) | 0.006 |

- Team ETH fell from 13.22 / 18.48 / 2.45 to 11.16 / 15.40 / 2.10 because the team share went from 13% to 10%. That 3% now goes to reward buys.
- Payback in the steady case improves by 6 days, mainly because idle expiry returns about 122M tokens to active farms. Hype and weak still do not pay back within 35 days. The drawdown is higher than in v3.2 because more tokens reach active players, who then sell.
- **Daily sync:** settlement gas per owner in the model is unchanged, because the same number of epochs is settled in daily batches. Total owner gas is 6.38 / 7.61 / 3.01 ETH across all players. A player who stops for more than 3 days stops earning.

### Whale (one wallet buys 300 packs on day 1, steady)
The whale paid 5.94 ETH. Its share of total emission (its committed hash ÷ total committed hash):

| Day | Whale share |
|---:|---:|
| 1 (first committed epoch) | **4.04%** |
| 3 | **3.18%** |
| 7 | **2.11%** |

It holds about 900 items, but it can only equip one room until day 3 (age gate) and starts with level 4 (paid-XP cap), so it cannot use its Legendary or Mythic items early. Its 400 paid XP per day plus activity XP reach level 10 only at day 5.

### Snipers (bots buy 5 ETH in the first minute, as 10 × 0.5 ETH max buys)
Single-sided model AMM at the 20% endowment opening cap, with no other trading.

| | With v3.3 launch tax | Without (v3.2) |
|---|---:|---:|
| Bot cost | 5.00 ETH | 5.00 ETH |
| Tokens received | 48.0M | 270.1M |
| Launch tax collected to reward pool | **4.314 ETH** | 0 |
| Price after snipe = at 30 min = at 60 min (no other flow) | +15.3% | +165.2% |
| Bot result if dumped at 30/60 min (15% capped sell fee) | **−4.51 ETH** | −0.85 ETH |

Because no other trades are modelled, the price at 30 and 60 minutes equals the price right after the snipe. Organic buyers arriving in that window pay the remaining tax on the curve. The sell fee cap is a worst case for the bots.

## Tests

`forge build`, `forge test` (159 passed, 0 failed, 1 skipped — the existing opt-in fork test) and `forge fmt --check` pass with solc 0.8.26 as pinned in foundry.toml. New tests are in `test/V33.t.sol`:
- idle expiry: drop-out after 12 epochs, no reward loss when settled late, `sync`/claim/pack re-commit from the next epoch, moving the bucket without double counting, no re-commit while behind, constant-cost advance;
- anti-rush: age caps at every boundary, the paid-XP daily cap and its daily reset, partial clipping, uncapped activity XP, paid XP unable to bypass the level 7/10 gates (rooms and Mythic), merge removed, district average per active farm, the 10% wallet cap (exact fixed point and top-10 tracking), a lone-whale district;
- split: 88/10/2 for packs, lobbying and the surcharge, the heartbeat cap overflow going to the pool, the 1%/1% base fee, launch tax only from the market and 100% to the pool;
- hook: views before initialization, the tax curve at 0/15/29/30 minutes and 10 days, the tax going to the pool through flush, a normal buy after the decay, sells during launch, the max buy at 59/60 minutes, split sniper buys;
- PackSale: opening time at T−1 s and T, token packs gated as well.

Existing tests were updated for v3.3 semantics: the test token launch is 1 hour before the fixture start so that sales are open, there are 10% split numbers, buys happen after the launch window, players sync every 8 epochs in long runs, and there is a `veteran()` fixture that backdates an older farm. The v3.2 ArbSys clock test now uses `vm.mockCall`, because Foundry 1.8 reserves address 0x64 and the old test failed in v3.2 as well.

The module creation-code pins (`src/lib/ModuleCode.sol`) were regenerated with `tools/pin_module_code.py`, and `--check` passes.

## Review

No independent second contributor was available in this run. The review in [docs/review-v33.md](docs/review-v33.md) was done by the same author with a fresh checklist pass (eth-security reference). **An independent adversarial review is still required before any launch.**

## Assumptions and open items
- The hook's launch clock is pool initialization, while PackSale's is `GameRegistry.launchTime`. The launch must pass the token launch timestamp (the pool initialization time) to GameRegistry, so that sales open exactly 60 minutes after the pool.
- The 10% wallet cap means a district needs at least 10 spending wallets to score. If you would prefer "a wallet counts for at most 10% of the district's total spend" (a softer rule under which small districts can still win), that is a one-line change. **This is a decision for the requester.**
- The paid-XP day is the UTC day (`block.timestamp / 1 days`), not a rolling 24 hours.
- The simulation is a scenario model, not an EVM emulator. The v3.2 comparison uses the figures from the v3.2 report.
