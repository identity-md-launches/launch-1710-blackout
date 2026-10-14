#!/usr/bin/env python3
"""BLACKOUT: a stdlib-only reconstruction, NOT the unavailable original v2 code.

Tokens are in whole-token units, ETH in ETH. A token balance conservation check
runs after every day. Behavioural forecasts are assumptions, not acceptance facts.
"""
from __future__ import annotations
import argparse
from dataclasses import dataclass, field, replace
import math
import random
import statistics
import unittest

SUPPLY = 1_000_000_000.0
RARITY_HASH = (10., 28., 80., 250.)
TYPE_CDF = (30, 60, 72, 84, 88, 92, 100)
RARITY_CDF = (70, 92, 99, 100)

@dataclass(frozen=True)
class Settings:
    days: int = 35
    seed: int = 20261010
    virtual_eth: float = 10.
    sell_intent: float = .65
    emission: float = .035
    swarm_sold: float = .5
    nft_claim_rate: float = .35
    referral_share: float = .4
    lobby_per_farm: float = .00004
    external_volume: float = .5
    set_bonuses: bool = True
    full_set: float = .25
    compute_pair: float = .10
    electricity_pair: float = .15
    shield_pair: float = .25
    rarity_sets: tuple = (0., .05, .10, .20)
    set_cap: float = .40
    generator_fraction: float = 0.  # no participation assumption supplied in either report
    generator_mitigation: float = .25

@dataclass(frozen=True)
class Item:
    kind: int
    rarity: int
    epoch: int = 0
    starter: bool = False


def draw(rng: random.Random, epoch: int, starter=False) -> Item:
    t, r = rng.randrange(100), rng.randrange(100)
    kind = next(i for i, bound in enumerate(TYPE_CDF) if t < bound)
    rarity = (1 if r < 92 else 2) if starter else next(i for i, bound in enumerate(RARITY_CDF) if r < bound)
    return Item(kind, rarity, min(epoch, 4), starter)


def room_stats(items: list[Item], settings: Settings, paid=True, overclock=0.):
    """One item/type in a room. Return hash, power-equivalent hash, heat and blackout losses."""
    assert len(items) <= 6 and len({i.kind for i in items}) == len(items)
    kinds = {i.kind for i in items}
    h = sum(RARITY_HASH[i.rarity] * (1 + .1 * i.epoch) *
            (.5 if i.starter and not paid else 1.) * (1 + .1 * overclock) for i in items)
    bonus = saving = shielding = 0.
    if settings.set_bonuses:
        bonus += settings.full_set if len(kinds) == 6 else 0.
        bonus += settings.compute_pair if {0, 1} <= kinds else 0.
        counts = [sum(i.rarity == r for i in items) for r in range(4)]
        bonus += max((settings.rarity_sets[r] for r in range(1, 4) if counts[r] >= 3), default=0.)
        bonus = min(settings.set_cap, bonus)
        saving = settings.electricity_pair if {2, 3} <= kinds else 0.
        shielding = settings.shield_pair if {4, 5} <= kinds else 0.
    h *= 1 + bonus
    cooling = any(i.kind == 3 and i.rarity >= 1 for i in items)
    return h, h * (1 - saving), h * (0 if cooling else .2), h * .5 * (1 - shielding), bonus

