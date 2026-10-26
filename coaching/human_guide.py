"""Read-only human coaching from the team's visible observation and Jev choices.

The engine never waits for inference. Candidate text is authored here, not model
generated. Each displayed choice is revalidated against the latest observation.
"""
from __future__ import annotations

import asyncio
import math
import os
import time

from aiohttp import ClientError, ClientTimeout

from .policy import distance
from .enemy_beliefs import EnemyBeliefs

ENDPOINT = "https://api.typesafe.ai/v1/systemone"
REQUEST_INTERVAL = 1.0
MAX_AGE = 2.0
MAX_TICKS = 64


def human_view(observation, slot=0):
    """Team vision is shared in coworld_host; only self changes perspective.

    Deliberately omit the teammate's accepted actions, print, and policy trace.
    Never source context from the omniscient /global stream.
    """
    human = next((p for p in observation["visible"]["pudges"] if p["slot"] == slot), None)
    if human is None or human["team"] != observation["self"]["team"]:
        return None
    # Being in vision does not make an enemy's private cooldowns, home pad,
    # inventory or bot speech human-visible evidence. Keep only rendered facts.
    public_fields = ("id", "slot", "team", "x", "y", "hp", "max_hp", "alive", "hooked", "shield", "in_river", "layer")
    visible = dict(observation["visible"])
    visible["pudges"] = [{k: p[k] for k in public_fields if k in p} for p in visible["pudges"]]
    return {k: observation[k] for k in ("tick", "score", "kill_goal", "done")
            if k in observation} | {"self": human, "visible": visible}


def segment_distance(point, start, end):
    dx, dy = end["x"] - start["x"], end["y"] - start["y"]
    length = dx * dx + dy * dy
    u = max(0, min(1, ((point["x"] - start["x"]) * dx + (point["y"] - start["y"]) * dy) / length)) if length else 0
    return math.hypot(point["x"] - start["x"] - u * dx, point["y"] - start["y"] - u * dy)


def hook_candidate_clear(me, target, people, props):
    # A conservative direct-shot envelope, not a simulation of aiming, terrain,
    # motion, rebounds, or hit probability. Leave those decisions to the player.
    if distance(me, target) > 55:
        return False
    blockers = [p for p in people if p["alive"] and p["id"] not in (me["id"], target["id"])]
    blockers += [p for p in props if p.get("kind") == "wall"]
    blockers += [{"x": 64, "y": 64}]  # fixed central fountain rock
    return not any(segment_distance(p, me, target) < 5 for p in blockers)


