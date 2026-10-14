# BLACKOUT keeper (v3.9 launch kit)

A single-file Node 22+ keeper with **no npm dependencies** (`lib/eth.mjs` carries its own keccak-256,
secp256k1 signing, RLP and a tiny static ABI encoder; `lib/abi.mjs` adds dynamic `bytes`/tuple encoding for
the relay and wiring calls; `node keeper.mjs` needs nothing installed beyond Node).

## What it does, every pass (default every 2 seconds)

| Duty | Calls | Notes |
|---|---|---|
| **Attestation relay (v3.9)** | `GET /schedules/:id` for the event and regulator schedules, `GET /oracle/requests/:id/attestation`, then `SwarmDesk.submit(attestation, signature)` | Schedules are bought on Ethereum with `consumer {chainId 4663, verifyingContract DESK}` and cannot deliver cross-chain; anyone relays the attester's bytes. The keeper checks the document is signed for the Desk on this chain with one of the Desk's two question commitments and is not yet consumed, then simulates. It has no authority: the Desk re-verifies signature, question, window, panel, slot, epoch and UUID. Polled every `RELAY_INTERVAL` seconds (default 60) |
| Oracle execution | Recover `AnswerStored` at the stored native block, verify matching UUID, then `SwarmDesk.execute(stream, answer)` | Runs before epoch advancement; the contract verifies the answer commitment and bounds |
| Advance epochs | `FarmRewards.advanceEpoch()` when `live()` and `epochEnd()` has passed; `GridOperator.resolve(epoch)` if the event is still unresolved. v3.17: if the event's 256-block window lapsed, the call re-arms it (`EventRearmed`, `EpochCloseDeferred`) and returns without closing; call `resolve(epoch)` or `advanceEpoch()` again at least two blocks later, inside the new window | Caller receives the epoch bounty from the heartbeat balance once the epoch closes |
| Pack entropy | scans `PackCommitted` logs, then `PackSale.captureEntropy(id)` or `rearm(id)` after the 256-block window | Capture is paid the entropy bounty; packs never lose value |
| Starter entropy | `StarterCommitted` logs, `StarterClaim.captureEntropy` / `rearm` | Same window rules |
| Enhancement | `EnhancementCommitted` logs, `Enhancement.capture(id)` then `resolve(id)` | Resolve reverts while the item is equipped; the keeper retries later. v3.17: an attempt past its window lapses on the first `capture`/`resolve` to the worst outcome of its level (`EnhancementLapsed`); there is no re-arm |
| Seasons | `Season.prepare(w, 64)` for past weeks after their deadline, `finalize(w)` / `rearm(w)` after `SeasonPrepared`, `rollover(w)` for expired pots | Permissionless, bounty-paid |
| Billboards | `Billboards.settleBillboard(week, d)` for the eight districts | No-op until the billboards phase is enabled |
| Hook flush | `V4Market.flushFees()` when the hook holds base, surcharge or launch-tax ETH | v3.9: the 1% base stream is all reward ETH |
| System sells | `FeeRouter.sellBatchQuote()` then `executeSells(amount, minimum)` | Exactly the quoted batch, 150 bps floor, five-minute cadence enforced on chain |
| Reward / pot buys | `executeBuys` / `executePotBuys` with `market.quote()` and the Params slippage floor | Batch ≤ Params `BuyBatch`, ≥ 0.05 ETH or the remaining queue |
| Phased release | `Civic.enable(feature)` once a swarm notice has aged 48 hours; `Enhancement.activateCap()` once announced | The keeper can only turn features **on** after the swarm's letter; nothing can turn them off |
| **Platform fee claim (v3.9)** | `LaunchFactory.claimFees(tokenLaunch)` at most every `CLAIM_INTERVAL` seconds (default 6 h) | Permissionless. Pays the pool's 1% to the paying wallet and 0.25% to the IMD network. The simulation returns the two amounts; nothing is sent when both are zero. Needs `LAUNCH_FACTORY` and `TOKEN_LAUNCH` |

