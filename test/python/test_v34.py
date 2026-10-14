import unittest,sys,math
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tools'));sys.path.insert(0,str(root/'sim'))
from regulator import inflow_emission,propose,example
from run_v34 import snipers
from blackout_sim_v34 import Model,vrgda
class V34EconomyTest(unittest.TestCase):
    def test_seven_day_inflow_rule_steps_direction_and_bounds(self):
        self.assertEqual(inflow_emission(350,[1,1,1,1,.5,.5,.5]),315)
        self.assertEqual(inflow_emission(350,[1,1,1,1,2,2,2]),385)
        self.assertEqual(inflow_emission(350,[1]*7),350)
        self.assertEqual(inflow_emission(200,[0]*7),200)
        self.assertEqual(inflow_emission(600,[1,1,1,1,10,10,10]),600)
        self.assertLess(inflow_emission(350,[1,1,1,1,2,2,2],10),350)
        for current in range(200,601):
            for history in [[0]*7,[1]*7,[10,10,10,1,1,1,1],[1,1,1,1,10,10,10]]:
                value=inflow_emission(current,history)
                self.assertTrue(200<=value<=600)
                self.assertLessEqual(abs(value-current),current//10)
    def test_invalid_history(self):
        for history in [[1]*6,[-1]*7,[math.nan]*7]:
            with self.assertRaises(ValueError):inflow_emission(350,history)
    def test_regulator_uses_trend_instead_of_raising_for_slow_payback(self):
        s=example();s.update(availableTokens=20_000_000,packSales7DaysETH=[10,10,10,10,1,1,1])
        proposals={x['key']:x for x in propose(s)['proposals']}
        self.assertEqual(proposals['EmissionBps']['proposed'],315)
    def test_snipers_five_eth_stepped_tax_all_to_pool(self):
        cases=snipers()
        self.assertEqual([x['reward_pool_eth'] for x in cases],[4.5,2.5,1.25])
        for x in cases:
            self.assertLess(x['pnl_normal_sell'],0);self.assertLess(x['pnl_capped_sell'],0)
        self.assertLess(cases[0]['tokens'],cases[1]['tokens'])
