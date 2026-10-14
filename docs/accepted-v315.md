# BLACKOUT v3.15 accepted low and informational findings

The eight v3.14 lines are unchanged. Control audit 031c93c4 added finding 1 (medium, `SwarmDesk.bind` accepted a
market that merely echoed `desk()`, `token()` and `gameConfigHash()`), which v3.15 **fixes** rather than accepts:
`bind` now takes the L2 launch number and requires the LaunchFactory's own `positionOf(tokenLaunch)` record to
name both the registry's token and its market. The remaining 031c93c4 findings, low 2 to info 6, are accepted below.
Only the finding numbers and one-line subjects of info 5 and info 6 were supplied to this job; copy their text from
the audit before pasting the objectives.

- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding.
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by an identical copy: `register` is permissionless and accepts any factory coordinates whose CREATE2 result is the pinned module code constructed with this registry, so a byte-identical copy launched through the ProjectFactory could take a role before the keeper registers the recorded job A/B module; the copy runs the same pinned code against the same registry, no authority or funds move, and the keeper registers every role immediately after each launch is recorded and verifies `module(role)` against the recorded addresses before any further wiring.
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: once a week's claim deadline passes, its unclaimed pot can be rolled into the current week whether or not that week was finalized, so a week nobody finalized rolls its whole pot forward instead of paying its winners; mitigated by the keeper finalizing every week (finalize, then rollover, in its weekly pass), and a rollover only moves the pot to later players, never out of the game.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: the heartbeat-excess sweep to RewardPool at the top of `executeSells` shares the transaction with the sell, so a sell that reverts (unfillable minimum, market failure) also rolls the sweep back; the sweep repeats on the next successful call and no value is lost.
- Accepted — 031c93c4 info 5: (copy the finding text verbatim from audit 031c93c4; only its number was supplied to the v3.15 job).
- Accepted — 031c93c4 info 6: (copy the finding text verbatim from audit 031c93c4; only its number was supplied to the v3.15 job).
