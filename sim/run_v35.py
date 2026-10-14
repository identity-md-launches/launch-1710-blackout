#!/usr/bin/env python3
"""Offline token-economy sensitivity model. Standard library only, deterministic seeds.
Scenario assumptions are deliberately explicit; this is not an EVM or a forecast.
"""
import json,math,random,statistics
from dataclasses import dataclass
from pathlib import Path
PROFILES=[dict(name='Accessible',start=3,floor=1.5,ceiling=6,decay=.03,target=20),dict(name='Balanced',start=5,floor=2.5,ceiling=10,decay=.02,target=20),dict(name='Scarce',start=7,floor=3.5,ceiling=14,decay=.01,target=15)]
CHANCE=[.95,.9,.8,.7,.6,.5,.4,.3,.25,.22,.20,.18,.15,.12,.10,.08]
BURN=[0,0,0,0,0,.10,.25,.50,.55,.60,.65,.70,.75,.80,.85,.90]
BONUS=[0,.03,.06,.10,.14,.19,.25,.32,.40,.44,.48,.52,.56,.60,.64,.67,.70]
DAYS=[.25,.5,1,1.5,2.5,4,6,9,12,15,19,24,30,37,45,55]
SEEDS=[3501,3502,3503,3504,3505]

def tier(h):return 1 if h>=.8-1e-10 else .85 if h>=.6-1e-10 else .65 if h>=.4-1e-10 else .4 if h>=.2-1e-10 else 0

def cohort_median(values):
    """Unrepaid members remain censored, rather than disappearing from the median."""
    result=statistics.median(math.inf if value is None else value for value in values)
    return result if math.isfinite(result) else None

def repair_study():
    rows=[]
    for hours in [4,6,8]:
        for mode in ['never','below80','below60']:
            health=1.;gross=cost=never=0.;counter=1.
            for epoch in range(100):
                # Identical mild event load: 3% damage every five days, before output.
                damage=.03 if epoch%20==19 else 0
                health=max(0,health-damage);counter=max(0,counter-damage)
                gross+=tier(health);never+=tier(counter)
                health=max(0,health-.01);counter=max(0,counter-.01)
                threshold=.8 if mode=='below80' else .6 if mode=='below60' else 0
                if health<threshold:
                    cost+=(1-health)/.1*hours/6;health=1
            liability=(1-health)/.1*hours/6 if mode!='never' else 0
            rows.append(dict(hours=hours,policy=mode,mining=gross,repair=cost,restoration_liability=liability,net_fraction=(gross-cost-liability)/100,repair_return_multiple=(gross-never)/(cost+liability) if cost+liability else None))
    return rows

def enhancement_study(cap,seed,trials=10000,budget=300):
    rng=random.Random(seed);reached=burned=attempts=0;costs=[];levels=[]
    for _ in range(trials):
        lv=0;spent=0
        while lv<cap and spent+DAYS[lv]<=budget:
            spent+=DAYS[lv];attempts+=1
            if rng.random()<CHANCE[lv]:lv+=1
            else:
                if rng.random()<BURN[lv]:burned+=1;lv=-1;break
                if lv+1>=4:lv-=1
        reached+=lv==cap;costs.append(spent);levels.append(lv)
    return dict(cap=cap,trials=trials,attempts=attempts,reached_fraction=reached/trials,burned_fraction=burned/trials,mean_spend_item_yield_days=statistics.mean(costs),median_spend_item_yield_days=statistics.median(costs),mean_bonus_survivors=statistics.mean(BONUS[x] for x in levels if x>=0),budget_item_yield_days=budget)