def options(obs):
    """Generate eligible actions in local fallback priority order."""
    me, visible = obs["self"], obs["visible"]
    hp = round(100 * me["hp"] / max(1, me["max_hp"]))
    people, hooks = visible.get("pudges", []), visible.get("hooks", [])
    enemies = sorted((p for p in people if p["alive"] and p["team"] != me["team"] and not p.get("shield")),
                     key=lambda p: (distance(me, p), p["id"]))
    allies = [p for p in people if p["alive"] and p["team"] == me["team"] and p["id"] != me["id"]]
    actions, strategies = {}, {}

    def add(key, title, why, control="", target=None, urgent=False, threshold=.6):
        actions[key] = dict(id=key, title=title, why=why, control=control,
                            target_id=target, urgent=urgent, threshold=threshold)

    def strategy(key, title, why):
        strategies[key] = dict(id=key, title=title, why=why)

    strategy("coordinate", "Make the next exchange a team play",
             "Take separate throwing lanes. Follow a teammate's catch when your hook has a clear path.")
    if not me["alive"]:
        add("respawn", "Plan your return", "You're down. Locate your teammate before the next engagement.")
        strategy("reset", "Return together", "Rejoin your teammate after respawning and find a fresh throwing lane.")
        return actions, {"reset": strategies["reset"]}
    if me.get("hooked"):
        add("hooked", "Prepare to escape when released", "You're on a hook. Movement and blink cannot free you mid-pull.", urgent=True)
        return actions, strategies
    near_hooks = [h for h in hooks if h["team"] != me["team"] and h.get("flying")
                  and not h.get("victim") and distance(me, h) < 12]
    if near_hooks and not me.get("shield"):
        add("dodge", "Watch the hook — move off its line", "An enemy hook is close. Move sideways to its visible path.", "WASD / right-click", urgent=True)
    if hp <= 35:
        add("retreat", "Fall back toward your healing pad", f"You're at {hp}% health. Recover before taking another exchange.", "WASD / right-click", urgent=True)
    if hp < 85:
        strategy("recover", "Recover before committing", "Use your healing pad, then return with enough health for another exchange.")
        if abs(me["x"] - me.get("home_x", -100)) <= 2 and abs(me["y"] - me.get("home_y", -100)) <= 2:
            add("heal", "Stay on your healing pad", f"You're at {hp}% health and within your home pad's healing area.")
    ready = me.get("hook_ready") and not any(h.get("owner_id") == me["id"] for h in hooks)
    if ready:
        ally_ids = {p["id"] for p in allies}
        caught = {h.get("victim") for h in hooks if h.get("owner_id") in ally_ids}
        endangered = {h.get("victim") for h in hooks if h["team"] != me["team"]}
        for ally in allies:
            if ally["id"] in endangered and hook_candidate_clear(me, ally, people, visible.get("props", [])):
                add(f"rescue_{ally['id']}", f"Try a rescue hook on ally {ally['slot'] + 1}",
                    "Your teammate is being pulled by an enemy. An ally hook can pull them back and heal them.",
                    "Aim at ally · Q", ally["id"], threshold=.85)
        if hp > 35:
            for enemy in enemies:
                if hook_candidate_clear(me, enemy, people, visible.get("props", [])):
                    follow = enemy["id"] in caught
                    add(f"{'follow' if follow else 'hook'}_{enemy['id']}",
                        f"{'Follow up on' if follow else 'Line up a hook on'} enemy {enemy['slot'] + 1}",
                        "Your teammate has this enemy on their hook. Check the moving target's path before throwing." if follow else
                        "Your hook is ready and this enemy is nearby. Check terrain and lead their movement before throwing.",
                        "Aim with cursor · Q", enemy["id"], threshold=.85)
    else:
        add("wait_hook", "Reposition while your hook returns", "Your hook is cooling down, casting, or already in flight. Set up your next angle.", "WASD / right-click")
    if allies and min(distance(me, p) for p in allies) > 20:
        add("regroup", "Move closer to your teammate", "Your living teammate is over 20 tiles away. Close the gap while keeping separate throwing lanes.", "WASD / right-click")
    if me.get("points", 0) > 0 and any(rank < 10 for rank in me.get("upgrades", [])):
        add("upgrade", "Spend your hook upgrade point", "You have an unspent point. Choose damage, range, speed, or radius in the ability bar.", "1–4")
    add("reposition", "Find a fresh throwing angle", "Keep moving between throws. Use visible enemies and your teammate to choose a lane.", "WASD / right-click")
    if not allies:
        strategies.pop("coordinate", None)
    if not enemies:
        add("scout", "Scout along your riverbank", "No enemies are visible. Move toward the river edge and scan along your bank for an opening.", "WASD / right-click")
        # Information gathering is more useful than a generic angle cue here.
        actions.pop("reposition")
    strategy("fish", "Create a clean hook opportunity", "Stay near your bank, vary your angle, and avoid throwing through other players or the fountain.")
    if hp <= 35:
        strategies = {"recover": strategies["recover"]} | strategies
    return actions, strategies


