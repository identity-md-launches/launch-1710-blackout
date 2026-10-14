import random
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'sim'))
from blackout_sim_v32 import Model, Item, stats, lottery_item, reservation_remainder

class V32ModelTest(unittest.TestCase):
    def test_destroyed_item_cannot_supply_phantom_combo(self):
        room = [Item(0, 0), Item(1, 0, health=0, destroyed=True)]
        actual = stats(room, True)
        self.assertEqual(actual[:3], (10, 10, 10))
        # The undamaged parallel counterfactual intentionally retains that ASIC.
        self.assertEqual(stats(room, True, shadow=True)[0], 22)

    def test_season_lottery_is_rare_or_legendary_with_ten_percent_legendary(self):
        rng = random.Random(117)
        prizes = [lottery_item(rng, 10) for _ in range(10000)]
        rarities = [item.rarity for item in prizes]
        self.assertTrue(all(item.kind >= 9 for item in prizes if item.rarity == 3))
        self.assertEqual(set(rarities), {2, 3})
        self.assertTrue(850 < rarities.count(3) < 1150)

    def test_heartbeat_at_cap_overflows_into_rewards(self):
        m = Model('steady', 'custom', single_sided=True, endowment=.2)
        m.route(100)
        self.assertEqual(m.team, 13)
        self.assertEqual(m.heartbeat, 1)
        self.assertEqual(m.reward_eth, 86)
        m.route(1)
        self.assertEqual(m.heartbeat, 1)
        self.assertAlmostEqual(m.reward_eth, 86.87)

    def test_lazy_and_delayed_season_reserves_are_in_conservation(self):
        m = Model('steady', 'custom', single_sided=True, endowment=.2)
        m.lazy_reserved = 1000
        m.delayed_prize_tokens = 2000
        m.locked -= 3000
        m.conservation()
        m.lazy_reserved += 1
        with self.assertRaises(AssertionError):
            m.conservation()

    def test_bounty_shortfall_is_observable_even_when_calls_continue(self):
        m = Model('weak', 'custom', single_sided=True, endowment=.2)
        m.work('advance', 1, .001, 0)
        self.assertEqual(m.bounty_shortfall, .001)
        self.assertEqual(m.bounties, 0)
        self.assertEqual(m.first_shortfall, 0)

    def test_ghost_envelopes_and_final_dust_cannot_fund_scrap(self):
        retained, scrap = reservation_remainder(100, 0, .6, 34)
        self.assertAlmostEqual(retained, 69.3 + .5)
        self.assertAlmostEqual(scrap, 12.2)
        # With everyone settled, final dust is released but still cannot fund scrap.
        retained, scrap = reservation_remainder(100, 0, 0, 115.4)
        self.assertEqual(retained, 0)
        self.assertAlmostEqual(scrap, .1)