def unlock_schedule_study(seed=3560,trials=10000):
    """One attempt/day; caps 8 on days 0-29, 12 on 30-59, 16 on 60-89.
    A destroyed item is not replaced. Each trial has a 300 current-item-yield-day budget.
    """
    rng=random.Random(seed);snapshots={29:[],59:[],89:[]}
    for _ in range(trials):
        lv=0;spent=0.;burned=False
        for day in range(90):
            cap=8 if day<30 else 12 if day<60 else 16
            if not burned and lv<cap and spent+DAYS[lv]<=300:
                spent+=DAYS[lv]
                if rng.random()<CHANCE[lv]:lv+=1
                elif rng.random()<BURN[lv]:burned=True
                elif lv+1>=4:lv-=1
            if day in snapshots:snapshots[day].append((lv,burned,spent,cap))
    return [dict(day=day+1,cap=rows[0][3],reached_fraction=sum(lv>=cap and not dead for lv,dead,spent,cap in rows)/trials,burned_fraction=sum(dead for lv,dead,spent,cap in rows)/trials,mean_spend_item_yield_days=statistics.mean(spent for lv,dead,spent,cap in rows)) for day,rows in snapshots.items()]

def growth_playbook(trials=10000):
    """Discrete quote-driven actions, without a forced spending-to-mining budget.
    Three equal base-hash items; one enhanced, same mild event/repair load as repair study.
    Farm yield includes enhancement. Extra packs are inventory/replacement purchases.
    """
    rows=[]
    for cadence in [1,2,3]:
        samples=[];totals={k:0. for k in ['mining','repair','rooms','packs','enhance','lobby','billboards']}
        for seed in range(trials):
            rng=random.Random(350000+seed);lv=0;health=1.;account={k:0. for k in totals}
            for e in range(140):
                daily=1+BONUS[lv]/3
                if e%20==19:health=max(0,health-.03)
                account['mining']+=daily*tier(health)/4
                health=max(0,health-.01)
                if health<.8:account['repair']+=daily*(1-health)*2.5;health=1
                if e%4==3:
                    day=e//4+1
                    account['rooms']+=daily*{3:2,7:5,14:10}.get(day,0)
                    if day in [10,20,30]:account['packs']+=daily*2.5
                    if day%7==0:account['lobby']+=daily
                    if day in [7,14,21,28]:account['billboards']+=.25
                    if day>=3 and (day-3)%cadence==0 and lv<8:
                        account['enhance']+=(1+BONUS[lv])/3*DAYS[lv]
                        if rng.random()<CHANCE[lv]:lv+=1
                        elif rng.random()<BURN[lv]:account['packs']+=daily*2.5;lv=0
                        elif lv+1>=4:lv-=1
            account['repair']+=(1-health)*2.5*(1+BONUS[lv]/3)
            spend=sum(v for k,v in account.items() if k!='mining')
            samples.append(spend/account['mining'])
            for k,v in account.items():totals[k]+=v
        mining=totals.pop('mining');spent=sum(totals.values())
        rows.append(dict(enhance_every_days=cadence,trials=trials,spend_mined=spent/mining,median_spend_mined=statistics.median(samples),net_market_share=max(0,spent-mining)/spent,sinks_per_100_mined={k:v/mining*100 for k,v in totals.items()}))
    return rows

@dataclass
class Farm:
    joined:int;strategy:str;hash:float;health:float=1.;wallet:float=0.;mined:float=0.;repair:float=0.;growth:float=0.;market_bought:float=0.;initial:float=0.;initial_eth:float=0.;cash_eth:float=0.;funding_eth:float=0.;payback:float|None=None;token_payback:float|None=None;locked:float=0.;unlock:int=0;lock_cost:float=0