Every action is simulated with `eth_call` first and only sent when the simulation succeeds, so disabled
phases, early calls and already-done work never cost gas. Transactions are EIP-1559, signed locally, and
sent through `eth_sendRawTransaction`; the keeper waits for the receipt and logs reverts.

## Post-launch wiring (v3.9): `node keeper.mjs wire`

```sh
node keeper.mjs wire --wiring /etc/blackout/wiring.json --dry-run --env /etc/blackout/keeper.env   # simulate every step
node keeper.mjs wire --wiring /etc/blackout/wiring.json --env /etc/blackout/keeper.env             # send what is due, in order
node keeper.mjs wire --wiring ... --step bind-desk                                                 # print the bind calldata for the binder (never sent)
```

`wiring.json` (template: `keeper/wiring.example.json`) holds the recorded addresses and launch numbers from
`GET /launches/:id` (Desk, escrow, registry, LaunchFactory, token launch number, job A and job B launch numbers
with their contract lists in manifest order) and the artifact directories to read creation code from
(`out-launch` for the IMD verifier toolchain, `out` for the repository toolchain; the first whose initcode the
chain accepts is used, and a wrong artifact only fails the simulation). The steps run in this order and each is
idempotent (already-done steps are reported and skipped):

1. **`bind-desk`** — right after job A is recorded. **v3.16: the keeper never sends this call.** `SwarmDesk.bind` reverts `Unauthorized` for every caller except the Desk's pinned `binder` (the project wallet `0x6d51…d007`, the Desk's eighth constructor word), so the step reads `Desk.binder()`, builds `bind(registry, registryCode, paramsCode, launchA, registryIndex, launchA, paramsIndex, tokenLaunch)`, simulates it with `from: binder` for each artifact toolchain and **prints the transaction (from, to, value 0, chainId, estimated gas, data) for the binder wallet to sign and send** with its own tooling (hardware wallet, `cast send --from`, etc.). The last word is the **L2 token launch number** (`wiring.tokenLaunch`): the Desk reads `LaunchFactory.positionOf(tokenLaunch)` and refuses a registry whose market is not the hook that record names for the registry's token, so the step fails closed if `tokenLaunch` is missing or the simulation from the binder reverts. Once the binder's transaction confirms, re-run `wire`: the step then **reads `Desk.registry()` and stops with an error if it is not the wiring registry**. `bind-router` and `forward` are reported as not due until the Desk is bound to the wiring registry. The keeper key is never the binder; if it happens to be, the step still only prints.
2. **`register`** — `GameRegistry.register(role, launch, index, creationCode)` for every role whose job is recorded (A's six modules first, B's eight once job B exists).
3. **`bind-router`** — `V4Market.bindFeeRouter(FeeRouter, launchA, registryIndex)` once role 6 is registered.
4. **`forward`** — `EndowmentEscrow.forward(registry, launchA, registryIndex, registryCode, launchA, poolIndex, poolCode)` once role 0 is registered and the Desk is bound.
5. **`fund`** — `RewardPool.fundEndowment()`.
6. **`claim-fees`** — `LaunchFactory.claimFees(tokenLaunch)`; afterwards the run loop repeats it periodically.

