"""Behavioral checks for the Base port consumed by the live JSON host."""

import copy
import unittest

from coworld.player.base import BasePolicy


def unit(pid=1, team=0, x=36, y=40):
    return dict(id=pid, team=team, x=x, y=y, hp=840, max_hp=840,
                alive=True, hooked=False, shield=0, hook_ready=True,
                blink_ready=False, rot=False, layer=team, gold=0, points=0,
                in_shop=False, home_x=25 if team == 0 else 103, home_y=30,
                upgrades=[0, 0, 0, 0], item_ranks=[0, 0, 0, 0, 0],
                ward_restock=100, buff=0)


def observation(me=None, others=(), hooks=()):
    me = me or unit()
    return dict(tick=200, self=me, play_west_max=52, play_east_min=76,
                visible=dict(pudges=[me, *others], hooks=list(hooks), runes=[]),
                ally_ping=None, rune_next=dict(soon=0, x=-1, y=-1))


class BaseCoworldPolicyTest(unittest.TestCase):
    def setUp(self):
        self.policy = BasePolicy()

    def test_recovery_continues_until_seventy_five_percent(self):
        me = unit()
        me.update(hp=400, max_hp=1200)
        obs = observation(me, others=[unit(pid=2, x=20, y=100)])
        self.policy.choose_action(obs)
        me["hp"] = 700
        self.assertEqual(self.policy.choose_action(obs)["walk_to"], [25, 30])
        me["hp"] = 900
        self.assertNotEqual(self.policy.choose_action(obs)["walk_to"], [25, 30])

    def test_recovery_scales_with_kill_earned_health(self):
        me = unit()
        me.update(hp=600, max_hp=1800)
        obs = observation(me, others=[unit(pid=2, x=20, y=100)])
        self.policy.choose_action(obs)
        me["hp"] = 1200
        self.assertEqual(self.policy.choose_action(obs)["walk_to"], [25, 30])
        me["hp"] = 1350
        self.assertNotEqual(self.policy.choose_action(obs)["walk_to"], [25, 30])

    def test_duel_returns_to_fishing_above_forty_percent(self):
        me = unit()
        me.update(hp=400, max_hp=1200)
        self.policy.choose_action(observation(me))
        me["hp"] = 700
        self.assertNotEqual(self.policy.choose_action(observation(me))["walk_to"], [25, 30])

    def test_death_clears_recovery(self):
        me = unit()
        me.update(hp=400, max_hp=1200)
        self.policy.choose_action(observation(me))
        me["alive"] = False
        self.policy.choose_action(observation(me))
        self.assertFalse(self.policy.recovering)

    def test_fountain_escape_requires_new_rules_and_a_clear_landing(self):
        for team in (0, 1):
            me = unit(team=team, x=73 if team == 0 else 55, y=60)
            me.update(hp=300, max_hp=1200, layer=1-team, blink_ready=True)
            obs = observation(me)
            self.assertNotIn("blink_to", BasePolicy().choose_action(obs))
            obs["game_version"] = 36
            landing = [56.0 if team == 0 else 72.0, 60.0]
            self.assertEqual(BasePolicy().choose_action(obs)["blink_to"], landing)
            ally = unit(pid=2, team=team, x=landing[0], y=landing[1])
            obs["visible"]["pudges"].append(ally)
            self.assertNotIn("blink_to", BasePolicy().choose_action(obs))

    def test_fountain_escape_respects_range_rot_and_walls(self):
        me = unit(x=73, y=60)
        me.update(hp=300, max_hp=1200, layer=1, blink_ready=True)
        obs = observation(me)
        obs["game_version"] = 36
        for update in ({"x": 80}, {"y": 40}, {"rot": True}):
            changed = copy.deepcopy(obs)
            changed["self"].update(update)
            self.assertNotIn("blink_to", BasePolicy().choose_action(changed))
        obs["visible"]["props"] = [dict(kind="wall", x=56, y=60)]
        self.assertNotIn("blink_to", BasePolicy().choose_action(obs))

    def test_dodge_on_foreign_bank_heads_inland(self):
        me = unit(x=85, y=40)
        me.update(layer=1, blink_ready=True)
        hook = dict(owner_id=4, team=1, x=77, y=40, flying=True, victim=0)
        action = self.policy.choose_action(observation(me, hooks=[hook]))
        self.assertGreater(action["blink_to"][0], me["x"])

    def test_spends_all_points_distance_then_speed(self):
        me = unit()
        me.update(points=3, upgrades=[0, 9, 0, 0])
        self.assertEqual(self.policy.choose_action(observation(me))["buy_upgrade"], [1, 2, 2])

    def test_maxed_upgrades_terminate(self):
        me = unit()
        me.update(points=10, upgrades=[10] * 4)
        self.assertNotIn("buy_upgrade", self.policy.choose_action(observation(me)))

    def test_shop_buys_multiple_permanent_ranks(self):
        me = unit()
        me.update(in_shop=True, gold=44)
        self.assertEqual(self.policy.choose_action(observation(me))["buy_power"], [6, 5, 6, 5])

    def test_flask_precedes_permanents(self):
        me = unit()
        me.update(in_shop=True, gold=17, hp=200)
        self.assertEqual(self.policy.choose_action(observation(me))["buy_power"], [0, 6])

    def test_free_ward_without_gold(self):
        me = unit()
        me.update(in_shop=True, ward_restock=0)
        self.assertEqual(self.policy.choose_action(observation(me))["buy_power"], [9])

    def test_live_protocol_without_ward_restock_timer(self):
        me = unit()
        me.update(in_shop=True, gold=22)
        del me["ward_restock"]
        self.assertEqual(self.policy.choose_action(observation(me))["buy_power"], [6, 5])

    def test_legacy_ward_does_not_start_an_impossible_placement_trip(self):
        me = unit()
        me["item_ranks"][4] = 1
        del me["ward_restock"]
        action = self.policy.choose_action(observation(me))
        self.assertEqual(action["walk_to"][0], 36)
        self.assertNotIn("place_ward", action)

    def test_unconfirmed_ward_purchase_does_not_start_a_trip(self):
        me = unit()
        me.update(in_shop=True, ward_restock=0)
        self.assertEqual(self.policy.choose_action(observation(me))["walk_to"][0], 36)

    def test_buffs_are_not_refreshed_or_replaced(self):
        for buff in range(1, 7):
            me = unit()
            me.update(in_shop=True, gold=12, item_ranks=[5, 5, 0, 0, 0], buff=buff)
            self.assertNotIn("buy_power", self.policy.choose_action(observation(me)))

    def test_one_big_hook_with_leftover_gold(self):
        me = unit()
        me.update(in_shop=True, gold=12, item_ranks=[5, 5, 0, 0, 0])
        self.assertEqual(self.policy.choose_action(observation(me))["buy_power"], [3])

    def test_actual_shop_on_both_banks_even_with_visible_enemy(self):
        for team in (0, 1):
            me = unit(team=team, x=36 if team == 0 else 92)
            me["gold"] = 24
            enemy = unit(4, 1 - team, 92 if team == 0 else 36)
            action = self.policy.choose_action(observation(me, [enemy]))
            self.assertEqual(action["walk_to"], [22 if team == 0 else 106, 64])

    def test_uses_full_base_hook_range(self):
        enemy = unit(4, 1, 91, 40)
        self.assertEqual(self.policy.choose_action(observation(others=[enemy]))["hook_to"], [91, 40])

    def test_shorter_velocity_prediction(self):
        enemy = unit(4, 1, 90, 40)
        obs = observation(others=[enemy])
        self.policy.choose_action(obs)
        obs["tick"] += 8
        enemy["y"] += 4
        aim = self.policy.choose_action(obs)["hook_to"]
        self.assertAlmostEqual(aim[1], 44 + 4 * 54 / 30)

    def test_does_not_blink_to_chase_or_stretch_a_hook(self):
        me = unit()
        me["blink_ready"] = True
        hook = dict(owner_id=1, team=0, x=52, y=40, flying=True, victim=0)
        action = self.policy.choose_action(observation(me, [unit(4, 1, 88, 40)], [hook]))
        self.assertIn("hook_to", action)
        self.assertNotIn("blink_to", action)

    def test_defensive_blink_stays_inside_actual_range(self):
        me = unit()
        me["blink_ready"] = True
        hook = dict(owner_id=4, team=1, x=56, y=40, flying=True, victim=0)
        self.policy.choose_action(observation(me, hooks=[hook]))
        obs = observation(me, hooks=[dict(hook, x=54)])
        obs["tick"] = 201
        hop = self.policy.choose_action(obs)["blink_to"]
        self.assertLessEqual((hop[0] - 36) ** 2 + (hop[1] - 40) ** 2, 400.00001)
        self.assertLess(hop[0], me["x"])

    def test_hook_before_melee_and_fight_when_cornered(self):
        me = unit(x=95)
        me.update(layer=1, hp=500)
        enemy = unit(4, 1, 100)
        enemy["rot"] = True
        action = self.policy.choose_action(observation(me, [enemy]))
        self.assertIn("hook_to", action)
        self.assertEqual(action["attack_target"], 4)
        self.assertTrue(action["rot"])

    def test_no_offensive_hook_through_an_ally(self):
        action = self.policy.choose_action(observation(others=[unit(2, 0, 46), unit(4, 1, 90)]))
        self.assertNotIn("hook_to", action)

    def test_rescue_in_danger_then_hold_without_dropping_purchases(self):
        me = unit()
        ally = unit(2, 0, 64)
        ally.update(hp=180, layer=2)
        obs = observation(me, [ally])
        first = self.policy.choose_action(obs)
        self.assertEqual(first["hook_to"], [64, 40])
        self.assertEqual(first["walk_to"], [36, 40])
        obs["tick"] += 1
        me["points"] = 1
        second = self.policy.choose_action(obs)
        self.assertEqual(second["walk_to"], [36, 40])
        self.assertEqual(second["buy_upgrade"], [1])
        self.assertNotIn("halt", second)

    def test_preserves_a_teammates_existing_rescue(self):
        ally = unit(2, 0, 64)
        ally.update(layer=2, hp=180, hooked=True)
        hook = dict(owner_id=3, team=0, x=64, y=40, flying=False, victim=2)
        action = self.policy.choose_action(observation(others=[ally, unit(3, 0, 30, 80)], hooks=[hook]))
        self.assertNotIn("hook_to", action)

    def test_does_not_rescue_a_healthy_rune_swimmer(self):
        ally = unit(2, 0, 64)
        ally["layer"] = 2
        action = self.policy.choose_action(observation(others=[ally]))
        self.assertNotIn("hook_to", action)

    def test_only_one_bot_answers_a_rally(self):
        a, b, caller = unit(), unit(2, 0, 36, 90), unit(3, 0, 20, 60)
        obs = observation(a, [b, caller])
        obs["ally_ping"] = dict(by=3, age=1, x=32, y=30)
        self.assertEqual(self.policy.choose_action(obs)["walk_to"], [32, 30])
        other = observation(b, [a, caller])
        other["ally_ping"] = obs["ally_ping"]
        self.assertNotEqual(BasePolicy().choose_action(other)["walk_to"], [32, 30])

    def test_ward_trip_yields_to_low_hp_and_rot(self):
        me = unit()
        me["item_ranks"][4] = 1
        me["hp"] = 200
        self.assertEqual(self.policy.choose_action(observation(me))["walk_to"], [25, 30])
        me["hp"] = 840
        ally = unit(2, 0, 40)
        ally["rot"] = True
        action = self.policy.choose_action(observation(me, [ally]))
        self.assertEqual(action["walk_to"][0], 25)

    def test_ward_placement_on_both_banks(self):
        for team in (0, 1):
            me = unit(team=team, x=47 if team == 0 else 81)
            me["item_ranks"][4] = 1
            self.assertEqual(self.policy.choose_action(observation(me))["place_ward"], [79 if team == 0 else 49, 40])

    def test_observation_is_not_mutated(self):
        obs = observation()
        obs["self"].update(points=8, gold=44, in_shop=True)
        before = copy.deepcopy(obs)
        self.policy.choose_action(obs)
        self.assertEqual(obs, before)

    def test_memory_resets_for_a_new_episode(self):
        self.policy.choose_action(observation(others=[unit(4, 1, 90)]))
        obs = observation()
        obs["tick"] = 0
        self.policy.choose_action(obs)
        self.assertIsNone(self.policy.last_enemy)


