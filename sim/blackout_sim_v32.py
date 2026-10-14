#!/usr/bin/env python3
"""BLACKOUT v3.2: deterministic 35-day, six-hour economic scenario model.
Stdlib only. No RPC, credentials, issuance, or transactions. Not an EVM emulator.
Every epoch reconciles the existing billion tokens across all holders.
"""
from __future__ import annotations
import argparse, json, math, random, statistics, unittest, hashlib
from dataclasses import dataclass, field
from pathlib import Path

SUPPLY=1_000_000_000.0
TYPE_WEIGHTS=(16,15,12,9,7,7,9,6,6,5,4,4)
HASH=(10,28,80,250,800)
THRESHOLDS=(0,100,400,600,800,1200,1600,2000,2400,2800)
FALLBACK=('green','cheap','calm','outage','calm','green','surge','calm','fire','calm','cheap','theft','calm','audit','calm','green','calm','outage','calm','cheap')

def level(xp): return sum(xp>=x for x in THRESHOLDS)
def tax(age): return max(.05,.20-.15*age/7)
def vrgda(sold,hours,target=20,step=.01,decay=.02):
    ahead=sold-hours*target
    exponent=math.log1p(step)*ahead if ahead>=0 else math.log1p(-decay)*(-ahead/target)
    return min(.03,max(.006,.010*math.exp(max(-10,min(10,exponent)))))