def choice_answer(payload, key, choices):
    answer = payload.get("answers", {}).get(key, {})
    if not isinstance(answer, dict) or answer.get("type") != "choice":
        raise ValueError("Invalid Choice answer")
    choice, confidence = answer.get("choice"), answer.get("confidence")
    if not isinstance(choice, str) or choice not in choices:
        raise ValueError("Unknown choice")
    if type(confidence) not in (int, float) or not math.isfinite(confidence) or not 0 <= confidence <= 1:
        raise ValueError("Invalid confidence")
    probabilities = answer.get("probabilities")
    if not isinstance(probabilities, dict) or set(probabilities) != set(choices):
        raise ValueError("Missing choice probabilities")
    if any(type(p) not in (int, float) or not math.isfinite(p) or not 0 <= p <= 1 for p in probabilities.values()):
        raise ValueError("Invalid probability")
    if abs(sum(probabilities.values()) - 1) > .02 or probabilities[choice] < max(probabilities.values()):
        raise ValueError("Invalid distribution")
    return choice, confidence


class HumanGuide:
    def __init__(self, api_key=None, model=None, clock=time.monotonic):
        self.api_key = os.environ.get("TYPESAFE_API_KEY", "") if api_key is None else api_key
        self.model = model or os.environ.get("TYPESAFE_MODEL", "jev-latest")
        self.clock = clock
        self.enabled = True
        self.generation = 0
        self.viewer_at = float("-inf")
        self.reset("")

    def reset(self, match_id):
        self.generation += 1
        self.match_id, self.obs = match_id, None
        self.actions, self.strategies = {}, {}
        self.observed_at = self.result_at = self.result_tick = 0
        self.result = {}
        self.beliefs = EnemyBeliefs()
        self.request_at = float("-inf")
        self.retry_at, self.failures, self.requests = 0, 0, 0
        self.latency_ms = None
        self.status = "ready" if self.api_key else "local"
        self.held = None
        self.held_at = 0

    def set_enabled(self, enabled):
        if type(enabled) is not bool:
            raise ValueError("enabled must be a boolean")
        self.enabled = enabled
        self.generation += 1
        self.result, self.held = {}, None
        self.beliefs.predictions.clear()
        self.retry_at = self.failures = 0
        self.status = "ready" if self.api_key else "local"

    def observe(self, observation, match_id):
        if match_id != self.match_id:
            self.reset(match_id)
        obs = human_view(observation)
        if obs is not None:
            self.obs, self.observed_at = obs, self.clock()
            self.actions, self.strategies = options(obs)
            self.beliefs.observe(obs)

    def fresh(self):
        return self.obs is not None and self.clock() - self.observed_at <= MAX_AGE and not self.obs.get("done")

    def request_body(self):
        body = {"model": self.model, "state": {
            "game": "Pudge Wars. A human skillshot team arena. Advise only; never control the player.",
            "view": "Current human self and team-shared visible entities only. Unseen enemies are unknown.",
            "observation": self.obs,
            "actions": self.actions, "strategies": self.strategies,
            "enemy_sightings": self.beliefs.context(),
        }, "questions": {
            "action": {"type": "choice", "instructions":
                "Choose the most useful next action for the HUMAN self now. Prioritize survival, ally rescues and coordinated catches. "
                "Only choose from supplied eligible actions. A potential hook is not a guaranteed hit. Choose none when uncertain.",
                "criteria": {k: v["title"] + ". " + v["why"] for k, v in self.actions.items()} | {"none": "No clear action to recommend."}},
            "strategy": {"type": "choice", "instructions":
                "Choose a useful plan for the HUMAN's next few exchanges, based on health, team spacing and visible opportunities. "
                "Treat the immediate action and longer plan as separate judgments. Choose none when uncertain.",
                "criteria": {k: v["title"] + ". " + v["why"] for k, v in self.strategies.items()} | {"none": "No clear strategy to recommend."}},
        }}
        body["questions"].update(self.beliefs.questions())
        return body

    async def evaluate(self, client):
        now = self.clock()
        if (not self.enabled or not self.api_key or not self.fresh() or now - self.viewer_at > 3
                or now < self.retry_at or now - self.request_at < REQUEST_INTERVAL):
            return
        generation, tick = self.generation, self.obs["tick"]
        body = self.request_body()
        self.request_at = now
        self.requests += 1
        try:
            async with client.post(ENDPOINT, json=body, headers={"Authorization": f"Bearer {self.api_key}"},
                                   timeout=ClientTimeout(total=1.5), allow_redirects=False) as response:
                if response.status != 200:
                    # Don't expose provider bodies or credentials in the public state.
                    if generation == self.generation:
                        self.status = "auth_error" if response.status in (401, 403) else "unavailable"
                        self.backoff(auth=response.status in (401, 403))
                    return
                payload = await response.json()
            answers = {key: choice_answer(payload, key, question["criteria"])
                       for key, question in body["questions"].items()}
        except (ClientError, asyncio.TimeoutError, ValueError, TypeError, AttributeError):
            if generation == self.generation:
                self.status = "unavailable"
                self.backoff()
            return
        if generation != self.generation or not self.enabled or not self.fresh():
            return
        if self.clock() - now > MAX_AGE or not 0 <= self.obs["tick"] - tick <= MAX_TICKS:
            return
        self.result = answers
        self.beliefs.accept(payload, body, tick)
        self.result_at, self.result_tick = self.clock(), tick
        self.latency_ms = round((self.clock() - now) * 1000)
        self.status, self.failures = "connected", 0

    def backoff(self, auth=False):
        self.failures += 1
        self.retry_at = float("inf") if auth else self.clock() + min(30, 2 ** min(self.failures, 5))
        self.result = {}

    async def run(self, client):
        # One worker per match, one in-flight request. Nothing queues old frames.
        while True:
            await self.evaluate(client)
            await asyncio.sleep(.1)

    def view(self, phase):
        now = self.clock()
        base = {"enabled": self.enabled, "configured": bool(self.api_key), "status": self.status,
                "model": self.model, "requests": self.requests, "latency_ms": self.latency_ms,
                "match_id": self.match_id, "tick": self.obs["tick"] if self.obs else None,
                "action": None, "strategy": None, "ttl_ms": 0}
        base["intel"] = self.beliefs.view(self.enabled and self.fresh() and phase == "playing")
        base["human"] = self.obs["self"] if self.obs else None
        base["team"] = [p for p in self.obs["visible"]["pudges"] if p["team"] == self.obs["self"]["team"]] if self.obs else []
        base["hooks"] = self.obs["visible"].get("hooks", []) if self.fresh() else []
        if not self.enabled or phase != "playing" or not self.fresh():
            base["status"] = "paused" if not self.enabled else ("waiting" if phase in ("ready", "starting") else "finished" if phase == "finished" else "stale")
            return base
        usable = (now - self.result_at <= MAX_AGE and 0 <= self.obs["tick"] - self.result_tick <= MAX_TICKS)
        def pick(key, available):
            chosen, confidence = self.result.get(key, (None, 0)) if usable else (None, 0)
            if chosen in available and confidence >= .6:
                item = available[chosen]
                return item | {"source": "jev", "confidence": confidence,
                               "tentative": confidence < item.get("threshold", .6)}
            return next(iter(available.values())) | {"source": "local", "confidence": None, "tentative": False}

        action = pick("action", self.actions)
        urgent = next((a for a in self.actions.values() if a["urgent"]), None)
        if urgent:
            action = urgent | {"source": "local", "confidence": None, "tentative": False}
        # Avoid flicker, but never hold an invalid target, urgent cue, or expired model answer.
        if (not urgent and self.held and self.held["id"] in self.actions and not self.held["urgent"]
                and now - self.held_at < 1.5 and (self.held["source"] == "local" or usable)):
            if action["id"] != self.held["id"]:
                action = self.actions[self.held["id"]] | {k: self.held[k] for k in ("source", "confidence", "tentative")}
        if not self.held or (action["id"], action["source"]) != (self.held["id"], self.held["source"]):
            self.held_at = now
        self.held = action
        base.update(action=action, strategy=pick("strategy", self.strategies), ttl_ms=1500)
        return base
