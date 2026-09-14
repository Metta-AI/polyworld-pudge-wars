"""Belief interventions, generation contracts and grounded feedback lifecycles."""
import asyncio
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from coaching.policy import PolicyError, compile_policy, decide, initial_policy
from coaching.reasoning import ReasoningLab, evaluate_candidate, load_model, reference_candidate
from coaching.server import Demo
from test_coaching_policy import observation


class ReasoningTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = Path(self.directory.name)
        self.demo = Demo()
        self.demo.reasoning = ReasoningLab(root / "reasoning")
        self.demo.policy = self.demo.remembered = compile_policy(initial_policy().document())
        self.demo.remembered_path = root / "remembered.json"
        self.demo.run_dir = root
        self.demo.phase, self.demo.match_id, self.demo.coach_id = "playing", "test-match", 1
        self.demo.contexts.append({"id": "test-match:100", "obs": observation(), "trace": {}, "selected_id": 4})

    async def asyncTearDown(self):
        await self.demo.stop_match()
        self.directory.cleanup()

    def revise(self, belief="catch_value", confidence=0.8):
        return self.demo.record_reasoning({"kind": "belief", "text": "A grounded human assessment for this test.",
            "subject_id": belief, "confidence": confidence, "context_id": "test-match:100",
            "base_semantic_revision": self.demo.reasoning.model.revision})["generation_request"]

    def evaluate(self, request, variant=0):
        return evaluate_candidate(request, reference_candidate(request, variant), "test-reference", "A complete candidate realizing the belief.")

    async def test_belief_revision_preserves_running_policy_and_has_evidence(self):
        before = self.demo.policy.fingerprint
        request = self.revise()
        self.assertEqual(self.demo.policy.fingerprint, before)
        self.assertIsNone(self.demo.pending)
        belief = self.demo.reasoning.model.belief("catch_value")
        self.assertEqual(belief.confidence, 0.8)
        self.assertEqual(belief.confidence_kind, "human_assessment")
        event = self.demo.reasoning.feedback[-1]
        self.assertEqual(belief.evidence_ids, (event["id"],))
        self.assertEqual(event["observation"]["tick"], 100)
        self.assertEqual(request["parent_hash"], before)
        self.assertEqual(request["status"], "awaiting_generation")
        self.assertEqual(request["evidence"][0]["id"], event["id"])

    async def test_encouragement_has_no_implicit_credit_assignment(self):
        before = self.demo.reasoning.model.fingerprint
        context = self.demo.context_bundle()
        result = self.demo.reasoning.record(kind="encouragement", text="good job, keep going", context=context, base_revision=1)
        self.assertEqual(self.demo.reasoning.model.fingerprint, before)
        self.assertIsNone(self.demo.reasoning.feedback[-1]["subject_id"])
        self.assertIn("No belief", result["message"])

    async def test_explicit_criticism_does_not_pretend_to_be_bayesian_evidence(self):
        self.demo.reasoning.record(kind="criticism", text="That follow-up was poorly timed.", context=self.demo.context_bundle(),
                                   base_revision=1, subject_id="catch_value")
        self.assertEqual(self.demo.reasoning.model.belief("catch_value").confidence, 0.5)
        self.assertEqual(self.demo.reasoning.feedback[-1]["attribution"], "explicit")

    async def test_new_frame_is_preserved_without_fabricated_grounding(self):
        before = self.demo.policy.fingerprint
        self.demo.reasoning.record(kind="frame", text="Think of the game as a continuous unit.",
            prediction="Reposition after misses before our next throw.", context=self.demo.context_bundle(), base_revision=1)
        model = self.demo.reasoning.model
        self.assertEqual(model.proposals[0]["status"], "needs_grounding")
        self.assertEqual(model.ontology_revision, 1)
        self.assertEqual(model.revision, 2)
        self.assertEqual(self.demo.policy.fingerprint, before)
        self.assertIsNone(self.demo.pending)

    async def test_model_roundtrip_and_parent_history(self):
        self.revise()
        model = self.demo.reasoning.model
        restored = ReasoningLab(self.demo.reasoning.directory)
        self.assertEqual(restored.model.fingerprint, model.fingerprint)
        self.assertEqual(load_model(json.loads(json.dumps(model.document()))).fingerprint, model.fingerprint)
        self.assertEqual(restored.feedback[-1]["semantic_hash"], model.fingerprint)
        self.assertTrue(list((self.demo.reasoning.directory / "models").glob("2-*.json")))
        self.assertTrue(list((self.demo.reasoning.directory / "models").glob("1-*.json")))

    async def test_generation_preserves_counterevidence_and_excludes_unassigned_praise(self):
        context = self.demo.context_bundle()
        self.demo.reasoning.record(kind="criticism", text="An earlier catch follow-up blocked a rescue.",
                                   subject_id="catch_value", context=context, base_revision=1)
        self.demo.reasoning.record(kind="encouragement", text="Good job!", context=context, base_revision=1)
        request = self.revise()
        self.assertEqual([e["kind"] for e in request["evidence"]], ["criticism", "belief"])
        self.assertEqual(request["evidence"][0]["observation"]["tick"], 100)

    async def test_invalid_confidence_and_stale_model_do_not_mutate(self):
        before = self.demo.reasoning.model.fingerprint
        for value in [float("nan"), float("inf"), True, -0.1, 1.1]:
            with self.assertRaises(PolicyError): self.revise(confidence=value)
        with self.assertRaises(PolicyError):
            self.demo.reasoning.record(kind="belief", text="Changed", context=self.demo.context_bundle(),
                                       base_revision=0, subject_id="catch_value", confidence=0.8)
        self.assertEqual(before, self.demo.reasoning.model.fingerprint)
        self.assertEqual(self.demo.reasoning.feedback, [])

    async def test_multiple_complete_policies_can_realize_one_semantic_model(self):
        request = self.revise()
        first, first_report = self.evaluate(request, 0)
        second, second_report = self.evaluate(request, 1)
        self.assertTrue(first_report["passed"])
        self.assertTrue(second_report["passed"])
        self.assertNotEqual(first.fingerprint, second.fingerprint)
        self.assertEqual(first.provenance["semantic_hash"], second.provenance["semantic_hash"])
        obs = observation()
        self.assertEqual(decide(self.demo.policy, obs, 1)[0]["hook_to"], [66, 40])
        self.assertEqual(decide(first, obs, 1)[0]["hook_to"], [76, 64])
        self.assertEqual(decide(second, obs, 1)[0]["hook_to"], [76, 64])

    async def test_lower_catch_belief_restores_independent_target(self):
        high, _ = self.evaluate(self.revise())
        self.demo.policy = high
        low, report = self.evaluate(self.revise(confidence=0.2))
        self.assertTrue(report["passed"])
        self.assertEqual(decide(low, observation(), 1)[0]["hook_to"], [66, 40])

    async def test_exposure_belief_changes_retreat_in_both_directions(self):
        high, report = self.evaluate(self.revise("punishment_risk", 0.8))
        self.assertTrue(report["passed"])
        obs = observation()
        obs["self"]["hp"] = 400
        self.assertEqual(decide(high, obs, 1)[0], {"walk_to": [20, 40]})
        self.assertEqual(decide(self.demo.policy, obs, 1)[0]["walk_to"], [47, 68])
        low, report = self.evaluate(self.revise("punishment_risk", 0.2))
        self.assertTrue(report["passed"])
        obs["self"]["hp"] = 250
        self.assertEqual(decide(low, obs, 1)[0]["walk_to"], [47, 68])
        self.assertEqual(decide(self.demo.policy, obs, 1)[0]["walk_to"], [20, 40])

    async def test_unchanged_uncertain_belief_has_no_forced_behavior_change(self):
        candidate, report = self.evaluate(self.revise(confidence=0.5))
        self.assertTrue(report["passed"])
        self.assertEqual(decide(candidate, observation(), 1)[0], decide(self.demo.policy, observation(), 1)[0])

    async def test_adversarial_regeneration_cannot_change_protected_movement(self):
        request = self.revise()
        document = reference_candidate(request)
        for rule in document["rules"]:
            if rule["id"] == "stay_with_you": rule["intent"] = "home"
        _, report = evaluate_candidate(request, document, "test-model", "A misleading explanation of success.")
        self.assertFalse(report["passed"])
        self.assertFalse(report["checks"][0]["passed"])

    async def test_false_semantic_claim_and_invented_capability_are_rejected(self):
        request = self.revise()
        doc = reference_candidate(request)
        doc["rules"][-1]["when"] = "always"
        _, report = evaluate_candidate(request, doc, "test-model", "Claims to follow catches.")
        self.assertFalse(report["passed"])
        doc["rules"][-1]["when"] = "secret_enemy_intent"
        with self.assertRaises(PolicyError): evaluate_candidate(request, doc, "test-model", "Unsupported.")

    async def test_complete_synthesis_review_and_activation_path(self):
        request = self.revise()
        result = await self.demo.reasoning_action("generate_reference_candidate", {"request_id": request["id"]})
        self.assertEqual(result["status"], "ready_for_trial")
        self.assertEqual(self.demo.policy.revision, 1)
        self.assertIsNone(self.demo.pending)
        await self.demo.reasoning_action("try_reasoning_candidate", {
            "request_id": request["id"], "submission_id": result["submission"]["id"]})
        self.assertEqual(self.demo.policy.revision, 1)
        self.demo.activate_pending(101)
        self.assertEqual(self.demo.policy.provenance["semantic_hash"], self.demo.reasoning.model.fingerprint)
        self.assertEqual(decide(self.demo.policy, observation(), 1)[0]["hook_to"], [76, 64])
        self.assertTrue(self.demo.reasoning.view(self.demo.policy, self.demo.match_id)["generations"][0]["active"])
        await asyncio.gather(*list(self.demo.tasks))
        self.assertFalse(self.demo.error)

    async def test_changed_belief_invalidates_an_older_candidate(self):
        request = self.revise()
        result = await self.demo.reasoning_action("generate_reference_candidate", {"request_id": request["id"]})
        self.revise(confidence=0.2)
        with self.assertRaisesRegex(PolicyError, "stale"):
            await self.demo.reasoning_action("try_reasoning_candidate", {
                "request_id": request["id"], "submission_id": result["submission"]["id"]})
        self.assertIsNone(self.demo.pending)

    async def test_policy_or_match_change_invalidates_generation(self):
        request = self.revise()
        with self.assertRaises(PolicyError):
            self.demo.reasoning.assert_current(request["id"], self.demo.policy, "different-match")
        document = self.demo.policy.document()
        document["revision"] += 1
        with self.assertRaises(PolicyError):
            self.demo.reasoning.assert_current(request["id"], compile_policy(document), self.demo.match_id)

    async def test_correction_during_async_evaluation_rejects_late_result(self):
        request = self.revise()
        entered, release = asyncio.Event(), asyncio.Event()
        async def delayed(function, *args):
            entered.set()
            await release.wait()
            return function(*args)
        with patch("coaching.server.asyncio.to_thread", delayed):
            task = asyncio.create_task(self.demo.reasoning_action("generate_reference_candidate", {"request_id": request["id"]}))
            await entered.wait()
            self.revise(confidence=0.2)
            release.set()
            with self.assertRaisesRegex(PolicyError, "stale"): await task
        self.assertEqual(self.demo.reasoning.requests[request["id"]]["submissions"], [])

    async def test_rejected_candidate_cannot_be_activated(self):
        request = self.revise()
        doc = reference_candidate(request)
        doc["retreat_percent"] = 80
        result = await self.demo.submit_reasoning_candidate({"request_id": request["id"], "policy": doc,
                                                           "explanation": "Unrelated threshold change."}, "test-model")
        self.assertEqual(result["status"], "rejected")
        with self.assertRaises(PolicyError):
            await self.demo.reasoning_action("try_reasoning_candidate", {
                "request_id": request["id"], "submission_id": result["submission"]["id"]})
        self.assertIsNone(self.demo.pending)


if __name__ == "__main__": unittest.main()
