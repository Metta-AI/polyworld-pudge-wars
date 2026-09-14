"""Behavioral contracts for the semantic policy, using explicit expected actions."""
import asyncio
from copy import deepcopy
from dataclasses import asdict
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from coaching.policy import PolicyError, Rule, compile_policy, decide, initial_policy, interpret, readable
from coaching.realtime import RealtimeCall, session_config
from coaching.server import Demo, load_opponent


def observation(tick=100):
    def player(id, team, x, y, **extra):
        return {"id": id, "slot": id - 1, "team": team, "x": x, "y": y, "hp": 800, "max_hp": 840,
                "alive": True, "shield": 0, "hooked": False, "hook_ready": True, "in_river": False,
                "home_x": 20 if team == 0 else 108, "home_y": 40, **extra}
    people = [player(1, 0, 35, 60), player(2, 0, 44, 40), player(3, 1, 66, 40), player(4, 1, 76, 64)]
    return {"tick": tick, "self": people[1], "play_west_max": 52, "play_east_min": 76,
            "score": {"west": 0, "east": 0}, "visible": {"pudges": people,
            "hooks": [{"owner_id": 1, "team": 0, "victim": 4, "flying": False, "x": 76, "y": 64}]}}


class PolicyBehavior(unittest.TestCase):
    def test_live_opponents_load_sibling_dependencies_with_separate_memory(self):
        first, second = load_opponent(2), load_opponent(3)
        self.assertEqual(first.PERSONALITY, "rusher")
        self.assertEqual(second.PERSONALITY, "rusher")
        self.assertIsNot(first, second)
        first._tracks[123] = "first seat only"
        self.assertNotIn(123, second._tracks)
        self.assertIsNot(first._base, second._base)

    def setUp(self):
        self.policy = compile_policy(initial_policy().document())
        self.obs = observation()

    def lesson(self, text):
        result = interpret(text, self.policy, self.obs, 1)
        self.assertEqual(result.status, "compiled", result.message)
        return result.policy

    def test_catch_priority_changes_target_and_preserves_movement(self):
        before, _, trace = decide(self.policy, self.obs, 1)
        after, _, changed = decide(self.lesson("follow up on my hooks"), self.obs, 1)
        self.assertEqual(before["hook_to"], [66, 40])
        self.assertEqual(after["hook_to"], [76, 64])
        self.assertEqual(before["walk_to"], after["walk_to"])
        self.assertEqual(changed["selected"]["hook"], "follow_up")

    def test_no_catch_is_unchanged(self):
        self.obs["visible"]["hooks"] = []
        self.assertEqual(decide(self.policy, self.obs, 1)[0], decide(self.lesson("follow up on my hooks"), self.obs, 1)[0])

    def test_wait_releases_when_flight_ends(self):
        policy = self.lesson("wait for my hook")
        self.obs["visible"]["hooks"][0].update(victim=0, flying=True)
        action, memory, trace = decide(policy, self.obs, 1)
        self.assertNotIn("hook_to", action)
        self.assertEqual(trace["selected"]["hook"], "wait_for_you")
        self.obs["visible"]["hooks"] = []
        self.assertEqual(decide(policy, self.obs, 1, memory)[0]["hook_to"], [66, 40])

    def test_retreat_has_explicit_priority(self):
        policy = self.lesson("follow up on my hooks")
        self.obs["self"]["hp"] = 200
        action, _, trace = decide(policy, self.obs, 1)
        self.assertEqual(action, {"walk_to": [20, 40]})
        self.assertEqual(trace["selected"]["movement"], "retreat")

    def test_target_context_is_not_an_oracle(self):
        self.obs["visible"]["pudges"] = self.obs["visible"]["pudges"][:2]
        self.assertNotIn("hook_to", decide(self.lesson("follow up on my hooks"), self.obs, 1)[0])

    def test_focus_ambiguity_expiry_and_death(self):
        self.obs["visible"]["hooks"] = []
        self.assertEqual(interpret("focus him", self.policy, self.obs, 1).status, "clarify")
        policy = interpret("focus him", self.policy, self.obs, 1, selected_id=4).policy
        self.assertEqual(decide(policy, self.obs, 1)[0]["hook_to"], [76, 64])
        self.obs["tick"] = 356
        self.assertEqual(decide(policy, self.obs, 1)[0]["hook_to"], [66, 40])
        self.obs["tick"] = 101
        self.obs["visible"]["pudges"][3]["alive"] = False
        self.assertEqual(decide(policy, self.obs, 1)[0]["hook_to"], [66, 40])

    def test_hook_availability_includes_returning_own_hook(self):
        self.obs["visible"]["hooks"].append({"owner_id": 2, "team": 0, "victim": 0, "flying": False})
        action, _, trace = decide(self.policy, self.obs, 1)
        self.assertNotIn("hook_to", action)
        self.assertIn("hook unavailable", str(trace))

    def test_friendly_corridor_blocks_throw(self):
        self.obs["visible"]["pudges"][0].update(x=55, y=40)
        action, _, trace = decide(self.policy, self.obs, 1)
        self.assertNotIn("hook_to", action)
        self.assertIn("teammate in the straight throw corridor", str(trace))

    def test_description_uses_executable_threshold(self):
        policy = self.lesson("retreat below 50 percent")
        self.obs["self"]["hp"] = 400
        self.assertEqual(decide(policy, self.obs, 1)[0]["walk_to"], [20, 40])
        self.assertIn("50%", next(r["text"] for r in readable(policy) if r["id"] == "retreat"))

    def test_negated_and_compound_instructions_are_not_partial_matches(self):
        for text in ["don't follow up on my hooks and chase him", "don't focus him", "wait for my hook actually don't wait"]:
            result = interpret(text, self.policy, self.obs, 1)
            self.assertIsNone(result.policy)

    def test_unsupported_semantics_and_priority_collisions_rejected(self):
        for change in [{"when": "enemy_secretly_behind_wall"}, {"priority": 10}, {"intent": "walk"}]:
            doc = self.policy.document()
            doc["rules"] = [dict(r) for r in doc["rules"]]
            doc["rules"][-1].update(change)
            with self.assertRaises(PolicyError): compile_policy(doc)

    def test_deterministic_roundtrip(self):
        policy = self.lesson("follow up on my hooks from now on")
        other = compile_policy(json.loads(json.dumps(policy.document())))
        self.assertEqual(other.fingerprint, policy.fingerprint)
        self.assertEqual(decide(other, self.obs, 1), decide(policy, self.obs, 1))

    def test_east_bank_moves_to_correct_side(self):
        self.obs["self"].update(team=1, x=84)
        self.obs["visible"]["pudges"][0]["team"] = 1
        action = decide(self.policy, self.obs, 1)[0]
        self.assertGreaterEqual(action["walk_to"][0], 76)