def controller(emission,tariff,target,positive,runway,payback,loss,pace_policy="reduce"):
    """Once per 24h, each numeric adjustment is <=10%, clamped to on-chain bounds."""
    old_target=target
    if runway<14: emission=max(.02,emission*.9);tariff=min(.30,tariff*1.1);target=max(10,math.ceil(target*.9))
    elif payback>10:
        emission=min(.06,emission*1.1);tariff=max(.10,tariff*.9);target=max(10,target-target//10)
    if runway>=14 and pace_policy=="hold": target=old_target
    if runway>=14 and pace_policy=="adaptive" and payback>30: target=min(40,old_target+old_target//10)
    if loss>.08: positive=min(.50,positive*1.1)
    return emission,tariff,target,positive

@dataclass
class Item:
    kind:int; rarity:int; health:float=1.;shadow:float=1.;destroyed:bool=False
    @property
    def raw(self):return HASH[self.rarity]*(1 if self.kind<3 else .6)

@dataclass
class Farmer:
    joined:int;district:int;paid:bool;cost:float=0.;xp:int=0;cash:float=0.;held:float=0.;alive:bool=True
    items:list=field(default_factory=list);yields:list=field(default_factory=list);payback:float|None=None
    allocation:float=0.;
    wallet:float=0.;gross_week:float=0.;spend_week:float=0.;tickets:int=0;theft_until:int=0;overclock:float=0.
    def equip(self,e,shadow=False):
        lev=level(self.xp);n=4 if lev>=10 else 3 if lev>=7 else 2 if e-self.joined>=12 else 1
        rooms=[[] for _ in range(n)]
        for item in sorted(self.items,key=lambda x:x.raw,reverse=True):
            if (not shadow and item.destroyed) or (item.shadow if shadow else item.health)<=0 or item.rarity==2 and lev<3 or item.rarity==3 and lev<5 or item.rarity==4 and lev<10:continue
            for room in rooms:
                if len(room)<6 and item.kind not in {x.kind for x in room}:room.append(item);break
        return rooms

def draw(rng,lev,starter=False,minimum=0):
    k=rng.choices(range(12),TYPE_WEIGHTS)[0];r=rng.randrange(10000)
    rarity=(1 if r<9200 else 2) if starter else (0 if r<7000 else 1 if r<9200 else 2 if r<9870 else 3 if r<9970 else 4 if lev>=10 else 0)
    return Item(k,max(minimum,rarity))

def stats(room,paid,clock=0.,theft=False,shadow=False):
    room=[item for item in room if shadow or not item.destroyed]
    kinds={i.kind for i in room};active=[i for i in room if not(theft and i.kind==8 and not {8,10}<=kinds)]
    tags={0 if k<3 else 1 if k<6 else 2 if k<8 else 3 if k==8 else 4 for k in {i.kind for i in active}}
    rarity=[sum(i.rarity==r for i in active) for r in range(5)]
    bonus=(.2 if {0,1,2}<=kinds else .1 if {0,1}<=kinds else 0)+(.15 if len(tags)==5 else 0)+(.05 if {6,10}<=kinds else 0)
    bonus+=max((v for r,v in enumerate((0,.05,.10,.20,.30)) if rarity[r]>=3),default=0)
    multiplier=(1+min(.4,bonus))*(1+clock*.1)*(1 if paid else .5)
    raw=sum(i.raw for i in active)*multiplier;effective=sum(i.raw*(i.shadow if shadow else i.health) for i in active)*multiplier
    saving=(.15 if {3,7}<=kinds else 0)+(.20 if {4,5}<=kinds else 0)
    return raw,effective,effective*(1-saving),kinds

def lottery_item(rng,lev):
    # Season uses seed%100 BOTH for kind and rarity, so these draws are correlated.
    point=rng.randrange(100)
    cumulative=0
    for kind,weight in enumerate(TYPE_WEIGHTS):
        cumulative+=weight
        if point<cumulative:return Item(kind,2 if point<90 else 3)
    raise AssertionError('item weights must sum to100')

def reservation_remainder(mining, redis, ghost_fraction, active_spent):
    """Continuous equivalent of lazy attribution: no ghost or final dust funds scrap."""
    envelope = 1.155 * mining + redis
    ghost = envelope * ghost_fraction
    dust = max(0., 1.17 * mining - .01 * mining - 1.155 * mining)
    retained = ghost + (dust if ghost_fraction > 0 else 0.)
    scrap = min(mining / 6, max(0., envelope - ghost - active_spent))
    return retained, scrap

class Model:
    def __init__(self,scenario,path,seed=20261011,liquidity=10.,bootstrap=0.,pace_policy="reduce",endowment=0.,drip_days=42,single_sided=False,heartbeat_bps=200,claim_lock_days=2,imd_eth=.003451,autonomous=False,heartbeat_cap=1.,pack_scale=1.,emission_start=.035,tariff_start=.15,sale_fraction=.65,gas_price=20_000_000,team_share=.13):
        self.team_share=team_share
        self.pack_scale=pack_scale;self.sale_fraction=sale_fraction;self.gas_price=gas_price
        self.lazy_reserved=0.;self.delayed_prizes=[];self.delayed_prize_tokens=0.;self.user_gas=0.
        self.v31=single_sided;self.autonomous=autonomous
        self.endowment_fraction=endowment;self.drip_days=drip_days;self.endowment_total=SUPPLY*endowment
        self.locked=self.endowment_total;self.released=0.;self.claim_lock_days=claim_lock_days
        self.heartbeat_bps=heartbeat_bps;self.heartbeat_cap=heartbeat_cap;self.heartbeat_in=0.;self.routed_eth=0.;self.bounty_due=0.;self.bounty_shortfall=0.;self.first_shortfall=None
        self.work_due={};self.work_paid={};self.entropy_count=0;self.swarm_backlog=0.;self.last_unsold=0.
        self.run_cost=.5*imd_eth;self.run_imd=0.;self.run_eth=0.;self.heartbeat_flows=[]
        self.seed=seed
        self.pace_policy=pace_policy
        self.scenario,self.path=scenario,path;self.rng=random.Random(seed);self.x=liquidity*(.9-endowment)/.9;self.y=SUPPLY*(.9-endowment);self.floor_x=self.x;self.initial_y=self.y;self.swarm=100_000_000.
        self.pool=self.endowment_total if drip_days==0 else 0.;self.locked=0. if drip_days==0 else self.locked;self.redis=0.;self.queue=[];self.farmers=[];self.sold=0;self.reward_eth=0.;self.team=0.;self.heartbeat=0.;self.bounties=0.;self.network=0.;self.external_tokens=0.
        self.emission=emission_start;self.tariff=tariff_start;self.target=20;self.positive=.25;self.rows=[];self.events=[];self.last_outage=[-100]*8;self.loss_total=0.;self.baseline_total=0.
        self.week_prize=0.;self.week_spend=[0.]*8;self.pack_eth=0.;self.peak=0;self.stall=None;self.tickets={};self.max_error=0.;self.lobbies=[0.]*8
        self.sell_fraction={'steady':.35,'hype':.50,'weak':.65}[scenario];self.holders=900;self.scrap_reserved=0.;self.bootstrap=bootstrap;self.pool+=self.buy(bootstrap)
    @property
    def price(self):return self.x/self.y
    def route(self,eth,base=False):
        if base:self.team+=eth*.5;self.reward_eth+=eth*.5;return
        self.routed_eth+=eth
        hb=min(max(0,self.heartbeat_cap-self.heartbeat),eth*self.heartbeat_bps/10000);self.heartbeat+=hb;self.heartbeat_in+=hb;self.team+=eth*self.team_share;self.reward_eth+=eth*(1-self.team_share)-hb
    def buy(self,eth):
        project=.02 if self.path=='custom' else .01;self.route(eth*project,True);self.network+=eth*.0025;net=eth*(1-project-.0025)
        out=self.y*net/(self.x+net);self.x+=net;self.y-=out;return out
    def sell(self,tokens,extra):
        self.last_unsold=0.
        if self.v31:
            fill=min(tokens,max(0.,self.initial_y-self.y))
            self.last_unsold=tokens-fill;tokens=fill
        gross=self.x*tokens/(self.y+tokens);self.y+=tokens;self.x-=gross;project=.02 if self.path=='custom' else .01
        self.route(gross*project,True);self.route(gross*extra);self.network+=gross*.0025;return gross*(1-project-.0025-extra)
    def demand(self,day):
        if self.scenario=='steady':return 150 if day<3 else 80
        if self.scenario=='hype':return 600*math.exp(-day/5)+25
        return 40*math.exp(-day/15)+5
    def pack(self,f,e,starter=False,free=False,token=False):
        if sum(not x.destroyed for x in f.items)>36:return False # twenty-four equipped plus fifteen inventory slots, with room-dependent opening below
        inv=sum(not x.destroyed for x in f.items)-sum(map(len,f.equip(e)))
        if inv+3>15:return False
        price=vrgda(self.sold,e*6,self.target)*self.pack_scale
        if not(starter or free):
            if token:
                cost=price/self.price*.9/1.05
                if f.held<cost:return False
                f.held-=cost;self.pool+=cost;f.spend_week+=cost*self.price
            else:f.cost+=price;self.pack_eth+=price;self.route(price);self.week_spend[f.district]+=price
            self.sold+=1;f.paid=True;f.xp+=25
        for i in range(3):f.items.append(draw(self.rng,level(f.xp),starter,1 if free and i==0 else 0))
        self.entropy_count+=1
        return True
    def event(self,e):
        kind=FALLBACK[e%20]
        # Swarm regulator may add positives, never remove rolling quota guarantees.
        if self.rng.random()<self.positive:kind=self.rng.choice(('green','cheap'))
        recent=self.events[-19:];pos=sum(x in ('green','cheap') for x in recent)
        if (e>=19 and pos<4) or (e<19 and pos+19-e<4):kind=self.rng.choice(('green','cheap'))
        if kind not in ('green','cheap','calm') and recent.count(kind)>=4:kind='calm'
        weights=[max(.4,1-.5*l/(1+l)) for l in self.lobbies]
        if kind=='green':weights=[2-w for w in weights]
        if kind=='outage':weights=[w if e-self.last_outage[i]>=8 else 0 for i,w in enumerate(weights)]
        d=self.rng.choices(range(8),weights)[0] if sum(weights)>0 else 0
        if not sum(weights):kind='calm'
        if kind=='outage':self.last_outage[d]=e
        self.events.append(kind);return kind,d
    def conservation(self):
        total=self.y+self.swarm+self.pool+self.locked+self.redis+self.week_prize+self.scrap_reserved+self.lazy_reserved+self.delayed_prize_tokens+self.external_tokens+sum(f.held+f.wallet for f in self.farmers)+sum(q[2] for q in self.queue)
        error=abs(total-SUPPLY);self.max_error=max(self.max_error,error);assert error<.02,(self.scenario,self.path,total)
    def work(self,kind,units,rate,e,gas=None):
        due=units*rate
        if gas is not None:
            calls=math.ceil(units/.5) if kind=="buy" else units if kind in ("pack_entropy","plan_entropy","season_finalize") else math.ceil(units/(64 if kind=="season_score" else 4))
            due=min(due,(gas+80000*calls)*min(self.gas_price,50_000_000)/1e18*1.25)
        paid=min(due,self.heartbeat);self.heartbeat-=paid;self.bounties+=paid
        self.bounty_due+=due;self.bounty_shortfall+=due-paid
        self.work_due[kind]=self.work_due.get(kind,0.)+due;self.work_paid[kind]=self.work_paid.get(kind,0.)+paid
        if due-paid>1e-10 and self.first_shortfall is None:self.first_shortfall=e/4
    def run(self):
        for e in range(140):
            day=e/4
            # Prize eligibility is frozen after the week is fully settled; payout follows the 7-day grace.
            for deadline, best, winning, eligible, winners, amount in list(self.delayed_prizes):
                if e < deadline: continue
                self.delayed_prize_tokens-=amount
                if best is not None:self.farmers[best].held+=amount
                else:self.pool+=amount
                self.work('season_finalize',bool(eligible),.00004,e,650000)
                for idx in eligible:
                    f=self.farmers[idx]
                    if f.district==winning:self.pack(f,e,free=True)
                for idx,item in winners:self.farmers[idx].items.append(item)
                self.delayed_prizes.remove((deadline,best,winning,eligible,winners,amount))
            if self.drip_days>0:
                vested=self.endowment_total*min(1,(e+1)/4/self.drip_days)
                release=vested-self.released;self.released=vested;self.locked-=release;self.pool+=release
            begin_price=self.price;pack_before=self.sold;redis_for_epoch=self.redis;self.redis=0.
            # Observed payback influences joining, but does not assume success.
            recent=[f for f in self.farmers if f.paid and f.alive and len(f.yields)>=4]
            forecast=statistics.median([f.cost/max(sum(f.yields[-4:]),1e-12) for f in recent]) if recent else 10.
            response=min(1,math.sqrt(21/max(1,forecast)))
            expected=self.demand(day)/4*response;n=int(expected)+(self.rng.random()<expected%1)
            for _ in range(n):
                f=Farmer(e,self.rng.randrange(8),True);self.farmers.append(f)
                desired=max(1,round(3*(.01/vrgda(self.sold,e*6,self.target))**.7))
                for _ in range(desired):self.pack(f,e)
            # Exactly 900 snapshot holders exercise one entitlement during the specified window.
            if 8<=e<64:
                n=(self.holders*(e-7)//56)-(self.holders*(e-8)//56)
                for _ in range(n):
                    f=Farmer(e,self.rng.randrange(8),False);self.farmers.append(f);self.pack(f,e,starter=True)
            # Holder sales are independent of gameplay, spread over the first fourteen days.
            holder_tokens=100_000_000*self.sell_fraction/56 if e<56 else 0.
            if self.v31:
                newly_due=100_000_000*self.sell_fraction/(56-self.claim_lock_days*4) if self.claim_lock_days*4<=e<56 else 0.
                self.swarm_backlog+=newly_due;holder_tokens=self.swarm_backlog
            due=[q for q in self.queue if q[0]<=e];self.queue=[q for q in self.queue if q[0]>e]
            user_tokens=sum(q[2] for q in due);sell_pressure=(holder_tokens+user_tokens)*self.price
            base=.02 if self.path=='custom' else .01
            extra=0 if self.path=='standard' else min(.15-.0025-base,.05*sell_pressure/(sell_pressure+self.reward_eth+.5)+.04*sell_pressure/(sell_pressure+self.reward_eth+2))
            if holder_tokens:
                self.sell(holder_tokens,extra);filled=holder_tokens-self.last_unsold;self.swarm-=filled
                if self.v31:self.swarm_backlog=self.last_unsold
            for _,idx,amount,age in due:
                withheld=amount*tax(age);self.redis+=withheld
                if self.v31:self.farmers[idx].wallet+=amount-withheld
                else:self.farmers[idx].cash+=self.sell(amount-withheld,extra)
                f=self.farmers[idx]
                if f.cash>=f.cost and f.paid and f.payback is None:f.payback=(e-f.joined)/4
            if self.v31:
                for f in self.farmers:
                    if f.wallet:
                        f.cash+=self.sell(f.wallet,extra);f.wallet=self.last_unsold
                        if f.cash>=f.cost and f.paid and f.payback is None:f.payback=(e-f.joined)/4
            # External round-trip volume is inventory conserving, with its fees included.
            trade=.5*max(0,self.pack_eth-sum(r['pack_eth'] for r in self.rows))
            if trade:tok=self.buy(trade);self.sell(tok,extra)
            buy_eth=self.reward_eth;self.reward_eth=0.;self.pool+=self.buy(buy_eth)
            if self.v31:
                self.work('advance',1,.001,e)
                self.work('buy',buy_eth,.00015/.5,e,2000000*math.ceil(buy_eth/.5))
                self.work('plan_entropy',1,.00001,e,210000)
                self.work('pack_entropy',self.entropy_count,.00001,e,120000*self.entropy_count);self.entropy_count=0
                self.run_imd+=.5;self.run_eth+=self.run_cost
            else:
                bounty=min(.001,self.heartbeat);self.heartbeat-=bounty;self.bounties+=bounty
            kind,d=self.event(e);severity=.5 if not self.autonomous and kind not in ('green','cheap','calm') else 1.;measured=[];total_raw=0.;shadow_records={};shadow_total=0.;measure_gas=0;roster=0
            for i,f in enumerate(self.farmers):
                if not f.alive or f.joined==e:continue
                rooms=f.equip(e);f.allocation=sum(stats(r,f.paid,f.overclock)[0] for r in rooms);roster+=bool(any(rooms));measure_gas+=550000+70000*sum(map(len,rooms));raw=productive=power=baseline=0.
                shadow_raw=shadow_yield=0.
                for shadow_room in f.equip(e,True):
                    a,b,_,_=stats(shadow_room,f.paid,f.overclock,shadow=True);shadow_raw+=a;shadow_yield+=b
                    for it in shadow_room:it.shadow=max(0,it.shadow-.005)
                shadow_records[i]=(shadow_raw,shadow_yield);shadow_total+=shadow_raw
                # Independent deterministic event/farm draw; callers and settlement order do not select victims.
                random_word=int.from_bytes(hashlib.sha256(f'{self.seed}:{e}:{i}'.encode()).digest(),'big')
                local=f.district==d;outage=kind=='outage' and local and random_word%10000<3000*severity
                surge=kind=='surge' and local and random_word%10000<1000*severity
                theft=kind=='theft' and local and random_word%10000<2000*severity
                occupied=[x for room in rooms for x in room]
                target=occupied[(random_word>>64)%len(occupied)] if surge and occupied else None
                for room in rooms:
                    a,b,c,kinds=stats(room,f.paid,f.overclock,e<f.theft_until);raw+=a;baseline+=b
                    if theft and not {8,10}<=kinds:f.theft_until=e+2
                    for it in room:
                        if it is target and not {3,11}<=kinds:
                            if (random_word>>128)%100<2 and it.rarity<3:it.health=0;it.destroyed=True
                            else:it.health=max(0,it.health-.5)
                        if kind=='fire' and local and not {3,7}<=kinds:it.health=max(0,it.health-(.15 if {6,10}<=kinds else .30)*severity)
                    _,b,c,kinds=stats(room,f.paid,f.overclock,e<f.theft_until)
                    if outage:b*=.5 if {4,5}<=kinds else 0;c*=.5 if {4,5}<=kinds else 0
                    if kind=='fire' and local and not ({6,7}&kinds):b=c=0
                    if kind=='green' and local:b*=1.1;c*=1.1
                    productive+=b;power+=c
                    for it in room:it.health=max(0,it.health-.005)
                if raw:measured.append((i,raw,productive,power,baseline));total_raw+=raw
            # Offline farms keep their committed allocation until an owner action.
            # Their bounded future claims remain reserved, not fictitiously recycled by keepers.
            total_raw=sum(f.allocation for f in self.farmers)
            ghost_weight=sum(f.allocation for f in self.farmers if not f.alive)
            self.pool+=self.scrap_reserved;self.scrap_reserved=0. # advance recycles the old allowance before sizing mining
            mining=self.pool*self.emission/4 if total_raw else 0.;budget=mining*1.17;redis=redis_for_epoch;self.pool-=budget
            top={i for i,raw,*_ in measured if raw>100} if kind=='audit' else set() # contract hashes are 1000x model units
            spent=0.;loss=0.;baseline_value=0.;epoch_net=0.
            for i,raw,productive,power,baseline in measured:
                user_gas=(550000+70000*sum(map(len,self.farmers[i].equip(e)))+300000)*self.gas_price/1e18
                self.user_gas+=user_gas
                self.farmers[i].cost+=user_gas
                f=self.farmers[i];gross=mining*productive/total_raw;tariff=mining*power/total_raw*self.tariff*(.5 if kind=='cheap' else 1)
                audit=gross*.1 if i in top else 0;net=max(0,gross-tariff-audit);reused=redis*min(raw,f.allocation)/total_raw
                # 40% referral adoption, independently funded at 5% on top; aggregate attribution.
                referral=gross*.05*.4;f.held+=net+reused+referral;spent+=net+reused+referral;epoch_net+=net*self.price
                f.xp+=100;f.tickets+=1;f.gross_week+=gross;f.yields.append(net*self.price)
                baseline_gross=mining*shadow_records[i][1]/total_raw if total_raw else 0.;loss+=max(0,baseline_gross-gross+audit)*self.price;baseline_value+=baseline_gross*self.price
                # Maintenance/reinvestment uses internal balance and returns every token to pool.
                repair=min(f.held,net*.03);f.held-=repair;self.pool+=repair;f.spend_week+=repair*self.price;self.week_spend[f.district]+=repair*self.price
                for it in f.items:
                    it.health=0 if it.destroyed else min(1,it.health+.006 if repair else it.health);it.shadow=min(1,it.shadow+.006 if repair else it.shadow)
                if self.rng.random()<.03/4:self.pack(f,e,token=True)
                lobby=.00004/4;self.route(lobby);self.week_spend[f.district]+=lobby;f.cost+=lobby;self.lobbies[f.district]+=lobby
                # 65% sale intent, 35% retained/spent; weighted 0/3/7 day cashout ages.
                amount=f.held*self.sale_fraction;f.held-=amount;age=self.rng.choices((0,3,7),(.4,.3,.3))[0];self.queue.append((e+max(1,age*4),i,amount,age))
                if f.cash>=f.cost and f.paid and f.payback is None:f.payback=(e-f.joined)/4
                rate=sum(f.yields[-4:]);churn=.015 if rate>=f.cost*.02 else .075
                if self.rng.random()<churn/4:f.alive=False
                if self.sold-pack_before>=2*self.target*6 and self.rng.random()<.05 and sum(not x.destroyed for x in f.items)-sum(map(len,f.equip(e)))<15:
                    item=draw(self.rng,level(f.xp));item.rarity=min(item.rarity,1);f.items.append(item)
            measured_ids={x[0] for x in measured}
            for i,(_,b) in shadow_records.items():
                if i not in measured_ids and total_raw:loss+=mining*b/total_raw*self.price;baseline_value+=mining*b/total_raw*self.price
            ghost_reserve,allowance=reservation_remainder(mining,redis,ghost_weight/total_raw if total_raw else 0.,spent)
            if not measured:allowance=0.
            self.lazy_reserved+=ghost_reserve
            prize=mining*.01 if total_raw else 0.;self.week_prize+=prize;spent+=prize
            self.pool+=budget+redis-spent-allowance-ghost_reserve;self.scrap_reserved=allowance
            if not total_raw:self.pool-=redis;self.redis+=redis
            self.loss_total+=loss;self.baseline_total+=baseline_value
            if e%28==27:
                eligible=[i for i,f in enumerate(self.farmers) if f.tickets and f.alive]
                best=max((i for i in eligible if self.farmers[i].gross_week),key=lambda i:self.farmers[i].spend_week/self.farmers[i].gross_week,default=None)
                winning=max(range(8),key=lambda j:self.week_spend[j])
                candidates=list(eligible);winners=[]
                for _ in range(min(3,len(candidates))):
                    idx=self.rng.choices(candidates,[self.farmers[i].tickets for i in candidates])[0]
                    winners.append((idx,lottery_item(self.rng,level(self.farmers[idx].xp))));candidates.remove(idx)
                self.delayed_prizes.append((e+28,best,winning,eligible,winners,self.week_prize))
                self.delayed_prize_tokens+=self.week_prize;self.week_prize=0.
                for f in self.farmers:f.gross_week=f.spend_week=f.tickets=0
                self.week_spend=[0.]*8
            for j in range(8):self.lobbies[j]*=2**(-.25/3)
            active=sum(f.alive for f in self.farmers);self.peak=max(self.peak,active)
            if day>=3 and self.stall is None and (active<self.peak*.25 or forecast>60):self.stall=round(day,2)
            if e%4==3 and not self.autonomous:self.emission,self.tariff,self.target,self.positive=controller(self.emission,self.tariff,self.target,self.positive,1/(self.emission*1.17),forecast,loss/max(baseline_value,1e-12),self.pace_policy)
            prior_packs=sum(r['pack_eth'] for r in self.rows)
            if self.v31:self.heartbeat_flows.append(dict(day=(e+1)/4,income=self.heartbeat_in,routed_eth=self.routed_eth,bounties_due=self.bounty_due,bounties_paid=self.bounties,runs_eth=self.run_eth,headroom=self.heartbeat_in-self.bounty_due,combined_headroom=self.heartbeat_in-self.bounty_due-self.run_eth))
            self.rows.append(dict(epoch=e+1,day=(e+1)/4,price=self.price,pool=self.pool,active=active,emission=self.emission,tariff=self.tariff,pack_eth=self.pack_eth-prior_packs,event=kind,severity=severity,loss=loss,baseline=baseline_value,net=epoch_net,forecast=forecast))
            self.conservation()
        cohorts=[]
        for w in range(5):
            fs=[f for f in self.farmers if f.paid and f.joined//28==w]
            realized=[f.payback for f in fs if f.payback is not None]
            # Project only the remaining cost from last-day net yield; no token-price appreciation assumption.
            projected=[(140-f.joined)/4+max(0,f.cost-f.cash)/(sum(f.yields[-4:])*.65*(1-tax(3))*(1-base-.0025)) for f in fs if f.yields and sum(f.yields[-4:])>0 and f.alive and f.payback is None]
            outcomes=realized+projected
            all_median=statistics.median(realized+[math.inf]*(len(fs)-len(realized))) if fs else math.inf
            cohorts.append(dict(week=w+1,farms=len(fs),realized_fraction=len(realized)/max(1,len(fs)),realized_median=statistics.median(realized) if realized else None,all_farms_median=all_median if math.isfinite(all_median) else None,within_10d_fraction=sum(x<=10 for x in realized)/max(1,len(fs)),estimated_median=statistics.median(outcomes) if outcomes else None,unpaid_or_quit=len(fs)-len(realized)))
        weekly_losses=[]
        for w in range(5):
            rows=self.rows[w*28:(w+1)*28];weekly_losses.append(sum(r['loss'] for r in rows)/max(1e-12,sum(r['baseline'] for r in rows)))
        return dict(version="3.2",team_share=self.team_share,lazy_reserved=self.lazy_reserved,delayed_prize_tokens=self.delayed_prize_tokens,user_settlement_gas_eth=self.user_gas,pack_scale=self.pack_scale,sale_fraction=self.sale_fraction,gas_price=self.gas_price,autonomous=self.autonomous,endowment=self.endowment_fraction,pool_bps=int(round((.9-self.endowment_fraction)*10000)),drip_days=self.drip_days,single_sided=self.v31,opening_cap_eth=10/.9,initial_actual_amm_eth=0 if self.v31 else 10,claim_lock_days=self.claim_lock_days,heartbeat_bps=self.heartbeat_bps,heartbeat_cap=self.heartbeat_cap,heartbeat_income=self.heartbeat_in,routed_eth=self.routed_eth,bounties_due=self.bounty_due,bounty_shortfall=self.bounty_shortfall,first_bounty_shortfall=self.first_shortfall,work_due=self.work_due,work_paid=self.work_paid,swarm_runs_imd=self.run_imd,swarm_runs_eth=self.run_eth,heartbeat_flows=self.heartbeat_flows,locked_endowment=self.locked,swarm_unsold=self.swarm,players_unsold=sum(f.wallet for f in self.farmers),scenario=self.scenario,path=self.path,pace_policy=self.pace_policy,starter_entitlements=900,contributor_agents=900,bootstrap_eth=self.bootstrap,swarm_sale_fraction=self.sell_fraction,cohorts=cohorts,stall_day=self.stall,team_eth=self.team,heartbeat_eth=self.heartbeat,bounties_eth=self.bounties,network_eth=self.network,pool_tokens=self.pool,pack_eth=self.pack_eth,final_price=self.price,final_emission=self.emission,final_tariff=self.tariff,max_weekly_event_loss=max(weekly_losses),weekly_event_losses=weekly_losses,token_conservation_max_error=self.max_error,rows=self.rows)

def report(results):
    lines=['# BLACKOUT v3 simulation — 35 days, 140 six-hour epochs','',f"Explicit initial reward-pool buy capital: {results[0]['bootstrap_eth']:.1f} ETH; pace policy: {results[0]['pace_policy']}. This is a scenario input, not an authorized or funded transaction.",'',
      'Deterministic seed 20261011. Initial AMM: 900M tokens / 10 ETH; remaining 100M held by approximately 900 NFT holders. Each run explicitly reports its initial game reward-pool buy capital. Numbers are scenario outcomes, not promised returns.','',
      '| Scenario | Fee path | Holder sale | Week-1 whole-cohort payback | Week-1 repaid share by day35 | Stall day | Team ETH | Heartbeat balance / paid bounties ETH | Max weekly event loss |',
      '|---|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in results:
        c=r['cohorts'][0];pb='not reached' if c['all_farms_median'] is None else f"{c['all_farms_median']:.2f}d"
        lines.append(f"| {r['scenario']} | {r['path']} | {r['swarm_sale_fraction']:.0%} | {pb} | {c['realized_fraction']:.1%} | {r['stall_day'] if r['stall_day'] is not None else '>35'} | {r['team_eth']:.4f} | {r['heartbeat_eth']:.4f} / {r['bounties_eth']:.4f} | {r['max_weekly_event_loss']:.2%} |")
    lines+=['','Payback is cash withdrawn after tax and market fees. Whole-cohort medians treat unrepaid farms as right-censored; not reached means at least half have not repaid within the run. Conditional realized medians include only farms repaid and must be read with their fraction. Estimated medians combine realized results with constant-last-day-yield projections for surviving unpaid farms; they exclude quitters without payback and are **not** realized results. Week 5 is heavily right-censored.','', '| Scenario / path | Join week | Paid farms | Whole-cohort median days | Conditional realized median days | Repaid fraction | Repaid within10d | Estimated median days |','|---|---:|---:|---:|---:|---:|---:|---:|']
    for r in results:
        for c in r['cohorts']:
            fmt=lambda v:'n/a' if v is None else f'{v:.2f}'
            lines.append(f"| {r['scenario']} / {r['path']} | {c['week']} | {c['farms']} | {fmt(c['all_farms_median'])} | {fmt(c['realized_median'])} | {c['realized_fraction']:.1%} | {c['within_10d_fraction']:.1%} | {fmt(c['estimated_median'])} |")
    lines+=['','Full per-epoch data and conservation errors: `artifacts/simulation-v3.json`. Event loss is measured against a parallel no-event item-health counterfactual under the same policy, budget and prices; accumulated damage and destruction remain in that counterfactual. Churn, repair and lottery timing are scenario assumptions.','']
    return '\n'.join(lines)

class Checks(unittest.TestCase):
    def test_price(self):
        self.assertAlmostEqual(vrgda(0,0),.01);self.assertAlmostEqual(vrgda(1,0),.0101);self.assertEqual(vrgda(0,1000),.006);self.assertEqual(vrgda(10000,0),.03)
    def test_controller(self):
        a=(.035,.15,20,.25);b=controller(*a,10,20,.1)
        for old,new in zip(a,b):self.assertLessEqual(abs(new-old),old*.1000001)
        self.assertLess(b[0],a[0]);self.assertGreater(b[1],a[1])
    def test_hold_and_adaptive_pace_are_bounded(self):
        self.assertEqual(controller(.06,.10,20,.25,15,40,.01,"hold")[2],20)
        self.assertEqual(controller(.06,.10,20,.25,15,40,.01,"adaptive")[2],22)
    def test_tax(self):self.assertEqual(tax(0),.2);self.assertAlmostEqual(tax(3.5),.125);self.assertEqual(tax(100),.05)
    def test_room(self):
        r=[Item(0,0),Item(1,0),Item(2,0)];self.assertEqual(stats(r,True)[0],36);self.assertEqual(stats([Item(3,0)],True)[0],6)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--output',default='artifacts');p.add_argument('--bootstrap-eth',type=float,default=0.);p.add_argument('--pace-policy',choices=('reduce','hold','adaptive'),default='reduce');args=p.parse_args()
    if args.check:
        suite=unittest.main(argv=['sim'],exit=False);raise SystemExit(0 if suite.result.wasSuccessful() else 1)
    else:
        results=[Model(s,path,bootstrap=args.bootstrap_eth,pace_policy=args.pace_policy).run() for s in ('steady','hype','weak') for path in ('custom','standard')]
        dest=Path(args.output);dest.mkdir(exist_ok=True,parents=True);(dest/'simulation-v3.json').write_text(json.dumps(results,indent=2)+'\n');(dest/'simulation-v3.md').write_text(report(results));print(report(results))
