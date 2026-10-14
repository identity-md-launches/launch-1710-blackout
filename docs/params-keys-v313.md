# Params keys: readers and reserved keys (v3.13)

`Params` holds 45 numeric keys. The regulator stream of `SwarmDesk` can move any of them within its hard
bounds, at most 10% per key per 24 hours, with a public letter. A key is only a lever when some contract
reads it. This register says, for every key, which contract reads it and where, or that it is **reserved
(no effect)**: a regulator step on a reserved key changes storage and burns that key's 24-hour cooldown but
changes nothing in the game.

The regulator vector packs `(index + 1) * 2^248 + target` per word, so the "packed key" column is what an
oracle answer carries; the index is the `Params.Key` enum position.

## Why this exists

Review finding 6d1287b0 (v3.12, medium): `FeeRouter._route` and `routeTokens` credited a literal 200 bps
heartbeat share and never read `Params.HeartbeatBps`, so the regulator lever (packed key 41, bounds
200–5000) burned its cooldown without effect. v3.13 wires that key (the only one whose documentation
promised a live effect) and documents every other reader-less key as reserved instead of wiring it: each
would need a design decision about *what* it should drive, which no brief has made.

## Register

| Index | Packed key | Key | Default | Bounds | Reader (contract: use) |
|---:|---:|---|---:|---|---|
| 0 | 1 | EmissionBps | 350 | 200–600 | FarmRewards: epoch emission snapshot (`advanceEpoch`) |
| 1 | 2 | TariffBps | 1500 | 1000–3000 | FarmRewards: epoch withdrawal tariff snapshot |
| 2 | 3 | PriceStepBps | 100 | 50–200 | PackSale: pack price step |
| 3 | 4 | PriceFloor | 0.006 ETH | 0.004–0.01 ETH | **reserved (no effect)** |
| 4 | 5 | PriceCeiling | 0.03 ETH | 0.02–0.05 ETH | **reserved (no effect)** |
| 5 | 6 | PriceStart | 0.01 ETH | 0.008–0.015 ETH | **reserved (no effect)** |
| 6 | 7 | DemandTarget | 20 | 10–40 | FarmRewards: epoch demand target (`× 6`) |
| 7 | 8 | PriceDecayBps | 200 | 100–400 | **reserved (no effect)** |
| 8 | 9 | RepairBps | 250 | 150–400 | **reserved (no effect)**; see the regulator vector note below |
| 9 | 10 | LobbyKBps | 5000 | 2500–10000 | **reserved (no effect)** |
| 10 | 11 | LobbyMinWeight | 4000 | 4000–7000 | **reserved (no effect)** |
| 11 | 12 | FullSetBps | 1500 | 500–1500 | FarmRewards epoch snapshot → FarmEngine set bonus |
| 12 | 13 | ComputePairBps | 1000 | 500–1000 | FarmRewards epoch snapshot → FarmEngine combo bonus |
| 13 | 14 | TripleCoreBps | 2000 | 1000–2000 | same |
| 14 | 15 | AirflowBps | 500 | 250–500 | same |
| 15 | 16 | ElectricityPairBps | 1500 | 500–1500 | same |
| 16 | 17 | OffgridBps | 2000 | 1000–2000 | same |
| 17 | 18 | RareSetBps | 500 | 250–500 | same |
| 18 | 19 | EpicSetBps | 1000 | 500–1000 | same |
| 19 | 20 | LegendarySetBps | 2000 | 1000–2000 | same |
| 20 | 21 | MythicSetBps | 3000 | 1500–3000 | same |
| 21 | 22 | SetCapBps | 10000 | 8000–10000 | FarmRewards epoch snapshot → FarmEngine bonus ceiling |
| 22 | 23 | BuyBatch | 0.5 ETH | 0.1–1 ETH | FeeRouter: reward and pot buy batch size, buy-bounty scale |
| 23 | 24 | SlippageBps | 150 | 10–150 | FeeRouter: reward buy minimum-output floor |
| 24 | 25 | SellHourBps | 500 | 200–600 | **reserved (no effect)** (the hook has its own fixed sell schedule) |
| 25 | 26 | SellDayBps | 400 | 100–500 | **reserved (no effect)** |
| 26 | 27 | SellDeviationBps | 5000 | 2000–5000 | **reserved (no effect)** |
| 27 | 28 | Bounty | 0.001 ETH | 0.0005–0.003 ETH | FeeRouter: `advanceEpoch` bounty (`payBounty`) |
| 28 | 29 | ExpansionPrice | 100 tokens | 50–500 | **reserved (no effect)** |
| 29 | 30 | MergePrice | 50 tokens | 25–250 | **reserved (no effect)** |
| 30 | 31 | OverclockPrice | 100 tokens | 50–500 | **reserved (no effect)** |
| 31 | 32 | PositiveWeight | 2500 | 2000–5000 | GridOperator: positive-event weight |
| 32 | 33 | DripPeriod | 42 days | 14–56 days | RewardPool: endowment drip length, read once at `fundEndowment` |
| 33 | 34 | MeasureBounty | 0.00006 ETH | 0.00001–0.0002 ETH | **reserved (no effect)** |
| 34 | 35 | CreditBounty | 0.00004 ETH | 0.000003–0.00005 ETH | **reserved (no effect)** |
| 35 | 36 | AuditBounty | 0.00001 ETH | 0.000001–0.00003 ETH | **reserved (no effect)** |
| 36 | 37 | BuyBounty | 0.00015 ETH | 0.000005–0.0003 ETH | FeeRouter: reward buy bounty cap |
| 37 | 38 | EntropyBounty | 0.00001 ETH | 0.000002–0.00005 ETH | FeeRouter `payWork` for GridOperator, PackSale, StarterClaim entropy |
| 38 | 39 | SeasonScoreBounty | 0.00001 ETH | 0.000001–0.00002 ETH | **reserved (no effect)** |
| 39 | 40 | SeasonBounty | 0.00004 ETH | 0.00001–0.0002 ETH | FeeRouter `payWork` for Season finalization |
| 40 | 41 | HeartbeatBps | 200 | 200–5000 | **FeeRouter (v3.13)**: heartbeat share of the sell surcharge (`_route`) and of routed tokens (`routeTokens`) |
| 41 | 42 | KeeperGasPrice | 0.05 gwei | 0.001–0.1 gwei | FeeRouter: gas-price ceiling of work reimbursements |
| 42 | 43 | HeartbeatCap | 1 ETH | 1–1 ETH | FeeRouter: heartbeat balance cap (fixed) |
| 43 | 44 | AuditHashThreshold | 100000 | 10000–10000000 | FarmRewards: audit hash threshold snapshot |
| 44 | 45 | RepairHours | 6 (WAD) | 4–8 | Economy: repair quote |