@dataclass
class Farmer:
    joined: int
    district: int
    starter: bool = False
    referred: bool = False
    generator: bool = False
    alive: bool = True
    paid: bool = False
    inventory: list[Item] = field(default_factory=list)
    cost: float = 0.
    cash: float = 0.
    held: float = 0.
    queued_tokens: float = 0.
    gross_week: float = 0.
    burn_week: float = 0.
    overclock: float = 0.
    pack_savings: float = 0.
    token_packs: int = 0
    paid_packs: int = 0
    payback: int | None = None
    yields: list[float] = field(default_factory=list)
    _stats: tuple | None = None

    def pack(self, rng, day, price=0., starter=False, token=False):
        self.inventory.extend(draw(rng, (day-1)//7, starter) for _ in range(3))
        self.cost += price
        if not starter:
            self.paid = True
            if token: self.token_packs += 1
            else: self.paid_packs += 1
        self._stats = None

    def stats(self, cfg):
        if self._stats is not None: return self._stats
        room_count = min(4, 1 + sum(i.kind == 6 for i in self.inventory))
        def hash_of(i):
            return RARITY_HASH[i.rarity] * (1 + .1*i.epoch) * (.5 if i.starter and not self.paid else 1.)
        equipment = sorted((i for i in self.inventory if i.kind != 6), key=hash_of, reverse=True)[:40]
        rooms = [[] for _ in range(room_count)]
        solo = []
        for item in equipment:
            for room in rooms:
                if item.kind not in {i.kind for i in room}:
                    room.append(item)
                    break
            else: solo.append(item)
        h = p = heat = black = 0.
        for room in rooms:
            a, b, c, d, _ = room_stats(room, cfg, self.paid, self.overclock)
            h += a; p += b; heat += c; black += d
        for i in solo:
            a = hash_of(i) * (1 + .1*self.overclock)
            h += a; p += a; heat += .2*a; black += .5*a
        if self.generator: black *= 1-cfg.generator_mitigation
        self._stats = h, p, heat, black
        return self._stats


def withdrawal_tax(age): return .05 if age >= 7 else .20 - .15*age/7
def sell_fee(sells, buys, before, after):
    s24 = max(0., (sells-buys)/(sells+buys+2.))
    s1 = min(1., 1.25*s24)
    dev = max(0., .5*(1-after/before)) if before else 0.
    return min(.1475, .01 + .05*s1 + .04*s24 + .5*min(dev,.1))

class Economy:
    def __init__(self, scenario, cfg):
        self.scenario, self.cfg = scenario, cfg
        self.rng = random.Random(cfg.seed)
        self.x, self.y = cfg.virtual_eth, 900_000_000.
        self.pool = self.burn = self.redistribute = 0.
        self.swarm = 100_000_000.
        self.team = self.heartbeat = self.network = 0.
        self.reward_eth = self.burn_eth = 0.
        self.farmers = []
        self.queue = []  # (due day, farmer index, tokens, age)
        self.rows = []
        self.week_emission = self.referral_emission = self.inspection = 0.
        self.fresh_emission = 0.
        self.event_history = []
        self.tariff = .15
        self.rps = 0.
        self.last_blackout = [-100]*8
        self.lobbies = [0.]*8
        self.pack_eth = self.lobby_eth = self.base_eth = self.extra_eth = 0.
        self.token_packs = self.free_packs = 0
        self.average_tax = sum(w*withdrawal_tax(age) for w, age in ((.4,0),(.3,3),(.3,7)))
        self.tax_redistributed = 0.

    @property
    def price(self): return self.x/self.y

    def route(self, amount, stream):
        splits = {'pack':(.65,.10,.15,.10), 'base':(.30,.40,.20,.10),
                  'excess':(.40,.35,.15,.10), 'lobby':(0.,.85,.10,.05)}
        reward, burn, team, heartbeat = splits[stream]
        self.reward_eth += amount*reward; self.burn_eth += amount*burn
        self.team += amount*team; self.heartbeat += amount*heartbeat
        if stream == 'base': self.base_eth += amount
        elif stream == 'excess': self.extra_eth += amount

    def buy(self, eth):
        if eth <= 0: return 0.
        self.route(eth*.01, 'base'); self.network += eth*.0025
        net = eth*.9875
        tokens = self.y*net/(self.x+net)
        self.x += net; self.y -= tokens
        return tokens

    def sell(self, tokens, fee):
        if tokens <= 0: return 0.
        gross = self.x*tokens/(self.y+tokens)
        self.y += tokens; self.x -= gross
        self.route(gross*.01,'base'); self.route(gross*(fee-.01),'excess'); self.network += gross*.0025
        return gross*(1-fee-.0025)

    def execute_buys(self):
        # Batch timing is collapsed into one daily aggregate; fees from these buys wait until tomorrow.
        reward, burn = self.reward_eth, self.burn_eth
        self.reward_eth = self.burn_eth = 0.
        self.pool += self.buy(reward); self.burn += self.buy(burn)
        return reward+burn

    def newcomers(self, day):
        if self.scenario == 'hype': return 600*math.exp(-(day-1)/5)+25
        if self.scenario == 'steady': return 150 if day <= 3 else 80
        return 40*math.exp(-(day-1)/15)+5

    def pack_price(self, day, previous):
        base = max(.006, .01*.85**((day-1)//7))
        return base*(1+min(.5,max(0., .5*(previous/1000-1))))

    def event(self, tick):
        probabilities = {'surge':.30, 'heat':.25, 'blackout':.20, 'audit':.15, 'calm':.10}
        caps = {'surge':8, 'heat':6, 'blackout':5, 'audit':4}
        possible = []
        for candidate in probabilities:
            window = self.event_history[-19:] + [candidate]
            counts = {k:window.count(k) for k in caps}
            if any(counts[k] > caps[k] for k in caps): continue
            if tick >= 19 and (counts['surge'] < 4 or counts['heat'] < 2):
                if not ((candidate == 'surge' and counts['surge'] <= 4) or
                        (candidate == 'heat' and counts['heat'] <= 2)): continue
            possible.append(candidate)
        kind = self.rng.choices(possible, [probabilities[k] for k in possible])[0]
        if kind == 'blackout':
            mean = max(.05, sum(self.lobbies)/8)
            weights = [max(.4,1/(1+.5*l/mean)) if tick-self.last_blackout[d]>=6 else 0. for d,l in enumerate(self.lobbies)]
            if sum(weights) == 0:
                self.event_history.append('calm')
                return 'calm', []
            d = self.rng.choices(range(8),weights)[0]; self.last_blackout[d] = tick
            self.event_history.append(kind)
            return kind,[d]
        self.event_history.append(kind)
        return kind,self.rng.sample(range(8),2 if kind == 'heat' else 1)

    def reward(self, farmer, gross, power_ratio, day, pack_price, fee):
        farmer.gross_week += gross
        upkeep = gross*self.tariff*power_ratio
        repair = gross*.05
        merge = gross*.02
        sunk = min(gross,upkeep+repair+merge)
        free = gross-sunk
        upgrade = free*.15
        free -= upgrade
        sunk += upgrade
        redirect = free*self.cfg.sell_intent*min(.6,1.5*self.average_tax)
        pack_budget = redirect*.25
        # One token pack per farmer per rolling day in the daily model.
        cost = pack_price/self.price/1.05
        farmer.pack_savings += pack_budget
        bought = current_pack_use = old_pack_use = 0.
        if cost>0 and farmer.pack_savings>=cost:
            bought=cost;farmer.pack_savings-=cost
            current_pack_use=min(cost,pack_budget);old_pack_use=cost-current_pack_use
            farmer.held-=old_pack_use
            farmer.pack(self.rng,day,token=True);self.token_packs+=1
            self.pool+=cost*.70;self.burn+=cost*.30;farmer.burn_week+=cost*.30
        # Unused fractional pack budgets stay held; they are not silently converted into fractional NFTs.
        other_spend = redirect*.75
        sunk += other_spend
        self.burn += sunk;farmer.burn_week += sunk
        daily_yield = farmer.stats(self.cfg)[0]*self.rps
        if daily_yield>0:
            farmer.overclock=min(5.,farmer.overclock+(upgrade+other_spend*1.05)/(.1*daily_yield*15*1.4**farmer.overclock))
            farmer._stats=None
        sold_fraction = self.cfg.sell_intent*max(0.,1-min(.6,1.5*self.average_tax)-max(0.,fee-.01))
        sell_tokens = free*sold_fraction
        held = free-sell_tokens-other_spend-current_pack_use
        assert held >= -1e-6
        farmer.held += max(0.,held)
        farmer.yields[-1] += (held-old_pack_use)*self.price*.95 + sell_tokens*(1-self.average_tax)*self.price*(1-fee-.0025)
        return sell_tokens

    def run(self):
        previous_packs = 0; peak = 0; perceived = 21.; fee = .01
        n_free = round(1999*self.cfg.nft_claim_rate)
        starter_plan = [0]*(self.cfg.days+1)
        for k in range(n_free):
            day = 3+(k%3) if k<n_free//2 else 6+(k%10)
            if day <= self.cfg.days: starter_plan[day]+=1
        for day in range(1,self.cfg.days+1):
            before = self.price
            p = self.pack_price(day,previous_packs)
            demand = min(1.,math.sqrt(21/max(1.,perceived)))
            new = round(self.newcomers(day)*demand)
            packs = 0
            for _ in range(new):
                f=Farmer(day,self.rng.randrange(8),referred=self.rng.random()<self.cfg.referral_share,
                         generator=self.rng.random()<self.cfg.generator_fraction)
                desired=3*(.01/p)**.7
                count=int(desired)+(self.rng.random()<desired%1)
                for _ in range(min(20,max(1,count))):f.pack(self.rng,day,p);packs+=1
                self.farmers.append(f)
            for f in self.farmers:
                if f.alive and f.joined<day and self.rng.random()<.03:
                    f.pack(self.rng,day,p);packs+=1
            for _ in range(starter_plan[day]):
                f=Farmer(day,self.rng.randrange(8),starter=True)
                f.pack(self.rng,day,starter=True);self.farmers.append(f);self.free_packs+=1
            pack_eth=packs*p;self.pack_eth+=pack_eth;self.route(pack_eth,'pack')
            alive=[(i,f) for i,f in enumerate(self.farmers) if f.alive]
            for _,f in alive:f.yields.append(0.)
            for i,f in enumerate(self.farmers):
                if not f.alive:f.yields.append(0.)
            self.lobbies=[v*2**(-1/3) for v in self.lobbies]
            lobby=len(alive)*self.cfg.lobby_per_farm;self.lobby_eth+=lobby;self.route(lobby,'lobby')
            for _,f in alive:self.lobbies[f.district]+=self.cfg.lobby_per_farm
            system_buys=self.execute_buys()
            gross_by_farmer={i:0. for i,_ in alive}
            fresh_by_farmer={i:0. for i,_ in alive};events=[];emission=0.
            # Redistributed tax is part of the next tick, not newly minted rewards.
            redistributed=self.redistribute;self.redistribute=0.
            for half in range(2):
                stats={i:f.stats(self.cfg) for i,f in alive}
                raw=sum(s[0] for s in stats.values())
                hashes={i:min(s[0],.02*raw)+.5*max(0.,s[0]-.02*raw) for i,s in stats.items()}
                kind,districts=self.event((day-1)*2+half);events.append(kind)
                weighted={}
                for i,f in alive:
                    h,power,heat,black=stats[i]
                    factor=1.
                    if f.district in districts:
                        if kind=='surge':factor=1.5
                        elif kind=='heat' and h:factor=1-heat/h
                        elif kind=='blackout' and h:factor=1-black/h
                    weighted[i]=hashes[i]*factor
                total=sum(weighted.values())
                fresh=self.pool*self.cfg.emission/2*(1.05 if kind=='surge' else 1.)
                self.pool-=fresh
                e=fresh
                if half==0:e+=redistributed
                emission+=e
                if total:
                    self.week_emission+=fresh;self.fresh_emission+=fresh
                    for i,f in alive:
                        g=e*weighted[i]/total
                        mining=fresh*weighted[i]/total
                        if kind=='audit' and hashes[i]>=2000:
                            self.burn+=g*.05;g*=.95;mining*=.95
                        gross_by_farmer[i]+=g
                        fresh_by_farmer[i]+=mining
                else:self.pool+=e
            total_hash=sum(f.stats(self.cfg)[0] for _,f in alive)
            self.rps=.7*self.rps+.3*(emission/total_hash if total_hash else 0.)
            referral=0.
            for i,f in alive:
                if f.referred:
                    extra=min(self.pool,fresh_by_farmer[i]*.05);self.pool-=extra;referral+=extra
                    # Cohort model attributes inviter receipts to the referred population (40% assumption).
                    gross_by_farmer[i]+=extra
            self.referral_emission+=referral
            for i,f in alive:
                h,power,_,_=f.stats(self.cfg)
                sold=self.reward(f,gross_by_farmer[i],power/h if h else 1.,day,p,fee)
                for weight,age in ((.4,0),(.3,3),(.3,7)):self.queue.append((day+age,i,sold*weight,age))
                f.queued_tokens+=sold
            if day%7==0 and alive:
                candidates=[(i,f) for i,f in alive if f.stats(self.cfg)[0]>=100 and f.gross_week>0]
                if candidates:
                    i,winner=max(candidates,key=lambda x:x[1].burn_week/x[1].gross_week)
                    prize=min(self.pool,self.week_emission*.01);self.pool-=prize;self.inspection+=prize
                    # v2 assumes half of the inspection prize is sold. Claims still pay day-zero tax.
                    winner.held+=prize*.5;winner.queued_tokens+=prize*.5
                    self.queue.append((day,i,prize*.5,0))
                    winner.yields[-1]+=prize*.5*self.price*(.95+(1-withdrawal_tax(0))*(1-fee-.0025))
                self.week_emission=0.
                for _,f in alive:f.gross_week=f.burn_week=0.
            due=[q for q in self.queue if q[0]<=day];self.queue=[q for q in self.queue if q[0]>day]
            net_due=[]
            for _,i,tokens,age in due:
                self.farmers[i].queued_tokens-=tokens
                tax=tokens*withdrawal_tax(age);self.redistribute+=tax;self.tax_redistributed+=tax
                net_due.append((i,tokens-tax))
            swarm_sell=min(self.swarm,100_000_000*self.cfg.swarm_sold/14) if day<=14 else 0.
            projected_sell=sum(t for _,t in net_due)+swarm_sell
            raw_eth=self.x*projected_sell/(self.y+projected_sell) if projected_sell else 0.
            after=(self.x-raw_eth)/(self.y+projected_sell)
            fee=sell_fee(raw_eth,system_buys+pack_eth*self.cfg.external_volume,before,after)
            for i,tokens in net_due:
                cash=self.sell(tokens,fee);self.farmers[i].cash+=cash
            self.swarm-=swarm_sell;self.sell(swarm_sell,fee)
            external_tokens=self.buy(pack_eth*self.cfg.external_volume);self.sell(external_tokens,fee)
            active=len(alive);peak=max(peak,active)
            yields=[f.yields[-1]/max(1,f.paid_packs) for _,f in alive if f.paid_packs]
            net_yield=statistics.mean(yields) if yields else 0.
            perceived=p/max(net_yield,1e-12)
            if perceived>35:self.tariff=max(.10,self.tariff*.9)
            elif perceived<25 and self.price<before:self.tariff=min(.30,self.tariff*1.1)
            for _,f in alive:
                if f.cost and f.cash+(f.held+f.queued_tokens)*self.price*.95>=f.cost and f.payback is None:f.payback=day-f.joined+1
                roi=f.yields[-1]/f.cost if f.cost else .02
                churn=.015+.06*max(0.,1-roi/.02)
                if self.rng.random()<churn:f.alive=False
            total_tokens=self.y+self.pool+self.burn+self.swarm+sum(f.held for f in self.farmers)+sum(q[2] for q in self.queue)+self.redistribute
            assert abs(total_tokens-SUPPLY)<.01,(day,total_tokens)
            assert self.pool>0 and self.burn>=0 and fee+.0025<=.15+1e-12
            inflow=self.pack_eth+self.lobby_eth+self.base_eth+self.extra_eth
            assert self.team<=.2*inflow+1e-9
            self.rows.append(dict(day=day,active=active,packs=packs,pack_price=p,pool=self.pool,burn=self.burn,price=self.price,
                                  yield_per_pack=net_yield,fee=fee+.0025,tariff=self.tariff,team=self.team,heartbeat=self.heartbeat,
                                  emission=emission,events='/'.join(events),token_error=total_tokens-SUPPLY))
            previous_packs=packs
        return self

    def projected_payback(self,f):
        if f.payback is not None:return f.payback
        if not f.cost:return None
        value=f.cash+(f.held+f.queued_tokens)*self.price*.95
        if len(f.yields)<2:return None
        history=f.yields[-7:]
        positive=[(i,math.log(y)) for i,y in enumerate(history) if y>0]
        if len(positive)<2:return None
        xs=[x for x,_ in positive];ys=[y for _,y in positive]
        meanx=statistics.mean(xs);meany=statistics.mean(ys)
        slope=sum((x-meanx)*(y-meany) for x,y in positive)/sum((x-meanx)**2 for x in xs)
        decay=min(1.,max(.80,math.exp(slope)))
        daily=statistics.mean(history)
        age=self.cfg.days-f.joined+1
        for extra in range(1,121-age):
            daily*=decay;value+=daily
            if value>=f.cost:return age+extra
        return None

    def summary(self):
        weeks=[]
        for week in range(5):
            people=[f for f in self.farmers if f.cost and f.alive and (f.joined-1)//7==week]
            paid=[self.projected_payback(f) for f in people]
            finite=[v for v in paid if v is not None]
            weeks.append((statistics.mean(finite) if finite else None,1-len(finite)/max(1,len(paid))))
        stall=None
        for day in range(3,min(self.cfg.days,35)+1):
            active=self.rows[day-1]['active']
            peak=max(r['active'] for r in self.rows[:day])
            if active < .25*peak:
                stall=day;break
            people=[f for f in self.farmers if f.cost and f.alive and f.joined==day]
            values=[self.projected_payback(f) for f in people]
            # Reconstructed cohort criterion: median paid farmer in the joining cohort.
            if values and statistics.median([v if v is not None else 121 for v in values])>60:
                stall=day;break
        return weeks,stall

class ModelTests(unittest.TestCase):
    def test_sets_and_cap(self):
        cfg=Settings()
        common=[Item(i,0) for i in range(6)]
        h,p,_,black,b=room_stats(common,cfg)
        self.assertAlmostEqual(h,81);self.assertAlmostEqual(p,68.85);self.assertEqual(b,.35);self.assertAlmostEqual(black,h*.375)
        for rarity in range(1,4):self.assertAlmostEqual(room_stats([Item(i,rarity) for i in range(6)],cfg)[4],.4)
        self.assertAlmostEqual(room_stats([Item(i,2) for i in (2,3,4)],cfg)[4],.1)
    def test_every_equipment_mines_and_starter(self):
        for kind in range(6):self.assertEqual(room_stats([Item(kind,0)],Settings())[0],10)
        self.assertEqual(room_stats([Item(0,1,starter=True)],Settings(),paid=False)[0],14)
    def test_fee_tax_and_supply(self):
        self.assertEqual(withdrawal_tax(0),.2);self.assertEqual(withdrawal_tax(7),.05)
        self.assertLessEqual(sell_fee(10000,0,10,1)+.0025,.15)
        for scenario in ('steady','hype','weak'):
            e=Economy(scenario,Settings(days=10)).run()
            self.assertLess(max(abs(r['token_error']) for r in e.rows),.01)
            self.assertGreater(e.pool,0)
    def test_seed_reproducible_and_set_ablation(self):
        a=Economy('weak',Settings(days=5)).run();b=Economy('weak',Settings(days=5)).run()
        self.assertEqual(a.rows,b.rows)
        self.assertGreater(room_stats([Item(i,0) for i in range(6)],Settings())[0],room_stats([Item(i,0) for i in range(6)],Settings(set_bonuses=False))[0])
    def test_event_caps_cooldown_and_new_mining_budgets(self):
        e=Economy('steady',Settings())
        last={}
        for tick in range(200):
            kind,districts=e.event(tick)
            if kind=='blackout':
                district=districts[0]
                self.assertGreaterEqual(tick-last.get(district,-100),6)
                last[district]=tick
            window=e.event_history[-20:]
            for k,cap in {'surge':8,'heat':6,'blackout':5,'audit':4}.items():self.assertLessEqual(window.count(k),cap)
        e=Economy('hype',Settings(days=14)).run()
        self.assertLessEqual(e.referral_emission,e.fresh_emission*.05)
        self.assertAlmostEqual(e.inspection,e.fresh_emission*.01,places=6)


def report(cfg):
    print('# Reconstructed BLACKOUT economy simulation\n')
    print('Original v2 source was absent from the supplied workspace and linked research trees. This is an independently rebuilt model from the reports, with six-type items and room sets. It does **not** reproduce or certify their numerical claims.\n')
    print(f'Seed {cfg.seed}; {cfg.days} days; virtual reserve {cfg.virtual_eth:g} ETH; sell intent {cfg.sell_intent:.0%}. All quantities below are simulation outputs.\n')
    print('Daily behaviour, claim delays and fee splits follow v2. Discrete items, survivor churn, whole token packs, 40-item capacity, set bonuses and a greedy placement policy are explicit reconstruction choices. Payback is conditional on still-active paid farmers (as the source model conditions on active packs), includes subsequent purchases, and marks held/queued tokens at 95% of spot; projection uses the last seven daily yields, capped at 120 days. Never-paying farmers are reported separately; finite means are not guarantees.\n')
    for scenario in ('steady','hype','weak'):
        e=Economy(scenario,cfg).run();weeks,stall=e.summary()
        print(f'## {scenario.title()}\n')
        print('| Day | Active | Packs | Pack ETH | Reward tokens | Locked/burned | ETH / 1M tokens | Net ETH/pack/day | Total sell fee | Tariff | Team ETH |')
        print('|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
        for r in e.rows:
            if r['day'] not in (1,3,7,14,21,28,35,cfg.days):continue
            print(f"| {r['day']} | {r['active']} | {r['packs']} | {r['pack_price']:.4f} | {r['pool']/1e6:.2f}M | {r['burn']/1e6:.2f}M | {r['price']*1e6:.4f} | {r['yield_per_pack']:.6f} | {r['fee']:.2%} | {r['tariff']:.3f} | {r['team']:.3f} |")
        print('\n| Join week | Active-farmer finite mean payback (days) | No projected payback by 120 days |\n|---:|---:|---:|')
        for i,(payback,never) in enumerate(weeks):print(f'| {i+1} | {payback:.1f} | {never:.1%} |' if payback is not None else f'| {i+1} | — | {never:.1%} |')
        print(f"\nPaid farmers that left by the horizon: {sum(f.cost>0 and not f.alive for f in e.farmers)/max(1,sum(f.cost>0 for f in e.farmers)):.1%}. They are excluded from the conditional payback table, not assumed profitable.\n")
        inflow=e.pack_eth+e.lobby_eth+e.base_eth+e.extra_eth
        print(f'\nReconstructed stall criterion: day {stall or "not reached"}. Team {e.team:.3f} ETH ({e.team/inflow:.2%} of routed inflow); heartbeat {e.heartbeat:.3f} ETH. Starter packs {e.free_packs}; token packs {e.token_packs}; referrals {e.referral_emission/1e6:.3f}M tokens; inspection {e.inspection/1e6:.3f}M; withdrawal tax recycled {e.tax_redistributed/1e6:.3f}M. Maximum token conservation error {max(abs(r["token_error"]) for r in e.rows):.6g} tokens.\n')
    print('## Set and liquidity sensitivity\n')
    print('| Case (steady) | Day-35 pool | Price ETH/1M | Team ETH | Stall |\n|---|---:|---:|---:|---:|')
    for name,c in [('sets disabled',replace(cfg,set_bonuses=False)),('sets enabled',cfg),('3 ETH depth',replace(cfg,virtual_eth=3)),('5 ETH depth',replace(cfg,virtual_eth=5)),('90% sell intent',replace(cfg,sell_intent=.9)),('no swarm sells',replace(cfg,swarm_sold=0))]:
        e=Economy('steady',c).run();_,stall=e.summary()
        print(f'| {name} | {e.pool/1e6:.2f}M | {e.price*1e6:.4f} | {e.team:.3f} | {stall or "—"} |')
    print('\nThe behavioural coefficients are unmeasured. The pool staying positive does not imply profitable players. Virtual liquidity is not real redeemable ETH. No token price, yield, return, or launch liquidity is promised. Generator participation defaults to zero because the reports supply no adoption assumption.')

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--days',type=int,default=35);parser.add_argument('--seed',type=int,default=20261010)
    args=parser.parse_args()
    if args.check:unittest.main(argv=['blackout_sim_v2'],verbosity=2)
    else:report(Settings(days=args.days,seed=args.seed))