Run `wire` once after job A (step 1 prints the bind for the binder; step 2 registers A's modules), again after
the binder has bound and after job B (the rest). Steps 2–6 are permissionless and the keeper key only pays gas;
step 1 is the binder's transaction and is only printed here. The whole sequence was exercised against the local fixture graph in `forge test`
(the same calldata encoders are checked byte-for-byte against `cast calldata` in `test/keeper-v39.test.mjs`);
it was **not** run against a live chain in this job.

## Install on a Linux VPS

```sh
sudo useradd --system --home /opt/blackout --shell /usr/sbin/nologin blackout
sudo mkdir -p /opt/blackout /etc/blackout /var/lib/blackout
sudo cp -r keeper /opt/blackout/keeper
sudo cp keeper/keeper.env.example /etc/blackout/keeper.env   # then edit: RPC_URL, REGISTRY, KEEPER_KEY, schedules, launch factory
sudo cp keeper/wiring.example.json /etc/blackout/wiring.json # then fill from GET /launches/:id
sudo chown -R blackout:blackout /opt/blackout /etc/blackout /var/lib/blackout
sudo chmod 0600 /etc/blackout/keeper.env
sudo cp keeper/blackout-keeper.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now blackout-keeper
journalctl -u blackout-keeper -f
```

The env file is the **only** place the RPC URL and keeper key are read from. It sits outside the
repository; nothing in `keeper/` or the state file ever contains a key. Use a dedicated hot wallet with a
small ETH float. Bounties (epoch, entropy, season, buy/sell work) are credited in FeeRouter and withdrawn
with `FeeRouter.withdraw()` by the keeper address; top the float up from there. Relay, wiring and
`claimFees` transactions carry no bounty: they are operator-sponsored gas.

## Commands

```sh
node keeper.mjs status --env /etc/blackout/keeper.env     # read-only: epoch, week, queues, phase flags, relay/claim status, what is due
node keeper.mjs once --dry-run --env ...                  # one pass, simulate only, print what would be sent
node keeper.mjs once --env ...                            # one pass, send
node keeper.mjs run --interval 2 --env ...                # loop (what the systemd unit runs)
node keeper.mjs relay --request UUID --env ...            # relay one attested answer by hand
node keeper.mjs wire --wiring FILE [--step S] --env ...   # post-launch wiring (see above)
node keeper.mjs ask-backup --stream event|regulator --dry-run --env ...
```

`status` and `--dry-run` work without `KEEPER_KEY`. The state file (`STATE_FILE`, default
`/var/lib/blackout/keeper-state.json`) only holds the last scanned block, pending commit ids, relayed request
ids and the last claim time; deleting it is safe (the keeper rescans and skips completed work).

## Before launch

- Run `wire --dry-run` against the recorded addresses: every step must simulate or report "already"; `bind-desk`
  must simulate from `Desk.binder()` and print the calldata (it is never sent by the keeper), and after the binder
  sends it the step must report `already bound to <REGISTRY>`.
- Run `status` against the registry after wiring: it must list all fourteen modules, show the Desk bound to
  the registry and every phase as `disabled`.
- Keep one keeper per key (nonces are read from the node; two instances on one key would collide). A second
  VPS with its own key is fine and recommended for redundancy: all duties are permissionless and idempotent.
- The keeper never calls `announce`, `submitPlan`, Params setters or any swarm-only function. SwarmDesk alone
  can call those functions after verifying an oracle answer. Removed profile/root/moderation selectors are never called.

## Oracle relay, backup and status

`status` includes both last answer times, pending execution, UTC slots, failure status, the configured
schedules (status, runs left, next run) and SwarmDesk's Robinhood IMD balance. The UI shows the last answer
vector, the next epoch plan and the wiring status. No oracle signer key is used by the keeper.

The two schedules are bought on Ethereum (see `launch-v39.md`) with `consumer {chainId: 4663,
verifyingContract: DESK}` and **no** `deliver`. Put their UUIDs in `SCHEDULE_EVENT` and `SCHEDULE_REGULATOR`.
The relay reads the newest opened runs, fetches each attestation once it exists and submits it. A relayed
answer that the Desk ignores (stale slot, second answer in a slot, wrong epoch) is a no-op on chain and is
recorded as relayed; a document signed for another contract or another question is refused locally.

From the repository root, `node keeper/keeper.mjs ask-backup --stream event --dry-run --env /etc/blackout/keeper.env` simulates a paid backup. Use `--stream regulator` for the weekly question. A separately authorized operator removes `--dry-run` to send. `--body PATH` selects the exact committed compact body; the contract rejects any changed byte. Copy `docs/oracle-v37/` beside the installed keeper or use absolute `--body` paths. This assignment did not send either command on a live chain.

A backup is available one hour into each UTC slot, at most once per slot, only if no answer was already accepted. A failed ask spends its price; no same-slot retry or refund. The endpoint price must be at or below the immutable maxPrice (0.5 IMD). Anyone may transfer Robinhood IMD to the Desk; there is no withdrawal. Funding this optional balance permits anyone to trigger its bounded schedule of asks. An unrelated gas payer may run all keeper duties; they gain no authority over the answer or modules.
