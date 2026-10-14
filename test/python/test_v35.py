import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'sim'))
sys.path.insert(0, str(ROOT / 'tools'))
from run_v35 import repair_study, enhancement_study, Model, PROFILES, cohort_median
from freepack_merkle import free_tree
from entropy_bot import Keeper
from test_entropy_bot import FakeRPC

class V35EconomyTests(unittest.TestCase):
    def test_cohort_payback_keeps_unrepaid_members_in_the_median(self):
        self.assertEqual(cohort_median([1, 3, None]), 3)
        self.assertEqual(cohort_median([1, 3, 5, None]), 4)
        self.assertIsNone(cohort_median([1, None, None]))
        self.assertIsNone(cohort_median([1, None]))

    def test_default_maintenance_hits_explicit_targets(self):
        rows = repair_study()
        default = next(r for r in rows if r['hours'] == 6 and r['policy'] == 'below80')
        idle = next(r for r in rows if r['hours'] == 6 and r['policy'] == 'never')
        self.assertGreaterEqual(default['net_fraction'], .85)
        self.assertLessEqual(default['net_fraction'], .90)
        self.assertGreaterEqual(default['repair_return_multiple'], 2)
        self.assertLess(idle['net_fraction'], .60)
        self.assertTrue(.08 <= default['repair'] / default['mining'] <= .13)

    def test_model_conserves_supply_and_reports_all_scenarios(self):
        data = json.loads((ROOT / 'artifacts/v35/simulation.json').read_text())
        # The committed artifact is reproducible by the offline runner.
        self.assertEqual(len(data['results']), 60)
        for row in data['results']:
            self.assertLess(row['max_conservation_error'], .001)
            self.assertTrue(1.3 <= row['grower_spend_mined'] <= 1.5)

    def test_discrete_growth_and_sequential_unlock_results(self):
        data = json.loads((ROOT / 'artifacts/v35/simulation.json').read_text())
        growth = next(r for r in data['growth_playbooks'] if r['enhance_every_days'] == 2)
        self.assertTrue(1.3 <= growth['spend_mined'] <= 1.5)
        self.assertAlmostEqual(growth['net_market_share'], 1 - 1 / growth['spend_mined'])
        self.assertEqual([r['cap'] for r in data['unlock_schedule']], [8, 12, 16])
        self.assertEqual([r['day'] for r in data['unlock_schedule']], [30, 60, 90])

    def test_free_tree_rejects_duplicates_empty_and_oversize(self):
        a = '0x' + '12' * 20
        with self.assertRaises(ValueError): free_tree([])
        with self.assertRaises(ValueError): free_tree([a, a.upper().replace('0X','0x')])
        with self.assertRaises(ValueError): free_tree([a] * 501)
        tree = free_tree([a])
        self.assertEqual(tree['claims'][a]['index'], 0)
        self.assertEqual(tree['claims'][a]['proof'], [])

class EnhanceRPC(FakeRPC):
    def call(self, address, data):
        return '0x' + ''.join(format(x, '064x') for x in [1, 99, self.target, 1, 0, int(self.captured), 0])
    def send_enhancement(self, address, receipt): self.send(address, receipt)

class EnhancementKeeperTests(unittest.TestCase):
    def test_enhancement_expiry_then_capture_uses_attempt_target(self):
        rpc = EnhanceRPC()
        bot = Keeper(rpc, {'enhancement': 'enhance'}, 100)
        rpc.block = 400
        self.assertEqual(bot.tick(), [('enhancement', 1, 'rearm')])
        rpc.block = 403
        self.assertEqual(bot.tick(), [('enhancement', 1, 'capture')])
        rpc.block = 404
        self.assertEqual(bot.tick(), [])
        self.assertEqual(rpc.sent, [1, 1])