class SupportOpportunityTest(unittest.TestCase):
    def test_safe_heal_on_either_bank_holds_the_healer(self):
        for team in (0, 1):
            x = 36 if team == 0 else 92
            me, ally = unit(1, team, x, 40), unit(2, team, x, 56)
            ally["hp"] = 500
            policy = BasePolicy(heal_allies=True, trace=True)
            action = policy.choose_action(observation(me, [ally]))
            self.assertEqual(action["hook_to"], [x, 56])
            self.assertEqual(action["walk_to"], [x, 40])
            self.assertEqual(policy.events[-1]["event"], "heal_request")

    def test_healing_has_one_owner(self):
        a, b, recipient = unit(1, x=32, y=40), unit(2, x=32, y=64), unit(3, x=36, y=52)
        recipient["hp"] = 500
        intents = []
        for me, others in [(a, [b, recipient]), (b, [a, recipient])]:
            policy = BasePolicy(heal_allies=True, trace=True)
            policy.choose_action(observation(me, others))
            intents.extend(policy.events)
        self.assertEqual(len(intents), 1)
        self.assertEqual(intents[0]["healer"], 1)

    def test_healing_declines_unsafe_or_wasteful_recipients(self):
        for changes in [dict(hp=800), dict(shield=50), dict(hooked=True), dict(layer=2), dict(rot=True), dict(x=20)]:
            me, ally = unit(), unit(2, x=36, y=56)
            ally.update(hp=500, **changes) if "hp" not in changes else ally.update(**changes)
            policy = BasePolicy(heal_allies=True, trace=True)
            policy.choose_action(observation(me, [ally]))
            self.assertFalse(any(e["event"] == "heal_request" for e in policy.events), changes)

    def test_enemy_or_hook_near_recipient_blocks_heal(self):
        me, ally = unit(), unit(2, x=36, y=56)
        ally["hp"] = 500
        for enemies, hooks in [([unit(4, 1, 52, 70)], []),
                               ([], [dict(owner_id=4, team=1, x=50, y=70, flying=True, victim=0)])]:
            policy = BasePolicy(heal_allies=True, trace=True)
            policy.choose_action(observation(me, [ally, *enemies], hooks))
            self.assertFalse(policy.events)

    def test_close_enemy_and_caught_enemy_keep_priority(self):
        me, ally = unit(), unit(2, x=36, y=56)
        ally["hp"] = 500
        for enemy in [unit(4, 1, 48, 40), dict(unit(4, 1, 86, 40), hooked=True)]:
            policy = BasePolicy(heal_allies=True, trace=True)
            action = policy.choose_action(observation(me, [ally, enemy]))
            self.assertIn("hook_to", action)
            self.assertFalse(policy.events)

    def test_nominal_readiness_does_not_heal_with_an_active_hook(self):
        me, ally = unit(), unit(2, x=36, y=56)
        ally['hp'] = 500
        hook = dict(owner_id=1, team=0, x=75, y=40, flying=False, victim=0)
        policy = BasePolicy(heal_allies=True, trace=True)
        policy.choose_action(observation(me, [ally], [hook]))
        self.assertFalse(policy.events)
        self.assertEqual(policy.rescue_until, 0)

    def test_spacing_one_collector_and_separated_targets(self):
        for team in (0, 1):
            players = [unit(i + 1, team, 36 if team == 0 else 92, y) for i, y in enumerate([40, 64, 88])]
            ys = []
            for me in players:
                obs = observation(me, [p for p in players if p is not me])
                obs["rune_next"] = dict(soon=100, x=64, y=48)
                action = BasePolicy(spread_fishing=True).choose_action(obs)
                ys.append(action["walk_to"][1])
            self.assertEqual(sum(y == 48 for y in ys), 1)
            self.assertGreaterEqual(min(abs(a - b) for i, a in enumerate(ys) for b in ys[i + 1:]), 20)

    def test_fishing_lanes_remain_stable_through_deaths(self):
        players = [unit(i + 1, y=y) for i, y in enumerate([40, 64, 88])]
        policy = BasePolicy(spread_fishing=True)
        obs = observation(players[2], players[:2])
        before = policy.choose_action(obs)["walk_to"]
        players[0]["alive"] = False
        after = policy.choose_action(obs)["walk_to"]
        self.assertEqual(before, after)

    def test_emergency_movement_is_identical_with_spacing(self):
        me = unit()
        me["hp"] = 200
        obs = observation(me, [unit(2, y=55), unit(3, y=90)])
        self.assertEqual(BasePolicy().choose_action(obs), BasePolicy(spread_fishing=True).choose_action(obs))

    def test_both_features_leave_duel_actions_identical(self):
        original, changed = BasePolicy(), BasePolicy(heal_allies=True, spread_fishing=True)
        for tick in range(200, 600):
            me, enemy = unit(), unit(4, 1, 90, 35 + tick % 60)
            obs = observation(me, [enemy])
            obs["tick"] = tick
            obs["rune_next"] = dict(soon=150, x=64, y=48)
            self.assertEqual(original.choose_action(obs), changed.choose_action(obs))

    def test_solo_hold_stays_out_of_the_edge_band(self):
        policy = BasePolicy(trace=True)
        # tick 224 puts player 1's juke at zero, so the solo hold mirrors the enemy's y exactly.
        for enemy_y, expected in [(17, 30), (111, 98), (64, 64)]:
            me = unit(y=max(30, min(98, enemy_y)))
            obs = observation(me, [unit(4, 1, 100, enemy_y)])
            obs["tick"] = 224
            self.assertEqual(policy.choose_action(obs)["walk_to"], [36, expected])
        recorded = [e for e in policy.events if e["event"] == "edge_clamp"]
        self.assertEqual([(e["raw"], e["y"]) for e in recorded], [(17.0, 30.0), (111.0, 98.0)])
        low = unit(y=40)
        obs = observation(low)
        obs["tick"] = 224
        obs["rune_next"] = {"soon": 100, "x": 64, "y": 18}
        self.assertEqual(BasePolicy().choose_action(obs)["walk_to"], [36, 30])

    def test_hook_aimed_elsewhere_is_not_a_threat(self):
        me = unit()
        me["blink_ready"] = True
        enemy = unit(4, 1, 60, 40)
        # The head flies from (60,40) through (52,50): its line passes ~19 tiles from us.
        first = dict(owner_id=4, team=1, x=53.6, y=48, flying=True, victim=0)
        second = dict(owner_id=4, team=1, x=52, y=50, flying=True, victim=0)
        policy = BasePolicy(threat_filter="collision", trace=True)
        far = policy.choose_action(observation(me, [enemy], hooks=[first]))
        self.assertNotIn("blink_to", far)
        obs2 = observation(me, [enemy], hooks=[second])
        obs2["tick"] = 201
        action = policy.choose_action(obs2)
        self.assertNotIn("blink_to", action)
        classes = [(e["cls"], e["src"]) for e in policy.events if e["event"] == "threat_class"]
        self.assertEqual(classes, [("pending", "none"), ("wide", "track")])

    def test_owner_position_after_blink_does_not_steer_the_classification(self):
        me = unit()
        me["blink_ready"] = True
        # Owner threw west along y=41 then blinked north-east: owner->head points south-west.
        enemy = unit(4, 1, 70, 20)
        first = dict(owner_id=4, team=1, x=52, y=41, flying=True, victim=0)
        second = dict(owner_id=4, team=1, x=50, y=41, flying=True, victim=0)
        policy = BasePolicy(threat_filter="collision", trace=True)
        policy.choose_action(observation(me, [enemy], hooks=[first]))
        obs2 = observation(me, [enemy], hooks=[second])
        obs2["tick"] = 201
        action = policy.choose_action(obs2)
        self.assertIn("blink_to", action)
        classes = [(e["cls"], e["src"]) for e in policy.events if e["event"] == "threat_class"]
        self.assertEqual(classes, [("pending", "none"), ("hit", "track")])

    def test_untracked_hook_close_by_is_dodged_at_once(self):
        me = unit()
        me["blink_ready"] = True
        hook = dict(owner_id=4, team=1, x=44, y=40, flying=True, victim=0)
        policy = BasePolicy(threat_filter="collision", trace=True)
        action = policy.choose_action(observation(me, hooks=[hook]))
        self.assertIn("blink_to", action)
        blinks = [e for e in policy.events if e["event"] == "dodge_blink"]
        self.assertEqual(blinks[-1]["cls"], "blind")

    def test_hook_moving_away_is_not_a_threat(self):
        me = unit()
        me["blink_ready"] = True
        policy = BasePolicy(threat_filter="collision", trace=True)
        first = dict(owner_id=4, team=1, x=44, y=40, flying=True, victim=0)
        second = dict(owner_id=4, team=1, x=46, y=40, flying=True, victim=0)
        obs = observation(me, hooks=[first])
        policy.choose_action(obs)
        obs2 = observation(me, hooks=[second])
        obs2["tick"] = 201
        action = policy.choose_action(obs2)
        self.assertNotIn("blink_to", action)
        classes = [(e["cls"], e["src"]) for e in policy.events if e["event"] == "threat_class"]
        self.assertEqual(classes, [("blind", "none"), ("away", "track")])

    def test_default_threat_filter_dodges_every_nearby_hook_like_the_baseline(self):
        me = unit()
        me["blink_ready"] = True
        # Same wide-passing head as the collision test; the distance filter dodges it anyway.
        first = dict(owner_id=4, team=1, x=53.6, y=48, flying=True, victim=0)
        second = dict(owner_id=4, team=1, x=52, y=50, flying=True, victim=0)
        policy = BasePolicy(trace=True)
        self.assertIn("blink_to", policy.choose_action(observation(me, hooks=[first])))
        obs2 = observation(me, hooks=[second])
        obs2["tick"] = 201
        self.assertIn("blink_to", policy.choose_action(obs2))
        blinks = [e["cls"] for e in policy.events if e["event"] == "dodge_blink"]
        self.assertEqual(blinks, ["pending", "wide"])
        far = dict(owner_id=4, team=1, x=70, y=40, flying=True, victim=0)
        obs3 = observation(me, hooks=[far])
        self.assertNotIn("blink_to", BasePolicy().choose_action(obs3))

    def test_hook_closing_on_us_keeps_the_dodge(self):
        me = unit()
        me["blink_ready"] = True
        policy = BasePolicy(threat_filter="collision", trace=True)
        first = dict(owner_id=4, team=1, x=52, y=41, flying=True, victim=0)
        second = dict(owner_id=4, team=1, x=50, y=41, flying=True, victim=0)
        policy.choose_action(observation(me, hooks=[first]))
        obs2 = observation(me, hooks=[second])
        obs2["tick"] = 201
        action = policy.choose_action(obs2)
        self.assertIn("blink_to", action)
        self.assertLess(action["blink_to"][0], me["x"])
        blinks = [e for e in policy.events if e["event"] == "dodge_blink"]
        self.assertEqual(blinks[-1]["cls"], "hit")


if __name__ == "__main__":
    unittest.main()
