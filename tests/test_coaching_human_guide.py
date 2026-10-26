"""Read-only coaching, inference routing, fog-safe tracking and async lifecycle."""
import asyncio
from copy import deepcopy
import json
import unittest
from unittest.mock import patch

from aiohttp import ClientSession, web
from aiohttp.test_utils import TestServer

from coaching.human_guide import HumanGuide, choice_answer, human_view, options


def scene(tick=100):
    def player(identifier, team, x, y, **extra):
        return dict(id=identifier, slot=identifier - 1, team=team, x=x, y=y, hp=800,
                    max_hp=1000, alive=True, hook_ready=True, blink_ready=True, hooked=False,
                    home_x=20 if team == 0 else 108, home_y=40, upgrades=[0, 0, 0, 0], **extra)
    players = [player(1, 0, 40, 40), player(2, 0, 42, 65), player(3, 1, 78, 40), player(4, 1, 100, 85)]
    return dict(tick=tick, self=players[1], accepted={"hook_to": True}, print="private teammate trace",
                score={"west": 2, "east": 1}, visible=dict(pudges=players, hooks=[], props=[]))


def response_for(body, action="hook_3", confidence=.95):
    answers = {}
    for key, question in body["questions"].items():
        selected = action if key == "action" else "coordinate" if key == "strategy" else "east_north"
        if selected not in question["criteria"]:
            selected = "none" if "none" in question["criteria"] else "unknown"
        others = max(1, len(question["criteria"]) - 1)
        answers[key] = dict(type="choice", choice=selected, confidence=confidence,
                            probabilities={c: .9 if c == selected else .1 / others for c in question["criteria"]})
    return dict(model="jev-test", answers=answers)