class Model:
    def __init__(self,profile,scenario,seed):
        self.p=profile;self.scenario=scenario;self.rng=random.Random(seed);self.farms=[]
        self.amm=700e6;self.amm_eth=70/9;self.pool=200e6;self.swarm=100e6;self.team_tokens=0.;self.heart_tokens=0.;self.pot=0.;self.team_eth=0.;self.heartbeat=0.;self.system_sells=0.;self.sold=0;self.avg=3000.;self.rate=.000001;self.peak=self.price();self.dd=0;self.sinks={k:0. for k in ['packs','repair','rooms','enhance','lobby','billboards']};self.pots=[0.]*5;self.rows=[];self.error=0.;self.shock_effect=1.;self.lock_peak=0.;self.nonplayer_wallet=0.;self.initial_amm_eth=self.amm_eth
    def price(self):return self.amm_eth/self.amm
    def days(self,e):
        ahead=self.sold-e*6*self.p['target'];exponent=math.log1p(.01)*ahead if ahead>=0 else math.log1p(-self.p['decay'])*(-ahead/self.p['target'])
        return min(self.p['ceiling'],max(self.p['floor'],self.p['start']*math.exp(max(-10,min(10,exponent)))))
    def buy(self,amount):
        if amount<=0:return 0
        if amount>=self.amm*.9:raise ArithmeticError('Unfillable model buy')
        net=self.amm_eth*amount/(self.amm-amount);gross=net/.9775
        self.amm-=amount;self.amm_eth+=net;self.team_eth+=gross*.01
        # Other 1% project base fee buys back tokens immediately, approximated without impact.
        reward=gross*.01/self.price();self.amm-=reward;self.pool+=reward;self.amm_eth+=gross*.01
        return gross
    def sell(self,amount,system=False):
        if amount<=0:return 0
        gross=self.amm_eth*amount/(self.amm+amount);self.amm+=amount;self.amm_eth-=gross
        self.team_eth+=gross*.01
        reward=gross*.01/self.price();self.amm-=reward;self.pool+=reward;self.amm_eth+=gross*.01
        surcharge=0 if system else .03
        if surcharge:
            budget=gross*surcharge*.5;tokens=budget/self.price();self.amm-=tokens;self.pot+=tokens;self.amm_eth+=budget;self.pots[self.epoch//28]+=budget
            # Remaining sell surcharge: 10% team, 2% heartbeat, 38% mining.
            self.team_eth+=gross*surcharge*.1;self.heartbeat=min(1,self.heartbeat+gross*surcharge*.02)
            reward=gross*surcharge*.38/self.price();self.amm-=reward;self.pool+=reward;self.amm_eth+=gross*surcharge*.38
        return gross*(.9775-surcharge)
    def spend(self,f,amount,kind,initial=False):
        short=max(0,amount-f.wallet)
        if short:
            eth=self.buy(short);f.wallet+=short;f.market_bought+=short;f.funding_eth+=eth
            if initial:f.initial_eth+=eth
        f.wallet-=amount;self.sinks[kind]+=amount
        if kind in ('packs','lobby'):
            self.pool+=amount*.88;self.team_tokens+=amount*.1;self.heart_tokens+=amount*.02
        else:self.pool+=amount
        if kind=='repair':f.repair+=amount
        elif not initial:f.growth+=amount
    def settle_system(self):
        # 72 five-minute opportunities per epoch. <=0.1% virtual token depth and <=0.1 ETH each.
        for _ in range(72):
            if self.heartbeat>=1:self.pool+=self.heart_tokens;self.heart_tokens=0
            total=self.team_tokens+self.heart_tokens
            if total<1:break
            amount=min(total,self.amm*.001,.1/self.price());h=amount*self.heart_tokens/total
            self.team_tokens-=amount-h;self.heart_tokens-=h
            eth=self.sell(amount,True);self.system_sells+=amount
            self.team_eth+=eth*(amount-h)/amount;credit=eth*h/amount;accepted=min(credit,1-self.heartbeat);self.heartbeat+=accepted
            if credit>accepted:
                tokens=(credit-accepted)/self.price();self.amm-=tokens;self.pool+=tokens;self.amm_eth+=credit-accepted
    def run(self):
        for e in range(140):
            self.epoch=e
            arrivals=(15 if self.scenario in ['steady','drop50'] else (45 if e<28 else 4) if self.scenario=='hype' else 3)
            arrivals=round(arrivals*(5/self.p['start'])**.5)
            for _ in range(arrivals):
                strategy=self.rng.choices(['maintain','grow','never'],[.5,.35,.15])[0]
                raw=sum(self.rng.choices([10000,28000,80000,250000],[.7,.22,.067,.013])[0]*(1 if self.rng.random()<.43 else .6) for _ in range(3))
                f=Farm(e,strategy,raw);cost=self.days(e)*self.avg;f.initial=cost;self.spend(f,cost,'packs',True);self.sold+=1;self.farms.append(f)
            locked_principal=200e6*max(0,1-(e+1)/168)
            available=max(0,self.pool-locked_principal)
            budget=available*.035/4
            denominator=sum(f.hash*(1.1 if f.locked else 1) for f in self.farms)
            self.rate=max(.000001,budget*.85/denominator) if denominator else .000001
            yields=[]
            for f in self.farms:
                if f.locked and e>=f.unlock:f.wallet+=f.locked;f.locked=0
                health_damage=.03 if (e-f.joined)%20==19 else 0
                f.health=max(0,f.health-health_damage)
                output=tier(f.health);weight=f.hash*(1.1 if f.locked else 1)
                mining=budget*weight/denominator*output*.85
                self.pool-=mining;f.wallet+=mining;f.mined+=mining;yields.append(mining)
                f.health=max(0,f.health-.01)
                if f.strategy!='never' and f.health<.8:
                    cost=(1-f.health)/.1*6/24*max(.04,f.hash*self.rate*4)
                    self.spend(f,cost,'repair');f.health=1
                # Explicit grower demand policy: 1.4x mined in consumptive growth+maintenance,
                # split among planned packs, rooms, enhancement attempts, lobby and billboards.
                # It is a willingness-to-spend assumption, never a promised emergent equilibrium.
                if f.strategy=='grow' and e>f.joined:
                    target=max(0,f.mined*1.4-f.growth-f.repair)
                    for kind,share in [('packs',.35),('rooms',.25),('enhance',.25),('lobby',.1),('billboards',.05)]:self.spend(f,target*share,kind)
                    # Economic aggregate accrues these budgets toward discrete item/room purchases.
                    f.hash*=1.001
                    if e==f.joined+12:
                        amount=max(3000,mining*4)*10;short=max(0,amount-f.wallet)
                        if short:self.buy(short);f.wallet+=short;f.market_bought+=short
                        f.wallet-=amount;f.locked=amount;f.unlock=e+56;f.lock_cost+=amount
                if f.strategy!='grow':
                    net=f.mined-f.repair
                    if f.token_payback is None and net>=f.initial:f.token_payback=(e-f.joined+1)/4
                # Sell 25% of the available balance daily; growers reinvest instead.
                if e%4==3 and f.strategy!='grow':
                    sell=f.wallet*.25;f.wallet-=sell;f.cash_eth+=self.sell(sell)*.95
                if f.strategy!='grow' and f.payback is None and f.cash_eth+f.wallet*self.price()*.95*.9475>=f.funding_eth:
                    f.payback=(e-f.joined+1)/4
            self.avg=max(3000,sum(yields)*4/len(yields))
            # Exogenous two-sided organic turnover supports fee/pot sensitivity; volume is not guaranteed.
            organic_eth=(1 if self.scenario=='weak' else 12 if self.scenario=='hype' and e<28 else 4)/4
            remaining=organic_eth
            while remaining>1e-8:
                chunk=min(remaining,self.amm_eth*.001)
                quantity=chunk/self.price()
                self.buy(quantity);self.nonplayer_wallet+=quantity;self.nonplayer_wallet-=quantity;self.sell(quantity)
                remaining-=chunk
            if self.scenario=='drop50' and e==40:
                # A mark-to-market stress, implemented as external ETH liquidity repricing. Token
                # balances remain conserved; this is not claimed to be a feasible atomic AMM trade.
                self.amm_eth*=.5;self.shock_effect=.5
            self.settle_system();self.heartbeat=max(0,self.heartbeat-.001)
            locked=sum(f.locked for f in self.farms);self.lock_peak=max(self.lock_peak,locked)
            total=self.amm+self.pool+self.swarm+self.team_tokens+self.heart_tokens+self.pot+sum(f.wallet+f.locked for f in self.farms)+self.nonplayer_wallet
            self.error=max(self.error,abs(total-1e9));assert self.error<.05,(e,total)
            price=self.price();self.peak=max(self.peak,price);self.dd=max(self.dd,1-price/self.peak)
            if e%4==3:self.rows.append(dict(day=(e+1)/4,price=price,pool=self.pool,farms=len(self.farms),locked=locked,team_eth=self.team_eth,pot_value=self.pot*price))
        cohorts=[]
        for week in [0,1,2]:
            fs=[f for f in self.farms if f.joined//28==week and f.strategy!='grow']
            paid=[f.payback for f in fs if f.payback is not None]
            cohorts.append(dict(week=week+1,farms=len(fs),repaid_fraction=len(paid)/len(fs),median_eth_payback=cohort_median([f.payback for f in fs]),conditional_eth_payback=statistics.median(paid) if paid else None,median_token_payback=cohort_median([f.token_payback for f in fs])))
        growers=[f for f in self.farms if f.strategy=='grow'];mined=sum(f.mined for f in growers);growth=sum(f.growth+f.repair for f in growers)
        purchased=sum(max(0,f.market_bought-f.initial-f.lock_cost) for f in growers)
        maintain=[f for f in self.farms if f.strategy=='maintain' and f.joined<40]
        return dict(profile=self.p['name'],scenario=self.scenario,cohorts=cohorts,team_eth=self.team_eth,drawdown=self.dd,grower_spend_mined=growth/mined,grower_market_share=max(0,growth-mined)/growth,maintain_mining_profit=sum(f.mined-f.repair for f in maintain),maintain_repair_share=sum(f.repair for f in maintain)/sum(f.mined for f in maintain),sinks=self.sinks,locked_peak=self.lock_peak,locked_end=sum(f.locked for f in self.farms),weekly_pot_eth=self.pots,system_sell_tokens=self.system_sells,system_sell_share_of_mined=self.system_sells/sum(f.mined for f in self.farms),max_conservation_error=self.error,rows=self.rows)

def median(rs,key):return statistics.median(r[key] for r in rs)
def report(results,repair,enhance,unlocks,playbooks):
    out=['# BLACKOUT v3.5: offline economic sensitivity study','', 'Five deterministic seeds, 35 days, six-hour epochs, 1B conserved tokens, 20% endowment / 42-day drip. No network, swaps, or deployments. Results are conditional model outputs, not return guarantees.','', '## Pack options (token yield-days, never ETH-pegged)','', '| Choice | Start / floor / ceiling | Decay per hour behind schedule | Target packs/hour | Constant-rate maintenance payback at start / floor |','|---|---|---|---|---|']
    for p in PROFILES:out.append(f"| {p['name']} | {p['start']} / {p['floor']} / {p['ceiling']} days | {p['decay']:.0%} | {p['target']} | {p['start']/.8775:.2f} / {p['floor']/.8775:.2f} days |")
    out+=['','The payback column assumes the bought farm produces the stated city-average daily yield and retains 87.75% after repair. Actual pack draws, dilution, idle periods, withdrawal tax, and token price change this materially. All profiles retain +1% per sale ahead of schedule. Recommend Balanced (profile 1); swarm must explicitly select the requester-approved profile before purchases.','', '## Scenario outcomes (median of five seeds)','', '| Option | Scenario | Team ETH after sales | Max drawdown | W1 / W2 / W3 median ETH payback | Grower spend / mined | Net market funding / growth spend |','|---|---|---:|---:|---|---:|---:|']
    for p in PROFILES:
        for scenario in ['steady','hype','weak','drop50']:
            rs=[r for r in results if r['profile']==p['name'] and r['scenario']==scenario]
            cohort=[]
            for w in range(3):
                values=[r['cohorts'][w]['median_eth_payback'] for r in rs]
                cohort.append('censored' if any(v is None for v in values) else f'{statistics.median(values):.2f}d')
            out.append(f"| {p['name']} | {scenario} | {median(rs,'team_eth'):.3f} | {median(rs,'drawdown'):.1%} | {' / '.join(cohort)} | {median(rs,'grower_spend_mined'):.3f} | {median(rs,'grower_market_share'):.1%} |")
    out+=['','Cash-equivalent ETH payback combines modeled realized sell proceeds and remaining tokens marked at the current price, after modeled withdrawal/sell fees, against all external ETH funding including repair top-ups. It includes unsold balances and is not fully realized ETH withdrawn. The valuation uses the mature minimum 5% withdrawal tax; early claims can pay more, so first-week realizable payback may be longer. Censored means fewer than half the cohort repaid by the end of the 35-day horizon; no uncensored value is substituted. Cohorts in this table are maintenance/non-repair farms; growers deliberately keep reinvesting and are not represented as repaid. Raw JSON also contains token payback and repayment fractions. The 50% scenario is an external ETH liquidity valuation shock at day 10.25, not a claim that a single trade can halve the price with arbitrary available supply.','', '## Repair groups: same 25-day mining opportunity','', '| Hours per 10% | Policy | Mining / 100 | Paid repair | End restoration liability | Net / ideal | Extra mining / repair cost |','|---|---|---:|---:|---:|---:|---:|']
    for r in repair:out.append(f"| {r['hours']} | {r['policy']} | {r['mining']:.2f} | {r['repair']:.2f} | {r['restoration_liability']:.2f} | {r['net_fraction']:.1%} | {r['repair_return_multiple'] or 0:.2f}× |")
    out+=['','Mining opportunity is after the unchanged electricity tariff, before maintenance and withdrawals. Mild event load is 3% damage every five days. Final health is marked back to 100% for a fair maintenance-cost comparison. No-repair output falls below 60%; default 6-hour repairs should be evaluated against the 85–90% net and ≥2× incremental return targets. Low pool yield below configured floors can violate profitability: the floor is not a subsidy or a promise.','', '## Enhancement Monte Carlo: a single item, at most 300 yield-days of attempts','', '| Cap | Reach cap | Item destroyed | Mean / median cost (item days) | Mean survivor bonus |','|---|---:|---:|---:|---:|']
    for r in enhance:out.append(f"| +{r['cap']} | {r['reached_fraction']:.2%} | {r['burned_fraction']:.2%} | {r['mean_spend_item_yield_days']:.2f} / {r['median_spend_item_yield_days']:.2f} | {r['mean_bonus_survivors']:.1%} |")
    out+=['','Unlocks are not a profitable maintenance strategy. Raising to +12 or +16 mainly adds long-tail destruction risk and spending; repeated replacement purchases are excluded from these per-item costs. Contract tests enforce +12 no earlier than day 30, +16 at least 30 days later, each announced at least 48h ahead.','', '## Recommended-profile steady sinks and liquidity','']
    out[-2:] = ['## Sequential unlock sensitivity: day 30 and day 60', '', '| End of day | Active cap | Surviving items at cap | Destroyed | Mean cumulative item-yield-day spend |', '|---|---|---:|---:|---:|']
    for r in unlocks:out.append(f"| {r['day']} | +{r['cap']} | {r['reached_fraction']:.2%} | {r['burned_fraction']:.2%} | {r['mean_spend_item_yield_days']:.2f} |")
    out+=['', 'This 90-day sensitivity follows one original item per player, one attempt per day and a 300 current-item-yield-day budget. +12 activates on day 30, +16 on day 60, with announcements two days earlier. Players at the cap wait for the next unlock; destroyed items are not replaced. It isolates unlock risk/cost from the separate 35-day city liquidity simulation.', '', '## Recommended-profile steady sinks and liquidity', '']
    rs=[r for r in results if r['profile']=='Balanced' and r['scenario']=='steady']
    for key in ['packs','repair','rooms','enhance','lobby','billboards']:out.append(f"- {key}: {statistics.median(r['sinks'][key] for r in rs):,.0f} tokens over 35 days")
    for key in ['locked_peak','locked_end','system_sell_tokens']:out.append(f"- {key}: {median(rs,key):,.0f} tokens")
    out.append(f"- System sales / mined: {median(rs,'system_sell_share_of_mined'):.1%}")
    out.append('- Weekly surcharge-funded pot ETH, weeks 1–5: '+', '.join(f"{statistics.median(r['weekly_pot_eth'][w] for r in rs):.3f}" for w in range(5)))
    out.append(f"- Maximum token reconciliation error across all runs: {max(r['max_conservation_error'] for r in results):.6f} tokens (floating point). Solidity tests use exact integers.")
    out+=['', '## Discrete growth choices (no forced spending target)', '', '| Enhancement attempt cadence | Total spends / mining | Median player | Net market share of spends |', '|---|---:|---:|---:|']
    for r in playbooks:out.append(f"| Every {r['enhance_every_days']} day(s) | {r['spend_mined']:.3f}× | {r['median_spend_mined']:.3f}× | {r['net_market_share']:.1%} |")
    out+=['', '10,000 simulated players per cadence over 35 days. Players buy rooms on days 3/7/14 for 2/5/10 current farm-yield days; buy inventory packs on days 10/20/30 at the Balanced floor (2.5 current city-average yield days approximated by their farm yield); lobby weekly for one farm day; bid 0.25 city-average days four times. One of three equal base-hash items is enhanced from day 3, using the exact success/failure/burn table and current enhanced item-yield quotes. A burn triggers a paid replacement pack. Mining increases with the enhanced item. Maintenance uses six-hour epochs, 1% wear and 3% event damage every five days, with final restoration liability included. This discrete progression policy has no budget fixed to the target ratio: the two-day enhancement cadence falls inside 1.3–1.5×, while slower/faster choices fall outside it. Extra pack contents are held as inventory/spares; slot optimization, item rarity, replacement timing/downtime and market-impact feedback are excluded from this separate constant-rate sensitivity. The city simulation above includes price/demand feedback but uses the explicit budget policy. Lock principal is recoverable capital and excluded from spending.', '']
    out+=['','The pot target of 0.3–1 ETH/week depends on taxable sell volume. At a 3% surcharge, its 50% share needs 20–66.7 ETH of sells/week before buy slippage. No funding guarantee or minimum transfer from principal is added.','', '## Comparison with v3.4','', 'The committed v3.4 five-seed / 42-day-drip baseline reported steady median team 9.943 ETH and 9.9% drawdown, hype 11.096 ETH and 81.5%, weak 2.259 ETH and 17.5%; all three join-week whole-cohort medians were censored. v3.5 removes fixed ETH pack income, retains base swap fees, and sells only the 12% token split. Its maintenance tiers replace linear wear; free items no longer have the old unpaid hash penalty. The new model uses explicit token-budget demand and does not claim an apples-to-apples causal revenue uplift over the differently specified v3.4 arrival model.','', '## Model responsibilities and limits','', 'Grower spending is an explicit 1.4× mined-token demand budget, allocated 35% packs / 25% rooms / 25% enhancement / 10% lobbying / 5% billboards, accrued toward discrete purchases. The net funding gap is (spend − mining) / spend; recoverable lock funding is separate. This tests required market funding, not player willingness or discrete full-farm optimization. Locks are reported separately as recoverable capital, not irreversible sinks. Token price, emission and pack rates are endogenous within each six-hour step; swap fee buybacks and 30-minute TWAP execution are approximated by small batches. Production contracts independently enforce real slippage, depth, five-minute cadence, age gates, item inventory, and entropy. Organic turnover assumes steady 4 ETH/day, weak 1, early hype 12; vary these assumptions before launch. No existing token is minted by this model or the application.']
    return '\n'.join(out)+'\n'

if __name__=='__main__':
    results=[Model(p,s,seed).run() for p in PROFILES for s in ['steady','hype','weak','drop50'] for seed in SEEDS]
    playbooks=growth_playbook();unlocks=unlock_schedule_study();repair=repair_study();enhance=[enhancement_study(cap,3500+cap) for cap in [8,12,16]]
    out=Path('artifacts/v35');out.mkdir(parents=True,exist_ok=True)
    (out/'simulation.json').write_text(json.dumps(dict(profiles=PROFILES,seeds=SEEDS,results=results,repair=repair,enhancement=enhance,unlock_schedule=unlocks,growth_playbooks=playbooks),indent=2)+'\n')
    (out/'simulation.md').write_text(report(results,repair,enhance,unlocks,playbooks));print(report(results,repair,enhance,unlocks,playbooks))
