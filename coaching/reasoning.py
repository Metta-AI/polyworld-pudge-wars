"""Working semantic model, grounded feedback, and policy synthesis contracts.

The working model and generated policy are distinct versioned artifacts. A
generator submits a complete policy; behavioral contracts decide whether it can
be offered as a live trial. Human confidence is not a Bayesian posterior.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import asdict, dataclass, replace
import hashlib
import json
import math
from pathlib import Path
import secrets
import time

from .policy import PolicyError, Rule, compile_policy, decide


def fingerprint(document):
    return hashlib.sha256(json.dumps(document, sort_keys=True).encode()).hexdigest()


@dataclass(frozen=True)
class Concept:
    id: str
    definition: str
    grounded_by: tuple[str, ...]


@dataclass(frozen=True)
class Belief:
    id: str
    claim: str
    concepts: tuple[str, ...]
    confidence: float = 0.5
    confidence_kind: str = "human_assessment"
    rationale: str = "Unvalidated starting hypothesis."
    evidence_ids: tuple[str, ...] = ()


@dataclass(frozen=True)
class Goal:
    id: str
    statement: str


@dataclass(frozen=True)
class Strategy:
    id: str
    belief_id: str
    goal_id: str
    consequence: str


@dataclass(frozen=True)
class SemanticModel:
    revision: int
    ontology_revision: int
    concepts: tuple[Concept, ...]
    beliefs: tuple[Belief, ...]
    goals: tuple[Goal, ...]
    strategies: tuple[Strategy, ...]
    proposals: tuple[dict, ...] = ()
    schema: str = "pudge-reasoning-v1"

    def document(self):
        return asdict(self)

    @property
    def fingerprint(self):
        return fingerprint(self.document())

    def belief(self, identifier):
        for belief in self.beliefs:
            if belief.id == identifier:
                return belief
        raise PolicyError("Choose a belief from the working model.")


def initial_model():
    return SemanticModel(1, 1, (
        Concept("catch_window", "A visible enemy is currently carried by the coaching teammate's hook.", ("coach_catch",)),
        Concept("exposure", "Our health is low while enemies can contest the arena.", ("low_health", "enemy_visible")),
        Concept("escape", "Moving to the home pad is the current recovery primitive.", ("home",)),
    ), (
        Belief("catch_value", "Teammate catches offer better offensive opportunities than independent shots.", ("catch_window",)),
        Belief("punishment_risk", "Opponents punish low-health exposure enough to justify earlier retreat.", ("exposure", "escape")),
    ), (
        Goal("team_conversion", "Convert coordinated opportunities into team advantage."),
        Goal("survival", "Stay available for the next team exchange."),
    ), (
        Strategy("follow_up", "catch_value", "team_conversion", "As confidence increases, prefer caught enemies after urgent defense and rescue."),
        Strategy("retreat_margin", "punishment_risk", "survival", "As confidence increases, retreat and reserve the hook at higher health."),
    ))


def load_model(document):
    if document["schema"] != "pudge-reasoning-v1":
        raise PolicyError("Unsupported semantic model version.")
    model = SemanticModel(
        document["revision"], document["ontology_revision"],
        tuple(Concept(**{**c, "grounded_by": tuple(c["grounded_by"])}) for c in document["concepts"]),
        tuple(Belief(**{**b, "concepts": tuple(b["concepts"]), "evidence_ids": tuple(b["evidence_ids"])}) for b in document["beliefs"]),
        tuple(Goal(**g) for g in document["goals"]),
        tuple(Strategy(**s) for s in document["strategies"]), tuple(document["proposals"]))
    if {b.id for b in model.beliefs} != {b.id for b in initial_model().beliefs}:
        raise PolicyError("New beliefs need a registered synthesis contract before execution.")
    for belief in model.beliefs:
        validate_confidence(belief.confidence)
    return model


def validate_confidence(value):
    if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 1:
        raise PolicyError("Confidence must be a finite number between zero and one.")


class ReasoningLab:
    def __init__(self, directory: Path):
        self.directory = directory
        current = directory / "model.json"
        self.model = load_model(json.loads(current.read_text())) if current.exists() else initial_model()
        events = directory / "feedback.jsonl"
        self.feedback = [json.loads(line) for line in events.read_text().splitlines()][-100:] if events.exists() else []
        self.requests = {}

    def save(self, event, parent):
        self.directory.mkdir(parents=True, exist_ok=True)
        archive = self.directory / "models"
        archive.mkdir(exist_ok=True)
        (archive / f"{parent.revision}-{parent.fingerprint[:12]}.json").write_text(json.dumps(parent.document(), indent=2) + "\n")
        contents = json.dumps(self.model.document(), indent=2) + "\n"
        (archive / f"{self.model.revision}-{self.model.fingerprint[:12]}.json").write_text(contents)
        pending = self.directory / "model.pending"
        pending.write_text(contents)
        pending.replace(self.directory / "model.json")
        with (self.directory / "feedback.jsonl").open("a") as output:
            output.write(json.dumps(event) + "\n")
        self.feedback.append(event)
        self.feedback = self.feedback[-100:]

    def record(self, *, kind, text, context, base_revision, subject_id=None, confidence=None, prediction=""):
        if base_revision != self.model.revision:
            raise PolicyError("The working semantic model changed. Retrieve its latest revision.")
        if kind not in {"belief", "encouragement", "praise", "criticism", "frame"}:
            raise PolicyError("Unknown feedback kind.")
        if not isinstance(text, str) or not 1 <= len(text.strip()) <= 2000:
            raise PolicyError("Feedback must contain 1–2000 characters.")
        subjects = {b.id for b in self.model.beliefs} | {s.id for s in self.model.strategies}
        subjects |= {r["id"] for r in context["policy"]["rules"]}
        if subject_id is not None and subject_id not in subjects:
            raise PolicyError("Feedback must reference an existing belief, strategy or policy rule.")
        parent = self.model
        event = {"id": secrets.token_hex(8), "kind": kind, "text": text.strip(), "at": time.time(),
                 "subject_id": subject_id, "attribution": "explicit" if subject_id else "unassigned",
                 "context_id": context["context_id"], "match_id": context["match_id"],
                 "observation": deepcopy(context["speech_time"]), "trace": deepcopy(context["trace_at_context"]),
                 "policy_hash": fingerprint(context["policy"]), "parent_semantic_hash": self.model.fingerprint}
        message = "Feedback recorded. No belief probability or policy was changed."
        if kind == "belief":
            belief = self.model.belief(subject_id)
            validate_confidence(confidence)
            updated = replace(belief, confidence=float(confidence), rationale=text.strip(),
                              evidence_ids=belief.evidence_ids + (event["id"],))
            self.model = replace(self.model, revision=self.model.revision + 1,
                                 beliefs=tuple(updated if b.id == subject_id else b for b in self.model.beliefs))
            event.update(before_confidence=belief.confidence, after_confidence=confidence,
                         epistemic_status="Human assessment; not a calibrated posterior or observed game outcome.")
            message = "Working belief revised. Generate and inspect a policy candidate before trying it."
        elif kind == "frame":
            if not isinstance(prediction, str) or len(prediction) > 2000:
                raise PolicyError("A proposed prediction must be a short description.")
            proposal = {"id": event["id"], "description": text.strip(), "prediction": prediction,
                        "status": "needs_grounding", "evidence_id": event["id"],
                        "next_step": "Specify an observable distinction, examples and an execution contract; compare against the current ontology."}
            self.model = replace(self.model, revision=self.model.revision + 1,
                                 proposals=self.model.proposals + (proposal,))
            message = "Frame challenge preserved as an ontology proposal. It has no executable grounding yet."
        elif kind in {"praise", "criticism"} and subject_id is None:
            message = "Feedback recorded without an assigned cause. Name the behavior you mean before treating it as evidence for a belief."
        event["semantic_hash"] = self.model.fingerprint
        self.save(event, parent)
        return {"status": "recorded", "message": message, "event_id": event["id"],
                "semantic_revision": self.model.revision, "semantic_hash": self.model.fingerprint}

    def request(self, belief_id, parent_policy, context):
        belief = self.model.belief(belief_id)
        subjects = {belief_id} | {s.id for s in self.model.strategies if s.belief_id == belief_id}
        evidence = [deepcopy(e) for e in self.feedback if e["subject_id"] in subjects][-6:]
        direction = "increase" if belief.confidence >= 0.6 else "decrease" if belief.confidence <= 0.4 else "retain"
        request = {"id": secrets.token_hex(8), "status": "awaiting_generation", "created_at": time.time(),
                   "semantic_model": self.model.document(), "semantic_hash": self.model.fingerprint,
                   "evidence": evidence,
                   "belief_id": belief_id, "direction": direction, "match_id": context["match_id"],
                   "context_id": context["context_id"], "context_tick": context["speech_time"]["tick"],
                   "parent_policy": parent_policy.document(), "parent_hash": parent_policy.fingerprint,
                   "contract": ("Change only follow_up catch priority. Preserve movement, thresholds and all other rules."
                                if belief_id == "catch_value" else
                                "Change only retreat_percent in the requested direction. Preserve every rule."),
                   "generation_instruction": "Submit a complete policy document. Multiple realizations may satisfy the same contract. Do not alter the evaluator or protected behavior.",
                   "confidence_interpretation": "The 0.4/0.6 bands are an explicit demo synthesis convention, not Bayesian inference.",
                   "submissions": []}
        self.requests[request["id"]] = request
        self.save_request(request)
        return deepcopy(request)

    def save_request(self, request):
        directory = self.directory / "generations"
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{request['id']}.json").write_text(json.dumps(request, indent=2) + "\n")

    def assert_current(self, request_id, policy, match_id):
        if request_id not in self.requests:
            raise PolicyError("That generation request is unavailable; request a fresh one.")
        request = self.requests[request_id]
        if (request["semantic_hash"] != self.model.fingerprint or request["parent_hash"] != policy.fingerprint
                or request["match_id"] != match_id):
            raise PolicyError("Generation is stale: its semantic model, policy or match changed.")
        return request

    def view(self, policy, match_id):
        generations = []
        for request in list(self.requests.values())[-6:]:
            stale = request["semantic_hash"] != self.model.fingerprint or request["parent_hash"] != policy.fingerprint or request["match_id"] != match_id
            active = any(s["policy_hash"] == policy.fingerprint for s in request["submissions"])
            generations.append({k: deepcopy(request[k]) for k in ("id", "status", "belief_id", "direction", "submissions")})
            generations[-1]["stale"] = stale
            generations[-1]["active"] = active
        return {"model": self.model.document(), "hash": self.model.fingerprint,
                "active_policy_semantic_hash": policy.provenance.get("semantic_hash"),
                "feedback": [{k: e.get(k) for k in ("id", "kind", "text", "subject_id", "attribution", "context_id")} for e in self.feedback[-8:]],
                "generations": generations}


def reference_candidate(request, variant=0):
    """Offline reference synthesizer for the demo; not a coding-model result."""
    document = deepcopy(request["parent_policy"])
    direction = request["direction"]
    if request["belief_id"] == "catch_value" and direction != "retain":
        document["rules"] = [r for r in document["rules"] if r["id"] != "follow_up"]
        if direction == "increase":
            document["rules"].append(asdict(Rule("follow_up", "hook", 30 + variant, "coach_catch", "coach_catch", "hook",
                                                       "match", goal="team_conversion")))
    elif request["belief_id"] == "punishment_risk":
        delta = 15 + variant if direction == "increase" else -10 - variant if direction == "decrease" else 0
        document["retreat_percent"] = max(10, min(80, document["retreat_percent"] + delta))
    document["revision"] += 1
    return document


def probe_observation(tick=100):
    """Contract scenario, explicitly synthetic; never substituted into live play."""
    def person(identifier, team, x, y):
        return {"id": identifier, "slot": identifier - 1001, "team": team, "x": x, "y": y,
                "hp": 800, "max_hp": 840, "alive": True, "shield": 0, "hook_ready": True,
                "in_river": False, "home_x": 20 if team == 0 else 108, "home_y": 40}
    people = [person(1001, 0, 35, 60), person(1002, 0, 44, 40), person(1003, 1, 66, 40), person(1004, 1, 76, 64)]
    return {"tick": tick, "self": people[1], "play_west_max": 52, "play_east_min": 76,
            "score": {"west": 0, "east": 0}, "visible": {"pudges": people,
            "hooks": [{"owner_id": 1001, "team": 0, "victim": 1004, "flying": False}]}}


def evaluate_candidate(request, document, generator, explanation):
    parent = compile_policy(request["parent_policy"])
    raw = deepcopy(document)
    if raw["revision"] != parent.revision + 1:
        raise PolicyError("A generated policy must advance its pinned parent by one revision.")
    raw["provenance"] = {"scope": "match", "semantic_hash": request["semantic_hash"],
                         "generation_id": request["id"], "belief_id": request["belief_id"],
                         "parent_hash": parent.fingerprint, "generator": generator, "rationale": explanation}
    candidate = compile_policy(raw)
    a = {r.id: r for r in parent.rules}
    b = {r.id: r for r in candidate.rules}
    direction = request["direction"]
    checks = []
    if request["belief_id"] == "catch_value":
        checks.append(("preserve unrelated rules and retreat threshold", parent.retreat_percent == candidate.retreat_percent and
                       {k: v for k, v in a.items() if k != "follow_up"} == {k: v for k, v in b.items() if k != "follow_up"}))
        follow = b.get("follow_up")
        if direction == "increase":
            checks.append(("catch tactic has a grounded target and bounded priority", follow is not None and
                           follow.channel == "hook" and follow.when == follow.select == "coach_catch" and follow.intent == "hook" and
                           follow.scope == "match" and 20 <= follow.priority < 100 and follow.until_tick is None))
            checks.append(("catch priority respects existing defense and focus order", follow is not None and
                           all(follow.priority > a[k].priority for k in ("reserve_when_hurt", "rescue", "focus") if k in a) and
                           "independent_shot" in a and follow.priority < a["independent_shot"].priority))
        elif direction == "decrease":
            checks.append(("remove catch priority", follow is None))
        else:
            checks.append(("uncertainty retains the existing tactic", a == b))
        obs = probe_observation(request["context_tick"])
        before = decide(parent, obs, 1001)[0]
        after = decide(candidate, obs, 1001)[0]
        desired = [76, 64] if direction == "increase" else [66, 40] if direction == "decrease" else before.get("hook_to")
        checks.extend((("intended target in a catch opportunity", after.get("hook_to") == desired),
                       ("movement preserved during catch", after.get("walk_to") == before.get("walk_to"))))
        obs["visible"]["hooks"] = []
        checks.append(("no-catch negative control", decide(parent, obs, 1001)[0] == decide(candidate, obs, 1001)[0]))
        obs = probe_observation(request["context_tick"])
        obs["self"]["hp"] = 1
        checks.append(("low-health behavior preserved", decide(parent, obs, 1001)[0] == decide(candidate, obs, 1001)[0]))
        obs["self"].update(hp=800, hook_ready=False)
        checks.append(("unavailable hook is not attempted", "hook_to" not in decide(candidate, obs, 1001)[0]))
        obs = probe_observation(request["context_tick"])
        obs["visible"]["hooks"].append({"owner_id": 1003, "team": 1, "victim": 1001, "flying": False})
        checks.append(("urgent rescue behavior preserved", decide(parent, obs, 1001)[0] == decide(candidate, obs, 1001)[0]))
    else:
        checks.append(("preserve all decision rules", a == b))
        old, new = parent.retreat_percent, candidate.retreat_percent
        checks.append(("retreat threshold follows the belief intervention",
                       new > old if direction == "increase" else new < old if direction == "decrease" else new == old))
        obs = probe_observation(request["context_tick"])
        obs["self"]["hp"] = 840
        checks.append(("healthy behavior is unchanged", decide(parent, obs, 1001)[0] == decide(candidate, obs, 1001)[0]))
        obs["self"]["hp"] = int(840 * (old + new) / 200)
        before, after = decide(parent, obs, 1001)[0], decide(candidate, obs, 1001)[0]
        desired = [20, 40] if direction == "increase" else before.get("walk_to") if direction == "retain" else [47, 68]
        checks.append(("borderline-health movement follows the intervention", after.get("walk_to") == desired))
    return candidate, {"passed": all(passed for _, passed in checks),
                       "checks": [{"name": name, "passed": passed} for name, passed in checks],
                       "example": {"before": before, "after": after},
                       "evidence_kind": "synthetic behavioral contracts", "competitive": "untested",
                       "causal_claim": "Tests the artifact's behavior, not the truth of the belief or a win-rate benefit."}
