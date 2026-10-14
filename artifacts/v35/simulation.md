# BLACKOUT v3.5: offline economic sensitivity study

Five deterministic seeds, 35 days, six-hour epochs, 1B conserved tokens, 20% endowment / 42-day drip. No network, swaps, or deployments. Results are conditional model outputs, not return guarantees.

## Pack options (token yield-days, never ETH-pegged)

| Choice | Start / floor / ceiling | Decay per hour behind schedule | Target packs/hour | Constant-rate maintenance payback at start / floor |
|---|---|---|---|---|
| Accessible | 3 / 1.5 / 6 days | 3% | 20 | 3.42 / 1.71 days |
| Balanced | 5 / 2.5 / 10 days | 2% | 20 | 5.70 / 2.85 days |
| Scarce | 7 / 3.5 / 14 days | 1% | 15 | 7.98 / 3.99 days |

The payback column assumes the bought farm produces the stated city-average daily yield and retains 87.75% after repair. Actual pack draws, dilution, idle periods, withdrawal tax, and token price change this materially. All profiles retain +1% per sale ahead of schedule. Recommend Balanced (profile 1); swarm must explicitly select the requester-approved profile before purchases.

## Scenario outcomes (median of five seeds)

| Option | Scenario | Team ETH after sales | Max drawdown | W1 / W2 / W3 median ETH payback | Grower spend / mined | Net market funding / growth spend |
|---|---|---:|---:|---|---:|---:|
| Accessible | steady | 3.460 | 1.2% | 2.50d / 2.25d / 2.50d | 1.401 | 28.6% |
| Accessible | hype | 4.841 | 1.6% | 2.25d / 2.50d / 2.25d | 1.401 | 28.6% |
| Accessible | weak | 0.884 | 0.6% | 2.62d / 2.50d / 2.38d | 1.401 | 28.6% |
| Accessible | drop50 | 3.430 | 49.4% | 2.50d / 2.50d / 2.25d | 1.401 | 28.6% |
| Balanced | steady | 3.497 | 1.3% | 3.75d / 3.75d / 3.75d | 1.400 | 28.6% |
| Balanced | hype | 4.870 | 1.6% | 3.50d / 3.75d / 4.00d | 1.401 | 28.6% |
| Balanced | weak | 0.897 | 0.6% | 4.25d / 4.25d / 4.00d | 1.401 | 28.6% |
| Balanced | drop50 | 3.461 | 49.4% | 3.88d / 4.25d / 3.50d | 1.400 | 28.6% |
| Scarce | steady | 3.543 | 1.3% | 5.75d / 5.75d / 5.62d | 1.401 | 28.6% |
| Scarce | hype | 4.915 | 1.7% | 5.50d / 5.62d / 5.00d | 1.401 | 28.6% |
| Scarce | weak | 0.912 | 0.6% | 6.75d / 6.25d / 6.00d | 1.401 | 28.6% |
| Scarce | drop50 | 3.500 | 49.4% | 6.12d / 6.00d / 4.62d | 1.401 | 28.6% |

Cash-equivalent ETH payback combines modeled realized sell proceeds and remaining tokens marked at the current price, after modeled withdrawal/sell fees, against all external ETH funding including repair top-ups. It includes unsold balances and is not fully realized ETH withdrawn. The valuation uses the mature minimum 5% withdrawal tax; early claims can pay more, so first-week realizable payback may be longer. Censored means fewer than half the cohort repaid by the end of the 35-day horizon; no uncensored value is substituted. Cohorts in this table are maintenance/non-repair farms; growers deliberately keep reinvesting and are not represented as repaid. Raw JSON also contains token payback and repayment fractions. The 50% scenario is an external ETH liquidity valuation shock at day 10.25, not a claim that a single trade can halve the price with arbitrary available supply.

## Repair groups: same 25-day mining opportunity

| Hours per 10% | Policy | Mining / 100 | Paid repair | End restoration liability | Net / ideal | Extra mining / repair cost |
|---|---|---:|---:|---:|---:|---:|
| 4 | never | 53.00 | 0.00 | 0.00 | 53.0% | 0.00× |
| 4 | below80 | 99.25 | 7.67 | 0.00 | 91.6% | 6.03× |
| 4 | below60 | 93.25 | 5.33 | 2.33 | 85.6% | 5.25× |
| 6 | never | 53.00 | 0.00 | 0.00 | 53.0% | 0.00× |
| 6 | below80 | 99.25 | 11.50 | 0.00 | 87.7% | 4.02× |
| 6 | below60 | 93.25 | 8.00 | 3.50 | 81.7% | 3.50× |
| 8 | never | 53.00 | 0.00 | 0.00 | 53.0% | 0.00× |
| 8 | below80 | 99.25 | 15.33 | 0.00 | 83.9% | 3.02× |
| 8 | below60 | 93.25 | 10.67 | 4.67 | 77.9% | 2.62× |

Mining opportunity is after the unchanged electricity tariff, before maintenance and withdrawals. Mild event load is 3% damage every five days. Final health is marked back to 100% for a fair maintenance-cost comparison. No-repair output falls below 60%; default 6-hour repairs should be evaluated against the 85–90% net and ≥2× incremental return targets. Low pool yield below configured floors can violate profitability: the floor is not a subsidy or a promise.

