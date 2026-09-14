"""A small semantic policy language with explicit, deterministic semantics.

Policy = ordered rules per action channel + versioned primitive capabilities.
The same compiled rules drive actions, the readable playbook, and decision traces.
This demo represents movement and hook decisions, not the existing champion policy.
"""
from __future__ import annotations

from copy import deepcopy
from dataclasses import asdict, dataclass, field
import hashlib
import json
import math
import re
from typing import Any

CAPABILITIES = "pudge-semantic-v1"
GUARDS = {
    "always": "always",
    "low_health": "health is below the retreat threshold",
    "in_river": "I am in the river",
    "coach_catch": "my teammate is carrying a visible enemy on a hook",
    "coach_throw": "my teammate has an empty hook in flight",
    "enemy_visible": "a living, unshielded enemy is visible",
    "ally_danger": "a teammate is low on health in the river or on an enemy hook",
    "target_visible": "the selected enemy is still visible and alive",
}
SELECTORS = {"none", "nearest_enemy", "coach_catch", "endangered_ally", "selected_enemy"}
INTENTS = {"hook": "throw at the selected target", "hold_hook": "keep my hook available",
           "home": "move to my home pad", "follow": "hold a throwing lane beside my teammate",
           "hold_position": "hold the chosen position on my bank"}


class PolicyError(ValueError):
    pass


@dataclass(frozen=True)
class Rule:
    id: str
    channel: str
    priority: int
    when: str
    select: str
    intent: str
    scope: str = "persistent"
    until_tick: int | None = None
    target_id: int | None = None
    point: tuple[float, float] | None = None
    goal: str = "coordinate_with_teammate"


@dataclass(frozen=True)
class Policy:
    revision: int = 1
    capabilities: str = CAPABILITIES
    retreat_percent: int = 35
    rules: tuple[Rule, ...] = ()
    provenance: dict[str, Any] = field(default_factory=dict)

    def document(self) -> dict[str, Any]:
        return asdict(self)

    @property
    def fingerprint(self) -> str:
        return hashlib.sha256(json.dumps(self.document(), sort_keys=True).encode()).hexdigest()


def initial_policy() -> Policy:
    return Policy(rules=(
        Rule("escape_water", "movement", 0, "in_river", "none", "home", goal="survive"),
        Rule("retreat", "movement", 10, "low_health", "none", "home", goal="survive"),
        Rule("stay_with_you", "movement", 100, "always", "none", "follow"),
        Rule("reserve_when_hurt", "hook", 0, "low_health", "none", "hold_hook", goal="survive"),
        Rule("rescue", "hook", 10, "ally_danger", "endangered_ally", "hook", goal="save_teammate"),
        Rule("independent_shot", "hook", 100, "enemy_visible", "nearest_enemy", "hook"),
    ))