class GuideContracts(unittest.TestCase):
    def setUp(self):
        self.now = 10.0
        self.guide = HumanGuide(api_key="", clock=lambda: self.now)
        self.obs = scene()
        self.guide.observe(self.obs, "match-a")

    def test_human_perspective_uses_only_shared_visible_data_and_never_mutates_it(self):
        original = deepcopy(self.obs)
        projected = human_view(self.obs)
        self.assertEqual(projected["self"]["id"], 1)
        self.assertNotIn("accepted", projected)
        self.assertNotIn("print", projected)
        self.assertNotIn("hook_ready", projected["visible"]["pudges"][2])
        self.assertNotIn("home_x", projected["visible"]["pudges"][2])
        self.assertTrue(projected["self"]["hook_ready"])
        self.guide.view("playing")
        self.assertEqual(original, self.obs)
        self.obs["visible"]["pudges"][0]["team"] = 1
        self.assertIsNone(human_view(self.obs))

    def test_low_health_and_nearby_hooks_override_model(self):
        self.guide.result = {"action": ("hook_3", .99)}
        self.guide.result_tick, self.guide.result_at = 100, 10
        self.obs["visible"]["pudges"][0]["hp"] = 200
        self.guide.observe(self.obs, "match-a")
        action = self.guide.view("playing")["action"]
        self.assertEqual((action["id"], action["source"]), ("retreat", "local"))
        self.obs["visible"]["hooks"] = [dict(team=1, owner_id=3, x=45, y=40, flying=True, victim=0)]
        self.guide.observe(self.obs, "match-a")
        self.assertEqual(self.guide.view("playing")["action"]["id"], "dodge")

    def test_dead_hooked_and_hook_in_flight(self):
        human = self.obs["visible"]["pudges"][0]
        human["alive"] = False
        self.guide.observe(self.obs, "match-a")
        self.assertEqual(self.guide.view("playing")["action"]["id"], "respawn")
        human.update(alive=True, hooked=True)
        self.guide.observe(self.obs, "match-a")
        self.assertEqual(self.guide.view("playing")["action"]["id"], "hooked")
        human["hooked"] = False
        self.obs["visible"]["hooks"] = [dict(team=0, owner_id=1, x=50, y=40, flying=False, victim=0)]
        self.guide.observe(self.obs, "match-a")
        self.assertNotIn("hook_3", self.guide.actions)

    def test_friendly_block_wall_fountain_and_range_suppress_shots(self):
        for blocker in ("ally", "wall", "fountain", "range"):
            obs = scene()
            if blocker == "ally": obs["visible"]["pudges"][1].update(x=60, y=40)
            if blocker == "wall": obs["visible"]["props"] = [dict(kind="wall", x=60, y=40)]
            if blocker == "fountain":
                obs["visible"]["pudges"][0]["y"] = 64
                obs["visible"]["pudges"][2]["y"] = 64
            if blocker == "range": obs["visible"]["pudges"][2]["x"] = 110
            self.assertNotIn("hook_3", options(human_view(obs))[0], blocker)

    def test_confidence_routes_to_direct_tentative_and_local(self):
        for confidence, source, tentative in ((.9, "jev", False), (.7, "jev", True), (.59, "local", False)):
            self.guide.held = None
            self.guide.result = {"action": ("hook_3", confidence)}
            self.guide.result_tick, self.guide.result_at = 100, 10
            action = self.guide.view("playing")["action"]
            self.assertEqual((action["source"], action["tentative"]), (source, tentative))

    def test_target_disappearing_immediately_invalidates_held_cue(self):
        self.guide.result = {"action": ("hook_3", .95)}
        self.guide.result_tick, self.guide.result_at = 100, 10
        self.assertEqual(self.guide.view("playing")["action"]["id"], "hook_3")
        self.obs["tick"] += 1
        self.obs["visible"]["pudges"] = self.obs["visible"]["pudges"][:2]
        self.guide.observe(self.obs, "match-a")
        self.assertNotEqual(self.guide.view("playing")["action"]["id"], "hook_3")

    def test_wall_clock_expiry_pause_finished_and_rematch_clear_advice(self):
        self.now += 3
        self.assertIsNone(self.guide.view("playing")["action"])
        self.guide.observe(self.obs, "match-a")
        self.guide.set_enabled(False)
        self.assertIsNone(self.guide.view("playing")["action"])
        self.guide.set_enabled(True)
        self.assertIsNone(self.guide.view("finished")["action"])
        self.guide.reset("match-b")
        self.assertEqual(self.guide.beliefs.tracks, {})
        self.assertIsNone(self.guide.view("playing")["action"])

    def test_model_choices_validate_confidence_and_full_distribution(self):
        body = self.guide.request_body()
        for corrupt in (lambda a: a.update(confidence=float("nan")), lambda a: a.update(choice="invented"),
                        lambda a: a.update(probabilities={}), lambda a: a.update(confidence=True)):
            payload = response_for(body)
            corrupt(payload["answers"]["action"])
            with self.assertRaises(ValueError): choice_answer(payload, "action", body["questions"]["action"]["criteria"])

    def test_enemy_history_only_retains_sightings_no_hidden_updates(self):
        self.obs["visible"]["pudges"] = self.obs["visible"]["pudges"][:2]
        self.obs["tick"] = 132
        self.guide.observe(self.obs, "match-a")
        enemy = self.guide.view("playing")["intel"]["enemies"][0]
        self.assertFalse(enemy["visible"])
        self.assertEqual(enemy["last_seen"]["x"], 78)
        self.assertEqual(enemy["last_seen"]["tick"], 100)
        self.assertEqual(enemy["age_seconds"], 1)
        self.assertIn("enemy_3_now", self.guide.request_body()["questions"])
        self.assertIn("enemy_3_next", self.guide.request_body()["questions"])
        self.obs["tick"] = 700
        self.guide.observe(self.obs, "match-a")
        self.assertNotIn("enemy_3_now", self.guide.request_body()["questions"])

    def test_visible_positions_override_estimates_and_forecasts_expire(self):
        body = self.guide.request_body()
        self.guide.beliefs.accept(response_for(body), body, 100)
        enemy = self.guide.view("playing")["intel"]["enemies"][0]
        self.assertNotIn("now", enemy["forecasts"])
        self.assertEqual(enemy["forecasts"]["next"]["probabilities"]["east_north"], .9)
        self.obs["tick"] = 165
        self.guide.observe(self.obs, "match-a")
        self.assertEqual(self.guide.view("playing")["intel"]["enemies"][0]["forecasts"], {})

    def test_never_seen_enemies_are_not_invented(self):
        self.guide.reset("empty")
        self.obs["visible"]["pudges"] = self.obs["visible"]["pudges"][:2]
        self.guide.observe(self.obs, "empty")
        self.assertEqual(self.guide.view("playing")["intel"]["enemies"], [])
        self.assertFalse(any(k.startswith("enemy_") for k in self.guide.request_body()["questions"]))


