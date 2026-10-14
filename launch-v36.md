> Historical v3.6 record. Superseded by [launch-v37.md](launch-v37.md); its wallet, profile, root-setting and endowment fallback steps no longer apply.

# BLACKOUT v3.6 launch checklist — token launch to packs opening (no deployment performed here)

Ordered. Each step names who acts. Values marked **requester** are not in this repository and must not be guessed.
X: https://x.com/IMDBlackout · Site: https://playblackout.xyz · Free pack: https://playblackout.xyz/freepack

1. **Freeze the build (contributor).** `forge fmt --check`, `forge build`, `python3 tools/pin_module_code.py --check`, `forge test` on this commit. Archive `out/` creation bytecodes; `src/lib/ModuleCode.sol` pins are the registration truth.
2. **Predict RewardPool (swarm/launcher).** Run `script/PredictGame.s.sol` with the real factory and the launch numbers/indices for jobs A and B to obtain the predicted RewardPool (role 0, job A index 2) and FeeRouter (job B index 0). Verify the factory's `predictContract` on chain before using the addresses.
3. **IMD token launch (requester, `univ4_hook` with the custom hook).** 1B supply, 1.25% swap fee (1% fee recipient = the predicted FeeRouter, 0.25% network). Allocation 70% pool / 20% endowment to the predicted RewardPool / 10% swarm. Documented fallback: if the launcher cannot pre-fund a predicted address, launch 70/10 with the 20% endowment held by the swarm wallet and transfer it to the real RewardPool in step 8 before `selectProfile`. The hook is the archived `launch/V4Market.sol`; initialization by the official launcher anchors every game clock.
4. **Application job A (requester, objective text below).** Params, GameRegistry, RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim. Constructor values: token, swarm wallet, hook/market, Identity MD starter root and snapshot block (**requester**), endowment = 200,000,000e18, HeartbeatBps 200, HeartbeatCap 1 ether, team 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007.
5. **Application job B (requester).** FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards, each with only `(registry)`.
6. **Registration (anyone).** `GameRegistry.register(role, launchNumber, index, creationCode)` for roles 0–13; exact pinned creation code only. `node keeper/keeper.mjs status` must list fourteen modules and all eight features `disabled`.
7. **Binding (launcher/swarm).** Bind the hook to exactly this registry's FeeRouter (authenticated binding, see docs/launch-v35.md). Pack sales stay closed until bound.
8. **Endowment funding (requester).** RewardPool must hold exactly the 200M endowment; `endowed()` must read true. Only player mining can ever move it.
9. **selectProfile(1) (swarm).** Balanced: 5 / 2.5 / 10 yield days, 2% hourly decay, 20 packs per hour. Freezes at the first paid sale.
10. **Keeper start (operator).** Install per `keeper/README.md`, `status` then `once --dry-run`, then `systemctl enable --now blackout-keeper`. Second keeper on a second key recommended.
11. **Packs open** one hour after the authenticated pool initialization, if bound, endowed and profile-selected. Publish the registry address on the site (`ui/` needs it) and announce on X.
12. **Free pack root within 7 days (swarm).** Collect the approved ≤500 wallet list, run `tools/freepack_merkle.py`, `StarterClaim.setFreeRoot(root)` once, publish `ui/allowlist.json`. Claims close at launch +30 days.
13. **Phased release (swarm, on only).** `Civic.announce(feature, letter)` then the keeper or anyone calls `Civic.enable(feature)` after 48 hours. Suggested: 3 enhancement (week 2); 4 locks/stake/lobby (weeks 3–4); 5 billboards and 6 season pot (month 2); then `Enhancement.announceCap(12)` (≥ day 30) and later 16, then 7 reserved events and the dormant modules 0–2 if ever wanted. Nothing can disable a feature; until 6 is enabled the pot share of the sell surcharge is routed as in v3.4 (reward buys).

## Objective text — application job A (7,9xx characters max; this draft is well under 8,000)

> BLACKOUT application job A of two. Deploy, in this order, the eight contracts from repository identity-md-launches/launch-1269-reports-v1-job-b9e37680-814c-4f17-b4bc-6 at the v3.6 commit, exactly as built by `forge build` with the pinned Solidity 0.8.26 configuration (no recompilation, no source edits): Params, GameRegistry, RewardPool, FarmRewards, FarmCore, FarmItems, PackSale, StarterClaim. Constructor arguments: Params(swarmWallet, 200, 1000000000000000000); GameRegistry(token, params, hook market, starterRoot, snapshotBlock, 200000000000000000000000000, applicationFactory); every other contract takes only (registry). The token is the BLACKOUT IMD token launched with the custom univ4 hook; the market is that hook. Do not deploy, replace or mint any token. No owner, no upgrade, no admin key exists in these contracts; the swarm wallet only sets bounded numeric parameters, submits event plans, selects the pack profile once, sets the free-pack root once and announces feature phases. Record each deployed address under its Solidity name. The RewardPool address must equal the prediction supplied with this job; if it does not, stop and report. Project: https://x.com/IMDBlackout — https://playblackout.xyz

## Objective text — application job B

> BLACKOUT application job B of two. Deploy, in this order, the eight contracts from repository identity-md-launches/launch-1269-reports-v1-job-b9e37680-814c-4f17-b4bc-6 at the v3.6 commit, exactly as built with the pinned Solidity 0.8.26 configuration: FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards. Every constructor takes only (registry), the GameRegistry address from job A. After deployment, anyone registers all fourteen roles on the registry with the exact creation code; the registry refuses any other bytecode. The FeeRouter address must equal the fee-recipient prediction used by the token launch; if it does not, stop and report. v3.6 ships with enhancement, locks/stake/lobby, billboards, the season token pot and reserved events disabled in Civic; the swarm enables each once with a 48-hour notice and nothing can disable them. No token is deployed or minted by this job. Project: https://x.com/IMDBlackout — https://playblackout.xyz

## Assumptions and operational responsibilities

- The requester supplies: swarm wallet, hook/launcher identities, Identity MD snapshot root and block, launch numbers/indices, the allowlist. None are in the repository.
- Swarm: profile, free root, event plans, phase letters, Params. Keeper operator: everything in `keeper/README.md`. Team: `FeeRouter.withdraw()`.
- An independent second-contributor review of the v3.6 diff is still open (see report.md); do not launch before it.
