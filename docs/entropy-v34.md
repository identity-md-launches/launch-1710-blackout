# Entropy capture and one-click reveal

The v3.4 browser helper is [ui/reveal.js](../ui/reveal.js), dependency-free and compatible with an injected EIP-1193 wallet. Import `revealReceipt`, then invoke it from the site's single Reveal button with the wallet provider, actual PackSale/StarterClaim address, receipt ID, and optional `count` (1–8 paid packs). Pass `starter:true` for a starter. `onStatus` supplies UI progress. The helper waits for the native target block, sends `resolve`, confirms the transaction and reads the receipt again. A successful re-arm leaves it pending and the same invocation continues to the new target. Wallet confirmation is still required for each transaction; “one click” means one user-initiated flow, not bypassing wallet authorization. Captured entropy never expires. A full inventory or rejected transaction leaves the receipt claimable.

```js
import { revealReceipt } from './reveal.js';
await revealReceipt({
  provider: window.ethereum,
  contract: deployedPackSale,
  receipt: selectedReceipt,
  count: 1,
  onStatus: text => { statusElement.textContent = text; }
});
```

This source adds an integration helper; it does not publish changes to playblackout.xyz. The site maintainer must use its verified deployment addresses. The JS unit test uses a simulated wallet/provider and covers direct reveal and the complete expired/rearmed flow from one invocation.

[tools/entropy_bot.py](../tools/entropy_bot.py) is a separate public entropy keeper. It needs Python's standard library and `cast` from the existing Foundry installation; no package downloads are required. It scans `PackCommitted` and `StarterCommitted` events, records IDs and an EVM log cursor in a caller-selected JSON file, then reads authoritative on-chain receipt state before acting. It samples the native block number through ArbSys on the supported Robinhood main/test networks (4663/46630), matching ChainClock and polls every two seconds by default. It captures even if inventory is full. Completed/captured IDs do not earn duplicate bounties. Expired targets are re-armed by capture, then captured after the new target. It rescans 16 blocks to handle shallow log reorganizations; deeper reorganizations require resetting the cursor to a verified block.

Run it first with `--once` and without `--send` to inspect proposed calls. Supply actual RPC, module addresses, deployment block and a writable state filename as explicit CLI arguments:

```text
python3 tools/entropy_bot.py --rpc-url RPC --packs PACKSALE --starter STARTER \
  --from-block DEPLOYMENT_BLOCK --state keeper-state.json --once
```

The capitalized words are argument descriptions, not deployed values. For continuous operation remove `--once`. To transmit, the operator explicitly adds `--send --sender OPERATOR`; the supplied RPC must expose that separately secured, gas-funded unlocked signer. This tool does not accept, create, print or fund a private key. A production operator may replace the small `Transport.send` interface with their own signing service. No transmission was performed in this task.

The two-second tick is tested with a fake clock: target block itself waits, the immediately following block captures, replay does not submit, and a 257+ block expiry rearms then captures. Two seconds is a polling target, not guaranteed inclusion latency. Monitor inclusion/replacement policy and heartbeat funding; keep more than one independently operated keeper. `cast send` waits for a receipt (45-second process timeout); RPC failures are logged and the next tick rereads state. The keeper only captures, leaving item minting to the reveal UI or a sponsor.

Randomness is still the specified future native blockhash construction. It can be influenced by a sequencer, and a sequencer censoring all captures for an entire window can force a redraw. Re-arming prevents forced fallback devaluation, but does not turn blockhash into verifiable randomness. Neither a receipt holder nor ordinary caller can re-arm a still-available/captured block. No paid pack is refunded or forfeited when entropy expires; the outstanding entitlement is retained.