class Transactions(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.demo = Demo()
        self.demo.policy = self.demo.remembered = compile_policy(initial_policy().document())
        self.demo.remembered_path = Path(self.directory.name) / "remembered.json"
        self.demo.run_dir = Path(self.directory.name)
        self.demo.phase = "playing"
        self.demo.coach_id = 1
        self.demo.contexts.append({"id": "match:100", "obs": observation(), "trace": {}, "selected_id": 4})

    async def asyncTearDown(self):
        await self.demo.stop_match()
        self.directory.cleanup()

    def commit(self, text):
        context = self.demo.context_bundle()
        candidate = interpret(text, self.demo.policy, context["speech_time"], 1, selected_id=4).policy
        result = self.demo.stage(candidate, context, text)
        self.demo.activate_pending(context["current_tick"] + 1)
        return result

    async def test_match_threshold_does_not_become_durable(self):
        self.commit("retreat below 50 percent")
        self.assertEqual(self.demo.policy.retreat_percent, 50)
        self.demo.reset_policy_for_match()
        self.assertEqual(self.demo.policy.retreat_percent, 35)

    async def test_persistent_deletion_survives_rematch(self):
        self.commit("wait for my hook from now on")
        self.commit("stop waiting from now on")
        self.demo.reset_policy_for_match()
        self.assertNotIn("wait_for_you", {r.id for r in self.demo.policy.rules})

    async def test_saving_one_lesson_does_not_save_other_match_edits(self):
        self.commit("retreat below 50 percent")
        self.commit("follow up on my hooks from now on")
        self.demo.reset_policy_for_match()
        self.assertEqual(self.demo.policy.retreat_percent, 35)
        self.assertIn("follow_up", {r.id for r in self.demo.policy.rules})
        self.assertEqual(json.loads(self.demo.remembered_path.read_text())["retreat_percent"], 35)

    async def test_expired_focus_does_not_block_unrelated_edits(self):
        self.commit("focus him")
        self.demo.contexts.append({"id": "match:400", "obs": observation(400), "trace": {}})
        self.commit("follow up on my hooks")
        self.assertIn("follow_up", {r.id for r in self.demo.policy.rules})

    async def test_undo_restores_the_durable_policy_too(self):
        self.commit("retreat below 50 percent from now on")
        await self.demo.tool_call("rollback_policy", {"base_revision": self.demo.policy.revision}, "undo")
        self.demo.activate_pending(102)
        self.demo.reset_policy_for_match()
        self.assertEqual(self.demo.policy.retreat_percent, 35)

    async def test_temporary_entity_binding_is_bounded_and_visible(self):
        for target, expiry in [(4, 1000), (99, 200)]:
            with self.assertRaises(PolicyError):
                await self.demo.tool_call("patch_policy", {
                    "base_revision": 1, "context_id": "match:100", "instruction": "focus him",
                    "upsert_rules": [asdict(Rule("focus", "hook", 20, "target_visible", "selected_enemy",
                                               "hook", "temporary", expiry, target))],
                    "remove_rule_ids": [], "scope": "match"}, f"bad-{target}")
            self.assertIsNone(self.demo.pending)

    async def test_duplicate_patch_returns_original_receipt(self):
        args = {"base_revision": 1, "context_id": "match:100", "instruction": "retreat below 50%",
                "upsert_rules": [], "remove_rule_ids": [], "retreat_percent": 50, "scope": "match"}
        first = await self.demo.tool_call("patch_policy", args, "same-call")
        self.demo.activate_pending(101)
        second = await self.demo.tool_call("patch_policy", args, "same-call")
        self.assertEqual(first, second)
        self.assertEqual(len(self.demo.previous), 1)

    async def test_background_comparison_finishes_and_records_evidence(self):
        receipt = self.commit("follow up on my hooks")
        await asyncio.gather(*list(self.demo.tasks))
        report = self.demo.jobs[receipt["job_id"]]
        self.assertEqual(report["status"], "complete")
        self.assertEqual(report["changed_hooks"], 1)
        self.assertEqual(report["competitive"], "untested")
        self.assertFalse(self.demo.error)
        self.assertEqual(self.demo.timeline[0]["kind"], "background_check")

    async def test_stale_revision_and_expired_context_do_not_mutate(self):
        demo = Demo()
        with self.assertRaises(PolicyError):
            await demo.tool_call("rollback_policy", {"base_revision": 0}, "stale")
        self.assertEqual(demo.policy.revision, 1)
        demo.contexts.append({"id": "match:100", "obs": observation(), "trace": {}})
        with self.assertRaises(PolicyError): demo.context_bundle("another-match:100")

    async def test_async_tools_do_not_block_the_voice_reader(self):
        release = asyncio.Event()
        class Owner:
            voice_status = ""
            context_number = 0
            def latest_context_id(self):
                self.context_number += 1
                return f"context:{self.context_number}"
            def context_bundle(self, anchor): return {"status": "context", "anchor": anchor}
            async def tool_call(self, name, args, call_id):
                await release.wait()
                return {"status": "slow-complete"}
        class Socket:
            def __init__(self): self.queue, self.sent = asyncio.Queue(), []
            def __aiter__(self): return self
            async def __anext__(self): return await self.queue.get()
            async def send_json(self, item): self.sent.append(item)
            async def close(self): pass
            async def event(self, **item): await self.queue.put(SimpleNamespace(type=1, data=json.dumps(item)))
        call = RealtimeCall(Owner(), None)
        call.ws = Socket()
        reader = asyncio.create_task(call.listen())
        await call.ws.event(type="input_audio_buffer.speech_started")
        await call.ws.event(type="response.created", response={"id": "response:1"})
        await call.ws.event(type="input_audio_buffer.speech_started")
        await call.ws.event(type="response.function_call_arguments.done", call_id="slow", name="patch_policy", arguments="{}")
        await call.ws.event(type="response.function_call_arguments.done", response_id="response:1", call_id="fast", name="get_game_context", arguments="{}")
        for _ in range(10): await asyncio.sleep(0)
        outputs = [m["item"] for m in call.ws.sent if m["type"] == "conversation.item.create"]
        self.assertEqual([o["call_id"] for o in outputs], ["fast"])
        self.assertEqual(json.loads(outputs[0]["output"])["anchor"], "context:1")
        release.set()
        for _ in range(10): await asyncio.sleep(0)
        outputs = [m["item"] for m in call.ws.sent if m["type"] == "conversation.item.create"]
        self.assertEqual([o["call_id"] for o in outputs], ["fast", "slow"])
        await call.ws.event(type="input_audio_buffer.speech_stopped")
        await call.ws.event(type="response.created", response={"id": "response:2"})
        await call.ws.event(type="response.done")
        for _ in range(10): await asyncio.sleep(0)
        self.assertFalse(any(m["type"] == "response.create" for m in call.ws.sent),
                         "The automatic voice response already consumed those outputs.")
        reader.cancel()
        await asyncio.gather(reader, return_exceptions=True)
        await call.close()

    async def test_realtime_config_uses_current_model_and_server_tools(self):
        with patch.dict("os.environ", {"OPENAI_REALTIME_MODEL": "gpt-realtime-2.1"}):
            config = session_config()
        self.assertEqual(config["model"], "gpt-realtime-2.1")
        self.assertTrue(config["parallel_tool_calls"])
        self.assertIn("patch_policy", [t["name"] for t in config["tools"]])

    async def test_realtime_sdp_setup_attaches_authenticated_sideband_and_hangs_up(self):
        class Response:
            status = 201
            headers = {"Location": "/v1/realtime/calls/rtc_test123"}
            async def text(self): return "sdp-answer"
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Socket:
            closed = False
            def __aiter__(self): return self
            async def __anext__(self):
                await asyncio.Event().wait()
            async def close(self): self.closed = True
        class Client:
            def __init__(self): self.requests, self.socket = [], Socket()
            def post(self, url, **kwargs):
                self.requests.append((url, kwargs))
                return Response()
            async def ws_connect(self, url, **kwargs):
                self.requests.append((url, kwargs))
                return self.socket
        client = Client()
        call = RealtimeCall(self.demo, client)
        with patch.dict("os.environ", {"OPENAI_API_KEY": "test-credential"}):
            self.assertEqual(await call.connect("sdp-offer"), "sdp-answer")
            self.assertEqual(client.requests[0][0], "https://api.openai.com/v1/realtime/calls")
            self.assertEqual(client.requests[1][0], "wss://api.openai.com/v1/realtime?call_id=rtc_test123")
            self.assertEqual(client.requests[1][1]["headers"]["Authorization"], "Bearer test-credential")
            await call.close()
            self.assertTrue(client.socket.closed)
            self.assertTrue(client.requests[-1][0].endswith("/rtc_test123/hangup"))

    async def test_realtime_reports_exhausted_credits_without_echoing_provider_payload(self):
        class Response:
            status = 429
            async def text(self):
                return json.dumps({"error": {"code": "credit_balance_exhausted", "message": "private provider details"}})
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
        class Client:
            def post(self, *args, **kwargs): return Response()
        call = RealtimeCall(self.demo, Client())
        with patch.dict("os.environ", {"OPENAI_API_KEY": "test-credential"}):
            with self.assertRaisesRegex(ValueError, "no available API credits/quota") as result:
                await call.connect("sdp-offer")
        self.assertNotIn("private provider details", str(result.exception))
        self.assertFalse(call.call_id)


if __name__ == "__main__": unittest.main()
