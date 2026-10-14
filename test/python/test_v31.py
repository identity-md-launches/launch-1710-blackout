import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'sim'))
from blackout_sim_v3 import Model, SUPPLY
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
from regulator import operations

class V31ModelTest(unittest.TestCase):
    def model(self,**kwargs):return Model('steady','custom',single_sided=True,endowment=.25,**kwargs)
    def test_no_eth_to_sell_against_at_open(self):
        m=self.model();x=m.x;y=m.y
        self.assertEqual(m.sell(10_000_000,.05),0)
        self.assertEqual(m.last_unsold,10_000_000)
        self.assertEqual((m.x,m.y),(x,y))
        m.conservation()
    def test_filled_sale_cannot_consume_virtual_eth(self):
        m=self.model();tokens=m.buy(1);cash=m.sell(tokens*2,.05)
        self.assertGreater(cash,0);self.assertLess(cash,1)
        self.assertAlmostEqual(m.last_unsold,tokens)
        self.assertAlmostEqual(m.x,m.floor_x)
        self.assertAlmostEqual(m.y,m.initial_y)
    def test_instant_is_only_sensitivity(self):
        instant=self.model(drip_days=0);drip=self.model(drip_days=42)
        self.assertEqual(instant.pool,SUPPLY*.25);self.assertEqual(instant.locked,0)
        self.assertEqual(drip.pool,0);self.assertEqual(drip.locked,SUPPLY*.25)
        instant.conservation();drip.conservation()
    def test_each_receipt_costs_a_transaction(self):
        m=self.model();m.heartbeat=1;m.work('pack_entropy',8,.00001,0,120000*8)
        self.assertAlmostEqual(m.bounty_due,(120000+80000)*8*20e6/1e18*1.25)
    def test_shortfalls_not_erased_by_partial_payment(self):
        m=self.model();m.heartbeat=.0001;m.work('advance',1,.001,0)
        self.assertAlmostEqual(m.bounty_due,.001);self.assertAlmostEqual(m.bounties,.0001)
        self.assertAlmostEqual(m.bounty_shortfall,.0009);self.assertEqual(m.heartbeat,0)
    def test_external_runs_are_separate_from_locked_balance(self):
        result=operations(dict(heartbeatBalanceETH=.5,dailyKeeperCostETH=.1,scheduleRunsRemaining=12,lockedEndowmentTokens=100))
        self.assertEqual(result['keeperRunwayDays'],5);self.assertEqual(result['externalScheduleDays'],3)
        self.assertFalse(result['canFundScheduleFromHeartbeat']);self.assertTrue(result['scheduleTopupNeeded'])
