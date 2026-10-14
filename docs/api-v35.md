# BLACKOUT read API (updated for v3.7)

Swarm authority is the immutable SwarmDesk at `Params.swarmWallet()`. It accepts attested oracle results and has no administrator. See [v3.7 launch and oracle interfaces](../launch-v37.md). Balanced profile1 is fixed; profile selection, free-root setters and billboard moderation are removed.

Resolve modules from `GameRegistry.module(role)`; missing roles revert `NotConfigured`. All token amounts and mining-yield quotes use 18 decimals. Durability, tiers and boosts use basis points unless stated otherwise. Epoch is six hours; season is seven days from authenticated launch. Calls are ordinary `eth_call`; no indexer is required for current wallet inventory.

| Role / contract | Useful reads |
|---|---|
| Registry | `token()`, `params()`, `market()`, `launchTime()`, `module(role)`, `starterRoot()`, `freeRoot()`, `snapshotBlock()` |
| SwarmDesk (via Params) | `lastAnswer(stream)`, `oracleConfig()`, `bindingConfig()`, `lastLetterHash()`, `lastFailure()`, `slot(stream)`; stream0 event,1 regulator |
| 0 RewardPool | `endowed()`, `lockedEndowment()`, `available()`, `reserved()` |
| 1 FarmRewards | `epoch()`, `epochData(e)`, `pending(wallet)`, `lastFarmDaily(wallet)`, `lastAverageDaily()`, `lastYieldPerHash()`, `farmWeight(wallet,e)`, `districtActiveHash(d)`, `epochTime(e)` |
| 2 FarmCore | `hasFarm(wallet)`, `xp(wallet)`, `paidPacks(wallet)`, `level(wallet)`, `district(wallet)`, `roomEligible(wallet,room)`, `roomUnlocked(wallet,room)`, `purchasedRoom(wallet,room)`, `autoRepairThreshold(wallet)`, `itemAt(wallet,room,slot)`, `roomStats(wallet,room)` |
| 3 FarmItems | `ownedCount(wallet)`, `itemsByOwner(wallet,offset,limit)` (limit≤100), `data(id)`, `uri(id)`, `capacity(wallet)` |
| 4 PackSale | `ready()`, `isOpen()`, `paused()`, `opensAt()`, `profile()`, `profileChosen()`, `profileParams(index)`, `priceBounds()`, `quote(count)`, `commits(id)` |
| 5 StarterClaim | `freeRoot()`, `freeClaimed()`, `freeClaimedBy(wallet)`, `freeIndexClaimed(index)`, `freeClaimEnds()`, `claims(receipt)` |
| 6 FeeRouter | `teamTokens()`, `heartbeatTokens()`, `heartbeatBalance()`, `credit(wallet)`, `rewardETH()`, `potETH()`, `sellBatchQuote()`, `lastSell()`, `lastBuy()` |
| 7 GridOperator | `gridStability(d)` (5,000–15,000), `lobbyAmount(d)`, `eventAt(e)`, `planAt(e)`, `outputBonus(e,d)`, `lastOutage(d)` |
| 8 Season | `result(week)`, `pot(week)`, `potRemaining(week)`, `potLiability()`, `claimDeadline(week)`, `lotteryWon(week,wallet)`, `lotteryClaimed(week,wallet)`, `bestClaimed(week)`, `districtClaimed(week,wallet)` |
| 9 FarmEngine | `stats(snapshot,room,active,epoch)` (used by accounting; read item/loadout data for previews) |
| 10 Economy | `farmDaily(wallet)`, `averageDaily()`, `itemDaily(id)`, `repairQuote(id)`, `enhanceQuote(id)`, `roomQuote(wallet,room)`, `lobbyQuote(wallet)`, `lockQuote(wallet,days)`, `locks(wallet)`, `boostAt(wallet,time)`, `districtStake(d)`, `districtTotal(d)` |
| 11 Enhancement | `cap()`, `announcedCap()`, `activationAt()`, `lastRaised()`, `table(nextLevel)`, `pending(id)`, `attempts(receipt)` |
| 13 Billboards | `week()`, `billboard(week,d)`, `refund(wallet)`, `escrow()` |

