"""Behavioral checks for the Base port consumed by the live JSON host."""

import copy
import unittest
from collections import deque

from coworld.player.base import LEAD_DIVISOR, BasePolicy


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


def seen_twice(policy, me, hook, step=(-0.8, 0.0), others=()):
    """Feed the hook on two consecutive ticks (the live host reports every tick)."""
    earlier = dict(hook, x=hook["x"] - step[0], y=hook["y"] - step[1])
    before = observation(me, others, [earlier])
    before["tick"] = 199
    policy.choose_action(before)
    return policy.choose_action(observation(me, others, [hook]))


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
        action = seen_twice(self.policy, me, hook, step=(0.8, 0.0))
        self.assertGreater(action["blink_to"][0], me["x"])

    def test_walking_dodge_starts_at_first_sight_but_blink_waits(self):
        me = unit()
        me["blink_ready"] = True
        far = dict(owner_id=4, team=1, x=72, y=46, flying=True, victim=0)  # 36.5 tiles out, over the river
        policy = BasePolicy(trace=True)
        action = seen_twice(policy, me, far)  # flying due west along y=46: we are 6 tiles north of the line
        self.assertEqual(action["walk_to"], [34, 30])
        self.assertNotIn("blink_to", action)
        self.assertEqual([(e["event"], e["tick"], e["dist"], e["side"], e["off"], e["line"]) for e in policy.events],
                         [("threat_seen", 200, 36.5, -1, 6.0, True)])
        beyond = dict(far, x=78)  # 42.4 tiles: not yet lit for us
        self.assertEqual(seen_twice(BasePolicy(), me, beyond)["walk_to"][0], 36)
        near = dict(far, x=54)
        self.assertIn("blink_to", seen_twice(BasePolicy(), me, near))

    def test_dodge_side_runs_away_from_the_flight_line(self):
        me = unit()
        # A led throw: the head is level with us but the line passes 5 tiles south of us.
        led = dict(owner_id=4, team=1, x=72, y=40, flying=True, victim=0)
        policy = BasePolicy(trace=True)
        action = seen_twice(policy, me, led, step=(-0.8, 0.1))  # heading (-0.8, +0.1): line reaches y=44.5 at x=36
        self.assertEqual(action["walk_to"], [34, 30])  # north, away from the line (head rule would also say north)
        mirrored = seen_twice(BasePolicy(), me, led, step=(-0.8, -0.1))  # line passes north of us
        self.assertEqual(mirrored["walk_to"], [34, 50])  # south, although the head rule says north (head.y == me.y)
        self.assertEqual(policy.events[0]["line"], True)
        self.assertAlmostEqual(policy.events[0]["off"], 4.5, places=1)
        # Dead-on line: fall back to the head rule (hook slightly south of us -> run north).
        dead_on = dict(led, y=40.3)
        policy = BasePolicy(trace=True)
        self.assertEqual(seen_twice(policy, me, dead_on)["walk_to"], [34, 30])
        self.assertEqual(policy.events[0]["line"], False)
        # The edge clamp still wins over the line.
        low = unit(y=18)
        self.assertEqual(seen_twice(BasePolicy(), low, dict(led, y=18), step=(-0.8, -0.1))["walk_to"], [34, 28])

    def test_first_lit_tick_waits_for_a_heading(self):
        me = unit()
        me["blink_ready"] = True
        far = dict(owner_id=4, team=1, x=72, y=46, flying=True, victim=0)
        policy = BasePolicy(trace=True)
        first = policy.choose_action(observation(me, hooks=[far]))
        self.assertEqual(first["walk_to"][0], 36)  # not dodging yet: keeps the hold order
        self.assertEqual(policy.events, deque(maxlen=256))
        self.assertNotIn("blink_to", BasePolicy().choose_action(observation(me, hooks=[dict(far, x=54)])))
        # A hook that never yields a heading (only seen once, then lost) falls back after two ticks.
        policy = BasePolicy(trace=True)
        for tick, hook in ((200, far), (201, dict(far, owner_id=5, x=70.4)), (202, dict(far, owner_id=6, x=69.6))):
            obs = observation(me, hooks=[hook])
            obs["tick"] = tick
            action = policy.choose_action(obs)
        self.assertEqual(action["walk_to"], [34, 30])
        self.assertEqual((policy.events[0]["tick"], policy.events[0]["line"], policy.events[0]["off"]), (202, False, None))

    def test_outgunned_on_the_enemy_bank_blinks_toward_home(self):
        for team, x, enemy_x, landing in ((0, 92, 96, [72.0, 40.0]), (1, 36, 32, [56.0, 40.0])):
            me = unit(team=team, x=x)
            me.update(hp=600, layer=1 - team, blink_ready=True)
            enemy = unit(4, 1 - team, enemy_x)
            obs = observation(me, [enemy])
            self.assertNotIn("blink_to", BasePolicy().choose_action(obs))
            obs["game_version"] = 36
            action = BasePolicy().choose_action(obs)
            self.assertEqual(action["blink_to"], landing)
            self.assertNotIn("attack_target", action)
            self.assertFalse(action.get("rot", False))
        me = unit(x=73, y=60)
        me.update(hp=600, layer=1, blink_ready=True)
        obs = observation(me, [unit(4, 1, 80, 60)])
        obs["game_version"] = 36
        policy = BasePolicy(trace=True)
        self.assertEqual(policy.choose_action(obs)["blink_to"], [56.0, 60.0])
        self.assertEqual([e["event"] for e in policy.events], ["bank_escape"])
        self.assertEqual(policy.events[0]["via"], "fountain")

    def test_bank_escape_respects_the_rot_blink_lock(self):
        # An enemy Rot disk within 8 tiles makes Blink impossible: brawl as v4.
        me = unit(x=92)
        me.update(hp=600, layer=1, blink_ready=True)
        enemy = unit(4, 1, 96)
        enemy["rot"] = True
        obs = observation(me, [enemy])
        obs["game_version"] = 36
        action = BasePolicy().choose_action(obs)
        self.assertNotIn("blink_to", action)
        self.assertEqual(action["attack_target"], 4)
        # Our own Rot is switched off first (the host reports blink_ready
        # false inside our own disk); the hop follows once it is off.
        me.update(rot=True, blink_ready=False)
        enemy["rot"] = False
        obs = observation(me, [enemy])
        obs["game_version"] = 36
        policy = BasePolicy(trace=True)
        action = policy.choose_action(obs)
        self.assertNotIn("blink_to", action)
        self.assertNotIn("attack_target", action)
        self.assertIs(action["rot"], False)
        me.update(rot=False, blink_ready=True)
        obs = observation(me, [enemy])
        obs.update(game_version=36, tick=201)
        self.assertEqual(policy.choose_action(obs)["blink_to"], [72.0, 40.0])
        # A Blink spent recently keeps Rot on (no pointless switch-off).
        obs = observation(me, [enemy])
        obs.update(game_version=36, tick=202, accepted={"blink_to": True})
        me.update(rot=True, blink_ready=False, x=92)
        action = policy.choose_action(obs)
        self.assertNotIn("rot", action)
        self.assertEqual(action["attack_target"], 4)
        self.assertEqual([e["event"] for e in policy.events], ["bank_escape"])

    def test_refused_bank_escape_falls_back_to_the_brawl(self):
        me = unit(x=92)
        me.update(hp=600, layer=1, blink_ready=True)
        enemy = unit(4, 1, 96)
        obs = observation(me, [enemy])
        obs["game_version"] = 36
        policy = BasePolicy(trace=True)
        self.assertEqual(policy.choose_action(obs)["blink_to"], [72.0, 40.0])
        # The host rejected the hop (e.g. a palisade on the ray): brawl for
        # a second instead of re-sending it every tick.
        obs = observation(me, [enemy])
        obs.update(game_version=36, tick=201, accepted={"blink_to": "rejected"})
        action = policy.choose_action(obs)
        self.assertNotIn("blink_to", action)
        self.assertEqual(action["attack_target"], 4)
        self.assertIs(action["rot"], True)
        self.assertEqual([e["event"] for e in policy.events], ["bank_escape", "bank_escape_refused"])
        self.assertEqual(policy.events[1]["reason"], "rejected")
        obs = observation(me, [enemy])
        obs.update(game_version=36, tick=220)
        self.assertNotIn("blink_to", policy.choose_action(obs))
        obs = observation(me, [enemy])
        obs.update(game_version=36, tick=234)
        self.assertEqual(policy.choose_action(obs)["blink_to"], [72.0, 40.0])

    def test_favourable_enemy_bank_brawl_is_kept(self):
        for my_hp, enemy_hp in ((840, 840), (600, 100)):
            me = unit(x=92)
            me.update(hp=my_hp, layer=1, blink_ready=True)
            enemy = unit(4, 1, 96)
            enemy["hp"] = enemy_hp
            obs = observation(me, [enemy])
            obs["game_version"] = 36
            action = BasePolicy().choose_action(obs)
            self.assertNotIn("blink_to", action)
            self.assertEqual(action["attack_target"], 4)
        me = unit(x=92)
        me.update(hp=600, layer=1, hooked=True)
        enemy = unit(4, 1, 96)
        policy = BasePolicy(trace=True)
        policy.choose_action(observation(me, [enemy]))
        me["hooked"] = False
        obs = observation(me, [enemy])
        obs["tick"] = 201
        self.assertEqual(policy.choose_action(obs)["attack_target"], 4)
        landed = [e for e in policy.events if e["event"] == "pull_landed"]
        self.assertEqual(len(landed), 1)
        self.assertEqual((landed[0]["blink_ready"], landed[0]["enemy_hp"], landed[0]["own_land"]), (False, 840, False))

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

    def test_long_hook_lead_is_applied_and_traced(self):
        policy = BasePolicy(trace=True)
        enemy = unit(4, 1, 90, 40)
        obs = observation(others=[enemy])
        policy.choose_action(obs)
        obs["tick"] += 8
        enemy["y"] += 4
        aim = policy.choose_action(obs)["hook_to"]
        self.assertAlmostEqual(aim[1], 44 + 4 * 54 / LEAD_DIVISOR)
        recorded = [e for e in policy.events if e["event"] == "hook_lead"]
        self.assertEqual(recorded, [dict(event="hook_lead", tick=208, span=54.0, lead=round(4 * 54 / LEAD_DIVISOR, 1), v8=4.0)])
        # The speed upgrade shortens the lead; a short brawl hook is not traced.
        obs["self"]["upgrades"] = [0, 0, 3, 0]
        obs["tick"] += 8
        enemy["y"] += 4
        self.assertAlmostEqual(policy.choose_action(obs)["hook_to"][1], 48 + 4 * 54 / (LEAD_DIVISOR + 3))
        close = unit(4, 1, 50, 40)
        obs = observation(others=[close])
        obs["tick"] = 224
        policy.choose_action(obs)
        obs["tick"] += 8
        close["y"] += 4
        policy.choose_action(obs)
        self.assertEqual(len([e for e in policy.events if e["event"] == "hook_lead"]), 2)

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
        hook = dict(owner_id=4, team=1, x=54, y=40, flying=True, victim=0)
        hop = seen_twice(self.policy, me, hook)["blink_to"]
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
            self.assertFalse(any(e["event"] == "heal_request" for e in policy.events))

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


if __name__ == "__main__":
    unittest.main()