def compile_policy(document: dict[str, Any]) -> Policy:
    """Validate and lower the supported semantic vocabulary to immutable rules."""
    if set(document) != {"revision", "capabilities", "retreat_percent", "rules", "provenance"}:
        raise PolicyError("Policy fields must match the versioned schema.")
    if document["capabilities"] != CAPABILITIES:
        raise PolicyError("Unsupported capability version.")
    if type(document["revision"]) is not int or document["revision"] < 1:
        raise PolicyError("Revision must be a positive integer.")
    if type(document["retreat_percent"]) is not int or not 10 <= document["retreat_percent"] <= 80:
        raise PolicyError("Retreat threshold must be an integer from 10 to 80 percent.")
    if not isinstance(document["rules"], (list, tuple)) or not 1 <= len(document["rules"]) <= 24:
        raise PolicyError("A policy needs 1–24 rules.")
    rules = []
    for raw in document["rules"]:
        try:
            rule = Rule(**raw)
        except (TypeError, ValueError) as exc:
            raise PolicyError("Invalid rule fields.") from exc
        if any(not isinstance(v, str) for v in (rule.when, rule.select, rule.intent, rule.channel, rule.scope)):
            raise PolicyError("Semantic capability names must be strings.")
        if rule.when not in GUARDS or rule.select not in SELECTORS or rule.intent not in INTENTS:
            raise PolicyError("This rule uses an unsupported semantic capability.")
        if rule.channel not in {"hook", "movement"}:
            raise PolicyError("Unknown decision channel.")
        if not isinstance(rule.id, str) or not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", rule.id):
            raise PolicyError("Invalid rule ID.")
        if type(rule.priority) is not int or not 0 <= rule.priority <= 1000:
            raise PolicyError("Invalid priority.")
        if rule.scope not in {"persistent", "match", "temporary"}:
            raise PolicyError("Unknown rule lifetime.")
        if rule.scope == "temporary" and (type(rule.until_tick) is not int or rule.until_tick < 0):
            raise PolicyError("Temporary rules need a bounded expiry tick.")
        if rule.scope != "temporary" and rule.until_tick is not None:
            raise PolicyError("Only temporary rules may have an expiry tick.")
        if rule.channel == "hook" and rule.intent not in {"hook", "hold_hook"}:
            raise PolicyError("Hook rules cannot control movement.")
        if rule.channel == "movement" and rule.intent not in {"home", "follow", "hold_position"}:
            raise PolicyError("Movement rules cannot control hooks.")
        if rule.intent == "hook" and rule.select == "none":
            raise PolicyError("A hook needs a target selector.")
        if rule.select == "selected_enemy" and (rule.scope != "temporary" or type(rule.target_id) is not int):
            raise PolicyError("An entity reference must be temporary and name an entity.")
        if rule.target_id is not None and rule.select != "selected_enemy":
            raise PolicyError("Only the selected-enemy selector can bind an entity ID.")
        if rule.when == "target_visible" and rule.target_id is None:
            raise PolicyError("The target-visible condition needs a bound entity ID.")
        if rule.intent != "hook" and rule.select != "none":
            raise PolicyError("Only hook actions use a target selector.")
        if not isinstance(rule.goal, str) or len(rule.goal) > 160:
            raise PolicyError("A goal must be a short descriptive label.")
        if rule.point is not None and rule.intent != "hold_position":
            raise PolicyError("Only hold-position actions use a point.")
        if rule.intent == "hold_position":
            if rule.scope == "persistent":
                raise PolicyError("A position belongs to this match; it is not a persistent strategy.")
            if (not isinstance(rule.point, (list, tuple)) or len(rule.point) != 2 or
                any(type(v) not in (int, float) or not math.isfinite(v) or not 8 <= v <= 119 for v in rule.point)):
                raise PolicyError("Holding a position needs a point inside the arena.")
            rule = Rule(**{**asdict(rule), "point": tuple(rule.point)})
        rules.append(rule)
    if len({r.id for r in rules}) != len(rules):
        raise PolicyError("Rule IDs must be unique.")
    if len({(r.channel, r.priority) for r in rules}) != len(rules):
        raise PolicyError("Each channel needs unambiguous priorities.")
    if not any(r.channel == "movement" and r.when == "always" for r in rules):
        raise PolicyError("Movement needs a total fallback.")
    if not isinstance(document["provenance"], dict):
        raise PolicyError("Provenance must be an object.")
    return Policy(document["revision"], CAPABILITIES, document["retreat_percent"],
                  tuple(sorted(rules, key=lambda r: (r.channel, r.priority))), deepcopy(document["provenance"]))


def readable(policy: Policy) -> list[dict[str, Any]]:
    rows = []
    for r in sorted(policy.rules, key=lambda r: (r.channel, r.priority)):
        condition = GUARDS[r.when].replace("the retreat threshold", f"{policy.retreat_percent}%")
        target = {"nearest_enemy": "the nearest enemy", "coach_catch": "the enemy on your hook",
                  "endangered_ally": "the endangered teammate", "selected_enemy": f"enemy {r.target_id}"}.get(r.select)
        action = INTENTS[r.intent].replace("the selected target", target or "the selected target")
        if r.point:
            action += f" near ({r.point[0]:g}, {r.point[1]:g})"
        rows.append({"id": r.id, "channel": r.channel, "priority": r.priority,
                     "text": f"When {condition}, {action}.", "scope": r.scope,
                     "until_tick": r.until_tick, "goal": r.goal})
    return rows


def distance(a: dict, b: dict) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def facts(obs: dict, coach_id: int) -> dict:
    me = obs["self"]
    visible = obs.get("visible", {})
    people = visible.get("pudges", [])
    enemies = [p for p in people if p["team"] != me["team"] and p["alive"] and not p.get("shield")]
    allies = [p for p in people if p["team"] == me["team"] and p["id"] != me["id"] and p["alive"]]
    hooks = visible.get("hooks", [])
    caught_ids = {h["victim"] for h in hooks if h.get("owner_id") == coach_id and h.get("victim")}
    danger_ids = {h["victim"] for h in hooks if h["team"] != me["team"] and h.get("victim")}
    catches = [p for p in enemies if p["id"] in caught_ids]
    danger = [p for p in allies if p["id"] in danger_ids or
              (p.get("in_river") and p["hp"] * 100 <= p["max_hp"] * 60)]
    order = lambda p: (distance(me, p), p["id"])
    return {"me": me, "enemies": sorted(enemies, key=order), "allies": allies,
            "catches": sorted(catches, key=order), "danger": sorted(danger, key=order),
            "coach": next((p for p in allies if p["id"] == coach_id), None),
            "coach_throw": any(h.get("owner_id") == coach_id and h.get("flying") and not h.get("victim") for h in hooks),
            "own_hook": any(h.get("owner_id") == me["id"] for h in hooks)}