Use actual ABI artifacts for tuples and function signatures; numeric room indices are 0–3 (human rooms 1–4). Item kind indices remain 0–11, rarities 0–4. Room costs are respectively free, 2, 5 and 10 farm-yield days, in addition to unchanged age/level gates. Item metadata is a base64 JSON data URI containing a base64 SVG image, name such as `+7 ASIC`, kind, rarity, durability, output tier and starter flag; unknown IDs revert.

Durability output is 100% at ≥80%, 85% at ≥60%, 65% at ≥40%, 40% at ≥20%, and zero below 20%. The shared boundary belongs to the higher tier. Wear applies only to active mining epochs. Repair restores all missing health; each 10% costs six hours of that item's healthy mining at the last settled net-of-normal-tariff rate. The displayed quote can change on settlement. Low yield floors still apply.

Enhancement preview returns success percent, conditional destruction percent on failure, hash bonus bps and cost in WAD yield-days. Levels 1–3 retain their level on failure; 4+ lose one level on surviving failure. +6–8 require farm level 7; +9+ require level 10. Commit requires an unequipped, no-longer-active item. The attempt prevents installation, scrapping and another enhancement until resolved. +12 and above glow. All enhancements, combos and sets share the Params bonus ceiling.

District stability combines capped escrow stake with a three-day lobby contribution. At equal city stake it is 1.0×; maximum stake approaches 1.5× positive-event selection and 0.5× negative selection, near-zero stake reverses those weights. Lobby can improve stability up to the same cap. Both Green and Cheap use positive weights. This changes selection probability, never grants immunity. Reserved Heatwave adds 5% cooling-item damage per affected epoch (Airflow and Cold Power protected); Festival output is clamped to +5–15%. Their enum values have zero launch selection weight and cannot be submitted in a launch plan.

## Wallet writes used by the UI

Approve the spending contract for the quoted amount, then call `PackSale.buyPackFor(recipient)` or `buyPacksFor(recipient,count,maxCost)`. `buyWithETH(recipient,count,minTokens,maxCost)` uses the official pool, buys with the received token amount and returns excess tokens to the payer in the same transaction. Gifts register and count as a first paid purchase for the recipient. The payer may be different from the recipient. Pauses cover all purchase entry points and expire automatically after at most 72h.

`FarmCore.repair(id,wallet)`, `buyRoom(room,wallet)`, `lobby(amount,wallet)`, `expand(wallet)` and `buyTokenPack(wallet)` use the established wallet-vs-credit flag (true = wallet). `setAutoRepair(enabled,threshold)` defaults zero threshold input to 8,000; accepted thresholds 2,000–10,000. `Enhancement.commit(id,maxCost,wallet)`, `capture(receipt)`, `resolve(receipt)` implement enhancement. `Economy.lock(amount,days)` accepts 7/14/30 days with minima 5/10/20 farm-yield days and hash weights +5/10/20%; `unlock()` has no early exit.

Free allowlist proof: call `StarterClaim.claimFree(index,proof)`, then capture/resolve the returned receipt. Leaf uses ABI-encoded uint256 index and address, sorted hash pairs. A wallet/index claims once, maximum 500 total. The root is frozen in the Registry constructor; claims end at day30. Starter and prize items mine normally; scrapping requires the owner's first paid purchase. Their starter provenance flag remains in metadata afterward.

Season pot is token-denominated. The ETH-value target is a simulation objective, not an oracle-denominated liability. Lottery entries come from at least one active epoch with capped committed-hash tickets; a paid purchase is not required. Best-farm ranking additionally requires 20 active epochs and positive spend. District prizes require paying participation. Lottery uses unique winners, committed future-block selection, pull claims, four-week expiry/rollover and no administrator withdrawal. Historical v3.4 entropy preparation, capture, re-arm and failure rollback rules continue.
