# BLACKOUT v3.14 accepted low and informational findings

- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding.