def hook_block(f: dict, target: dict, obs: dict) -> str | None:
    me = f["me"]
    if not me.get("hook_ready") or f["own_hook"]:
        return "hook unavailable or already in flight"
    # Deliberately conservative v1 primitive: no predictive aiming or bounce shots.
    if distance(me, target) > 55:
        return "target outside the demo's 55-tile aiming envelope"
    dx, dy = target["x"] - me["x"], target["y"] - me["y"]
    length = dx * dx + dy * dy
    for ally in f["allies"]:
        if ally["id"] == target["id"] or length == 0:
            continue
        u = max(0, min(1, ((ally["x"] - me["x"]) * dx + (ally["y"] - me["y"]) * dy) / length))
        if math.hypot(ally["x"] - me["x"] - u * dx, ally["y"] - me["y"] - u * dy) < 5:
            return "teammate in the straight throw corridor"
    return None


def decide(policy: Policy, obs: dict, coach_id: int, memory: dict | None = None) -> tuple[dict, dict, dict]:
    """(policy, observation, memory) -> action, next memory, execution trace.

    Rule-table swaps keep game/controller state separate. The bounded memory
    records the latest selected rules; hook-flight commitments derive from observed state.
    """
    memory = dict(memory or {})
    trace: dict[str, Any] = {"tick": obs["tick"], "revision": policy.revision,
                             "policy_hash": policy.fingerprint, "rules": [], "selected": {}}
    if not obs["self"]["alive"]:
        trace["status"] = "dead"
        return {}, memory, trace
    f = facts(obs, coach_id)
    me = f["me"]
    action: dict[str, Any] = {}
    for channel in ("movement", "hook"):
        for r in sorted((r for r in policy.rules if r.channel == channel), key=lambda r: r.priority):
            if r.until_tick is not None and obs["tick"] >= r.until_tick:
                trace["rules"].append({"id": r.id, "status": "expired"})
                continue
            selected = next((e for e in f["enemies"] if e["id"] == r.target_id), None)
            guard = {"always": True, "low_health": me["hp"] * 100 < me["max_hp"] * policy.retreat_percent,
                     "in_river": bool(me.get("in_river")), "coach_catch": bool(f["catches"]),
                     "coach_throw": f["coach_throw"], "enemy_visible": bool(f["enemies"]),
                     "ally_danger": bool(f["danger"]), "target_visible": selected is not None}[r.when]
            if not guard:
                trace["rules"].append({"id": r.id, "status": "condition_false"})
                continue
            candidates = {"none": [], "nearest_enemy": f["enemies"], "coach_catch": f["catches"],
                          "endangered_ally": f["danger"], "selected_enemy": [selected] if selected else []}[r.select]
            target = candidates[0] if candidates else None
            if r.intent == "hook":
                reason = hook_block(f, target, obs) if target else "no eligible target"
                if reason:
                    trace["rules"].append({"id": r.id, "status": "blocked", "reason": reason})
                    continue
                action["hook_to"] = [target["x"], target["y"]]
            elif r.intent == "home":
                action["walk_to"] = [me["home_x"], me["home_y"]]
            elif r.intent in {"follow", "hold_position"}:
                west = me["team"] == 0
                lip = obs["play_west_max"] - 5 if west else obs["play_east_min"] + 5
                coach_y = (f["coach"] or me)["y"]
                x, y = r.point if r.point else (lip, coach_y + (8 if coach_y < 64 else -8))
                x = min(x, lip) if west else max(x, lip)
                action["walk_to"] = [max(8, min(119, x)), max(8, min(119, y))]
            trace["rules"].append({"id": r.id, "status": "selected", "target": target["id"] if target else None})
            trace["selected"][channel] = r.id
            memory[channel] = r.id
            break
    trace["action"] = deepcopy(action)
    return action, memory, trace


