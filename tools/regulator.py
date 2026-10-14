#!/usr/bin/env python3
"""Dry-run only: print bounded Params proposals and a two-epoch event plan. No network/signing."""
import argparse, json, math
from pathlib import Path
BOUNDS={'EmissionBps':(200,600),'TariffBps':(1000,3000),'DemandTarget':(10,40),'PositiveWeight':(2000,5000)}

def inflow_emission(current, history, runway=100):
    if len(history)!=7 or any(not math.isfinite(x) or x<0 for x in history):
        raise ValueError('provide seven completed nonnegative daily pack payment totals')
    early=sum(history[:3]);late=sum(history[-3:])
    ratio=late/early if early else (1. if late==0 else 600/350)
    target=200 if sum(history)==0 else max(200,min(600,math.floor(350*ratio)))
    if runway<14:target=min(target,math.ceil(current*.9))
    return max(200,current-current//10,min(600,current+current//10,target))

def propose(state):
    now=state['timestamp'];values=state['params'];last=state['lastChanged'];pool=state['availableTokens'];daily=state['dailyOutflowTokens']
    if pool<0 or daily<0: raise ValueError('token balances and outflow must be nonnegative')
    if state.get('pacePolicy','reduce') not in ('reduce','hold','adaptive'): raise ValueError('invalid pacePolicy')
    runway=pool/daily if daily>0 else (math.inf if pool>0 else 0);payback=state['medianPaybackDays'];loss=state['weeklyEventLossBps'];desired=dict(values);reason=[]
    if runway<14:
        desired['EmissionBps']=math.ceil(values['EmissionBps']*.9)
        desired['TariffBps']=math.floor(values['TariffBps']*1.1)
        desired['DemandTarget']=math.ceil(values['DemandTarget']*.9)
        reason.append('Runway below fourteen days: slow outflow and pack supply, recycle a higher tariff.')
    elif payback>10:
        desired['EmissionBps']=math.floor(values['EmissionBps']*1.1)
        # Conservative total committed daily budget includes referral, green and weekly headroom.
        desired['EmissionBps']=min(desired['EmissionBps'],int(10000/(14*1.59)))
        desired['TariffBps']=math.ceil(values['TariffBps']*.9)
        desired['DemandTarget']=max(10,values['DemandTarget']-values['DemandTarget']//10)
        reason.append('Payback above ten days with runway room: increase mining and lower electricity.')
    if runway>=14 and state.get('pacePolicy','reduce')=='hold':
        desired['DemandTarget']=values['DemandTarget']
    if runway>=14 and state.get('pacePolicy','reduce')=='adaptive' and payback>30:
        desired['DemandTarget']=min(40,values['DemandTarget']+values['DemandTarget']//10)
    if loss>800:
        desired['PositiveWeight']=math.floor(values['PositiveWeight']*1.1)
        reason.append('Event losses approach ten percent: favor positive events and reduce severity.')
    # Seven completed UTC days of wallet-funded token packs. Credit recycling is excluded.
    # Legacy ETH field is retained solely for historical v3.4 input compatibility.
    if 'packSales7DaysTokens' in state or 'packSales7DaysETH' in state:
        history=state.get('packSales7DaysTokens',state.get('packSales7DaysETH'))
        desired['EmissionBps']=inflow_emission(values['EmissionBps'],history,runway)
        reason.append('Emission follows the last-three/first-three-day pack inflow ratio within a seven-day window; daily movement is bounded.')
    else:
        desired['EmissionBps']=min(desired['EmissionBps'], values['EmissionBps'])
        reason.append('No complete seven-day cash history supplied: do not raise emission.')
    output=[]
    for key,(low,high) in BOUNDS.items():
        old=values[key];step=old//10;next_=max(low,old-step,min(high,old+step,desired[key]))
        if next_!=old:output.append(dict(key=key,current=old,proposed=next_,eligibleAt=last[key]+86400,ready=now>=last[key]+86400,letter=' '.join(reason)))
    # Network conditions/rolling counts must still be checked on-chain; the contract enforces quotas.
    kinds=['Green','Cheap'] if loss>800 or runway<14 else ['Calm','Green']
    return dict(dryRun=True,runwayDays=None if math.isinf(runway) else runway,proposals=output,
                nextTwoEpochs=[dict(epoch=state['epoch']+i+1,kind=k,severity=5000 if loss>800 else 10000,randomNumber='oracle-attested public epoch salt; never a signer key',letter=' '.join(reason) or 'Maintain bounded conditions.') for i,k in enumerate(kinds)],
                operatorActions=['Flush held hook fees after the one-time bind; execute eligible depth-limited token sales and separate season-pot buys.', 'Capture each shifted epoch, paid receipt, starter and enhancement entropy before native block history expires.', 'Advance epochs without scanning farms; owners/sponsors settle each farm in chunks of at most eight epochs.', 'Use gas reimbursement caps and heartbeat balance when quoting useful keeper work.', 'Complete the week for each farm before its seven-day grace deadline; prepare once and finalize the bounded lottery afterward.', 'Pay IMD schedule top-ups from an external wallet; heartbeat ETH has no administrative exit.', 'Inspect TWAP, available pool excluding locked endowment, realized ETH payback and weekly loss before proposing an oracle policy.'],
                operations=operations(state))

def operations(state):
    """Informational cash budget. Off-chain IMD costs are never counted as withdrawable heartbeat ETH."""
    locked=state.get('lockedEndowmentTokens',0)
    balance=state.get('heartbeatBalanceETH',0)
    due=state.get('dailyKeeperCostETH',0)
    runs=state.get('scheduleRunsRemaining',0)
    if min(locked,balance,due,runs)<0:raise ValueError('operational balances must be nonnegative')
    return dict(lockedEndowmentTokens=locked,availableExcludesLocked=True,
                keeperRunwayDays=balance/due if due else None,
                externalScheduleDays=runs/4,
                scheduleTopupNeeded=runs<28,
                canFundScheduleFromHeartbeat=False,
                salePausedUntil=state.get('packSalePausedUntil',0),
                keepersAndClaimsAlwaysEnabled=True)

def example():
    return dict(timestamp=172800,epoch=12,availableTokens=1_000_000,dailyOutflowTokens=80000,medianPaybackDays=15,weeklyEventLossBps=900,
        params=dict(EmissionBps=350,TariffBps=1500,DemandTarget=20,PositiveWeight=2500),lastChanged=dict(EmissionBps=0,TariffBps=0,DemandTarget=0,PositiveWeight=0))
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('state',nargs='?',type=Path);parser.add_argument('--example',action='store_true');args=parser.parse_args()
    if not args.example and args.state is None:parser.error('supply state.json or --example')
    print(json.dumps(propose(example() if args.example else json.loads(args.state.read_text())),indent=2))