## Enhancement Monte Carlo: a single item, at most 300 yield-days of attempts

| Cap | Reach cap | Item destroyed | Mean / median cost (item days) | Mean survivor bonus |
|---|---:|---:|---:|---:|
| +8 | 24.10% | 75.86% | 53.67 / 44.25 | 40.0% |
| +12 | 0.10% | 99.85% | 60.87 / 50.75 | 45.8% |
| +16 | 0.00% | 99.99% | 60.61 / 50.25 | 32.0% |

Unlocks are not a profitable maintenance strategy. Raising to +12 or +16 mainly adds long-tail destruction risk and spending; repeated replacement purchases are excluded from these per-item costs. Contract tests enforce +12 no earlier than day 30, +16 at least 30 days later, each announced at least 48h ahead.

## Sequential unlock sensitivity: day 30 and day 60

| End of day | Active cap | Surviving items at cap | Destroyed | Mean cumulative item-yield-day spend |
|---|---|---:|---:|---:|
| 30 | +8 | 20.62% | 64.99% | 47.14 |
| 60 | +12 | 0.06% | 98.57% | 60.42 |
| 90 | +16 | 0.00% | 99.91% | 61.06 |

This 90-day sensitivity follows one original item per player, one attempt per day and a 300 current-item-yield-day budget. +12 activates on day 30, +16 on day 60, with announcements two days earlier. Players at the cap wait for the next unlock; destroyed items are not replaced. It isolates unlock risk/cost from the separate 35-day city liquidity simulation.

## Recommended-profile steady sinks and liquidity

- packs: 65,325,447 tokens over 35 days
- repair: 16,715,298 tokens over 35 days
- rooms: 24,754,729 tokens over 35 days
- enhance: 24,754,729 tokens over 35 days
- lobby: 9,901,892 tokens over 35 days
- billboards: 4,950,946 tokens over 35 days
- locked_peak: 20,032,041 tokens
- locked_end: 14,685,709 tokens
- system_sell_tokens: 9,027,281 tokens
- System sales / mined: 4.7%
- Weekly surcharge-funded pot ETH, weeks 1–5: 0.421, 0.424, 0.428, 0.432, 0.435
- Maximum token reconciliation error across all runs: 0.000091 tokens (floating point). Solidity tests use exact integers.

## Discrete growth choices (no forced spending target)

| Enhancement attempt cadence | Total spends / mining | Median player | Net market share of spends |
|---|---:|---:|---:|
| Every 1 day(s) | 1.861× | 1.898× | 46.3% |
| Every 2 day(s) | 1.434× | 1.426× | 30.2% |
| Every 3 day(s) | 1.242× | 1.232× | 19.5% |

10,000 simulated players per cadence over 35 days. Players buy rooms on days 3/7/14 for 2/5/10 current farm-yield days; buy inventory packs on days 10/20/30 at the Balanced floor (2.5 current city-average yield days approximated by their farm yield); lobby weekly for one farm day; bid 0.25 city-average days four times. One of three equal base-hash items is enhanced from day 3, using the exact success/failure/burn table and current enhanced item-yield quotes. A burn triggers a paid replacement pack. Mining increases with the enhanced item. Maintenance uses six-hour epochs, 1% wear and 3% event damage every five days, with final restoration liability included. This discrete progression policy has no budget fixed to the target ratio: the two-day enhancement cadence falls inside 1.3–1.5×, while slower/faster choices fall outside it. Extra pack contents are held as inventory/spares; slot optimization, item rarity, replacement timing/downtime and market-impact feedback are excluded from this separate constant-rate sensitivity. The city simulation above includes price/demand feedback but uses the explicit budget policy. Lock principal is recoverable capital and excluded from spending.


The pot target of 0.3–1 ETH/week depends on taxable sell volume. At a 3% surcharge, its 50% share needs 20–66.7 ETH of sells/week before buy slippage. No funding guarantee or minimum transfer from principal is added.

## Comparison with v3.4

The committed v3.4 five-seed / 42-day-drip baseline reported steady median team 9.943 ETH and 9.9% drawdown, hype 11.096 ETH and 81.5%, weak 2.259 ETH and 17.5%; all three join-week whole-cohort medians were censored. v3.5 removes fixed ETH pack income, retains base swap fees, and sells only the 12% token split. Its maintenance tiers replace linear wear; free items no longer have the old unpaid hash penalty. The new model uses explicit token-budget demand and does not claim an apples-to-apples causal revenue uplift over the differently specified v3.4 arrival model.

## Model responsibilities and limits

Grower spending is an explicit 1.4× mined-token demand budget, allocated 35% packs / 25% rooms / 25% enhancement / 10% lobbying / 5% billboards, accrued toward discrete purchases. The net funding gap is (spend − mining) / spend; recoverable lock funding is separate. This tests required market funding, not player willingness or discrete full-farm optimization. Locks are reported separately as recoverable capital, not irreversible sinks. Token price, emission and pack rates are endogenous within each six-hour step; swap fee buybacks and 30-minute TWAP execution are approximated by small batches. Production contracts independently enforce real slippage, depth, five-minute cadence, age gates, item inventory, and entropy. Organic turnover assumes steady 4 ETH/day, weak 1, early hype 12; vary these assumptions before launch. No existing token is minted by this model or the application.