@dataclass
class Interpretation:
    status: str
    message: str
    policy: Policy | None = None
    changed: list[str] = field(default_factory=list)


def interpret(text: str, policy: Policy, context: dict, coach_id: int, selected_id: int | None = None,
              point: list[float] | None = None, utterance_id: str = "") -> Interpretation:
    """Conservative demo grammar. A model adapter can propose the same validated IR.

    Unsupported or compound instructions don't execute a guessed partial meaning.
    """
    original = text.strip()
    t = re.sub(r"[.!?,]", "", original.lower().replace("’", "'"))
    t = re.sub(r"\s+", " ", t).strip()
    if t.startswith("why") or t in {"what are you doing", "explain"}:
        return Interpretation("question", "See the selected rules and accepted actions in the decision panel.")
    scope = "persistent" if t.endswith(" from now on") else "match"
    t = t.removesuffix(" from now on")
    t = re.sub(r"^(please |can you )", "", t)
    rules = {r.id: r for r in policy.rules}
    changed: list[str] = []
    threshold = policy.retreat_percent
    message = ""
    if t in {"follow up on my hooks", "follow up on my catches", "hook my target", "prioritize my catches",
             "when i catch someone follow up", "when i catch someone follow up before picking your own target"}:
        r = Rule("follow_up", "hook", 30, "coach_catch", "coach_catch", "hook", scope=scope,
                 goal="convert_team_catches")
        rules[r.id] = r
        changed = [r.id]
        message = "I'll prioritize enemies on your hook, after retreat and urgent rescues."
    elif t in {"wait for my hook", "save your hook for mine", "hold your hook while mine is flying"}:
        r = Rule("wait_for_you", "hook", 40, "coach_throw", "none", "hold_hook", scope=scope)
        rules[r.id] = r
        changed = [r.id]
        message = "I'll hold my hook while yours is flying empty, then release it when that flight ends."
    elif t in {"stop waiting", "don't wait for my hook", "do not wait for my hook"}:
        rules.pop("wait_for_you", None)
        changed = ["wait_for_you"]
        message = "I won't reserve my hook for your throw."
    elif t in {"stop following up", "don't follow up on my hooks", "do not follow up on my hooks"}:
        rules.pop("follow_up", None)
        changed = ["follow_up"]
        message = "I've removed the catch priority."
    elif t in {"focus him", "focus that enemy", "hook him", "hook this one next"}:
        f = facts(context, coach_id)
        targets = [p for p in f["enemies"] if p["id"] == selected_id] if selected_id is not None else f["catches"]
        if len(targets) != 1:
            return Interpretation("clarify", "Select one visible enemy in the context panel, then say 'focus him'.")
        r = Rule("focus", "hook", 20, "target_visible", "selected_enemy", "hook", "temporary",
                 context["tick"] + 32 * 8, targets[0]["id"])
        rules[r.id] = r
        changed = [r.id]
        message = f"I'll prioritize enemy {r.target_id} for eight seconds while visible, after urgent rescues."
    elif re.fullmatch(r"retreat (?:below|at) (\d+)\s*(?:percent|%)?(?: health)?", t):
        threshold = int(re.search(r"\d+", t).group())
        changed = ["retreat", "reserve_when_hurt"]
        message = f"I'll head home and reserve my hook below {threshold}% health."
    elif t in {"hold here", "hold this position"}:
        point = point or [context["self"]["x"], context["self"]["y"]]
        r = Rule("hold_here", "movement", 30, "always", "none", "hold_position", "match", point=tuple(point))
        rules[r.id] = r
        changed = [r.id]
        message = "I'll hold this position on my bank, unless I need to retreat."
    elif t in {"follow me", "stop holding position"}:
        rules.pop("hold_here", None)
        changed = ["hold_here"]
        message = "I'll move back to a throwing lane beside you."
    else:
        return Interpretation("unsupported", "This demo understands catch priority, waiting for your hook, focus him, retreat below a percentage, hold here, and follow me. Please give one instruction at a time.")
    doc = policy.document()
    doc.update(revision=policy.revision + 1, retreat_percent=threshold, rules=[asdict(r) for r in rules.values()],
               provenance={"parent_hash": policy.fingerprint, "utterance_id": utterance_id, "text": original,
                           "context_tick": context["tick"], "scope": scope, "changed": changed})
    try:
        candidate = compile_policy(doc)
    except PolicyError as exc:
        return Interpretation("invalid", str(exc))
    return Interpretation("compiled", message, candidate, changed)