class JevTransport(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.now = 10.0
        self.guide = HumanGuide(api_key="test-key", clock=lambda: self.now)
        self.guide.observe(scene(), "a")
        self.guide.viewer_at = self.now
        self.received = []
        self.status = 200
        self.started = asyncio.Event()
        self.release = None
        async def handler(request):
            self.assertEqual(request.headers["Authorization"], "Bearer test-key")
            body = await request.json()
            self.received.append(body)
            self.started.set()
            if self.release: await self.release.wait()
            return web.json_response(response_for(body), status=self.status)
        app = web.Application()
        app.router.add_post("/v1/systemone", handler)
        self.server = TestServer(app)
        await self.server.start_server()
        self.endpoint = patch("coaching.human_guide.ENDPOINT", str(self.server.make_url("/v1/systemone")))
        self.endpoint.start()
        self.client = ClientSession()

    async def asyncTearDown(self):
        self.endpoint.stop()
        await self.client.close()
        await self.server.close()

    async def test_actual_http_request_and_probability_response_reach_view(self):
        await self.guide.evaluate(self.client)
        self.assertEqual(self.guide.status, "connected")
        view = self.guide.view("playing")
        self.assertEqual(view["action"]["source"], "jev")
        self.assertIn("next", view["intel"]["enemies"][0]["forecasts"])
        self.assertEqual(self.received[0]["state"]["observation"]["self"]["id"], 1)
        self.assertNotIn("test-key", json.dumps(view))
        await self.guide.evaluate(self.client)
        self.assertEqual(len(self.received), 1, "one second request cadence")

    async def test_pause_and_inactive_browser_stop_requests(self):
        self.guide.set_enabled(False)
        await self.guide.evaluate(self.client)
        self.guide.set_enabled(True)
        self.now += 4
        self.guide.observe(scene(), "a")
        await self.guide.evaluate(self.client)
        self.assertEqual(len(self.received), 0)

    async def test_rate_limit_backs_off_and_auth_failure_waits_for_retry(self):
        self.status = 429
        await self.guide.evaluate(self.client)
        self.assertEqual(self.guide.status, "unavailable")
        self.now += 1
        await self.guide.evaluate(self.client)
        self.assertEqual(len(self.received), 1)
        self.now += 1
        self.status = 401
        await self.guide.evaluate(self.client)
        self.assertEqual(self.guide.status, "auth_error")
        self.assertEqual(self.guide.retry_at, float("inf"))

    async def test_inflight_old_match_or_paused_answer_is_discarded(self):
        for reset in (lambda: self.guide.reset("b"), lambda: self.guide.set_enabled(False)):
            self.guide = HumanGuide(api_key="test-key", clock=lambda: self.now)
            self.guide.observe(scene(), "a")
            self.guide.viewer_at = self.now
            self.started.clear()
            self.release = asyncio.Event()
            task = asyncio.create_task(self.guide.evaluate(self.client))
            await self.started.wait()
            reset()
            self.release.set()
            await task
            self.assertEqual(self.guide.result, {})
            self.assertEqual(self.guide.beliefs.predictions, {})

    async def test_response_from_old_tick_is_discarded(self):
        self.release = asyncio.Event()
        task = asyncio.create_task(self.guide.evaluate(self.client))
        await self.started.wait()
        self.guide.observe(scene(200), "a")
        self.release.set()
        await task
        self.assertEqual(self.guide.result, {})


if __name__ == "__main__":
    unittest.main()