Seventeen keys are reserved: 3, 4, 5, 7, 8, 9, 10, 24, 25, 26, 28, 29, 30, 33, 34, 35, 38. They stay in
the enum because removing or renumbering them would change the `Params` creation code (pinned as
`SwarmCode.PARAMS_LAUNCH`) and the key numbering every regulator body uses.

## The HeartbeatBps split (v3.13)

- Sell surcharge (`_route`, stream 3): team 10% and, when Civic feature 6 is enabled, pot 50% are taken first
  and never move. The heartbeat takes `HeartbeatBps` of the whole amount, limited by the room under the
  1 ETH cap and by what is left after team and pot. The rest goes to reward buys. At the launch value of
  200 bps the split is exactly the v3.4 one (0.5 / 0.1 / 0.02 / 0.38 of 1 ETH with the pot on). A raised
  share comes out of reward buys only; above 4000 bps with the pot on it is clipped to the 40% that is left,
  so the arithmetic can never underflow.
- Routed tokens (`routeTokens`): team 10%, heartbeat `HeartbeatBps` while the heartbeat balance is under the
  cap (zero at the cap), the rest to the RewardPool.
- Sales of queued tokens (`executeSells`) and the cap-overflow rule are unchanged.
- Tests: `test/HeartbeatBpsV313.t.sol` (default split, the 220-bps case: 0.022 ETH of a 1 ETH surcharge and
  0.022e18 of 1e18 routed tokens, cap, floor, 5000-bps clip, fuzzed conservation, authority/bounds/step/
  cooldown failures) and `SwarmDeskV37Test.testDeskSetHeartbeatBpsMovesFeeRouterShare` (the value set by a
  Desk-executed regulator vector carrying packed key 41).

## The committed regulator vector (`docs/oracle-v37/regulator.json`)

The committed question proposes these `(index, target)` pairs: (0, 350), (1, 1500), (8, 250), (31, 2500),
(23, 150), (40, 200), (27, 1000000000000000), (44, 6000000000000000000).

| Index | Key | Reader? | Effect of the committed proposal |
|---:|---|---|---|
| 0 | EmissionBps | yes | target = default, skipped by the Desk (`target == old`) |
| 1 | TariffBps | yes | same |
| 8 | RepairBps | **no, reserved** | target = default, skipped; a different value would only burn the key's cooldown |
| 31 | PositiveWeight | yes | target = default, skipped |
| 23 | SlippageBps | yes | target = default, skipped |
| 40 | HeartbeatBps | yes since v3.13 | target = default, skipped |
| 27 | Bounty | yes | target = default, skipped |
| 44 | RepairHours | yes | target = default, skipped |

**Reported:** index 8 (`RepairBps`, packed key 9) is in the committed vector and has no reader. It is not
removed here because the vector is the committed regulator body: its hash is `oracle-config.json`
`bodies[1]`, its question hash is `questions[1]`, and both are two of the twelve SwarmDesk constructor
words, which this job keeps as given. The proposal is harmless: it carries the key's default, so the Desk
skips it, and if a panel ever answered a different value the only effect would be a storage write and that
key's 24-hour cooldown. Dropping it needs a re-cut of the regulator body, which moves `bodies[1]`,
`questions[1]` and therefore the SwarmDesk constructor words (not its creation code), in a job that re-pins
the M1 objective.
