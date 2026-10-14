import importlib.util
from pathlib import Path
import unittest
p=Path(__file__).resolve().parents[2]/'tools'/'regulator.py'
spec=importlib.util.spec_from_file_location('regulator',p);r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class RegulatorTest(unittest.TestCase):
    def test_runway_response_and_steps(self):
        s=r.example();out=r.propose(s);self.assertTrue(out['dryRun']);self.assertEqual(out['runwayDays'],12.5)
        values={x['key']:x['proposed'] for x in out['proposals']};self.assertLess(values['EmissionBps'],350);self.assertGreater(values['TariffBps'],1500)
        for x in out['proposals']:self.assertLessEqual(abs(x['proposed']-x['current']),x['current']//10)
    def test_cooldown_is_not_permission(self):
        s=r.example();s['timestamp']=1;self.assertTrue(all(not x['ready'] for x in r.propose(s)['proposals']))
    def test_good_state_no_unnecessary_changes(self):
        s=r.example();s.update(availableTokens=20_000_000,medianPaybackDays=8,weeklyEventLossBps=200)
        self.assertEqual(r.propose(s)['proposals'],[])
    def test_holding_pace_keeps_daily_emission_response(self):
        s=r.example();s.update(availableTokens=20_000_000,pacePolicy='hold',packSales7DaysETH=[1,1,1,1,2,2,2])
        changes={x['key']:x['proposed'] for x in r.propose(s)['proposals']}
        self.assertNotIn('DemandTarget',changes);self.assertGreater(changes['EmissionBps'],350)
    def test_empty_pool_is_not_infinite_runway(self):
        s=r.example();s.update(availableTokens=0,dailyOutflowTokens=0)
        self.assertEqual(r.propose(s)['runwayDays'],0)
    def test_invalid_policy_rejected(self):
        s=r.example();s['pacePolicy']='unknown'
        with self.assertRaises(ValueError):r.propose(s)

    def test_token_pack_history_takes_precedence_over_historical_eth(self):
        s=r.example();s.update(availableTokens=20_000_000,packSales7DaysTokens=[1,1,1,1,2,2,2],packSales7DaysETH=[10,10,10,1,0,0,0])
        changes={x['key']:x['proposed'] for x in r.propose(s)['proposals']}
        self.assertGreater(changes['EmissionBps'],350)
