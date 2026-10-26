"""Train one Fresh Meat butcher against the bundled BASIC opponents."""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

from base import BasePolicy

MODES = [
    "noop",
    "walk",
    "hook",
    "blink",
    "attack",
    "place_wall",
    "place_mine",
    "place_ward",
    "ping",
    "halt",
]
UPGRADES = ["none", 0, 1, 2, 3]
POWERS = ["none", *range(10)]
ROT = ["keep", "on", "off"]
COORDINATES = list(range(128))
MAX_PLAYERS = 10
MAX_HOOKS = 10
MAX_RUNES = 4

host: subprocess.Popen[str]
teacher: BasePolicy
observation: dict
seat: int
seats: int
max_ticks: int


def exchange(message: dict) -> dict:
    host.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
    host.stdin.flush()
    return json.loads(host.stdout.readline())


def scene() -> dict:
    me = observation["self"]
    return {
        "tick": observation["tick"],
        "max_ticks": max_ticks,
        "team": me["team"],
        "self": {
            key: me[key]
            for key in (
                "x",
                "y",
                "hp",
                "max_hp",
                "hook_ready",
                "blink_ready",
                "points",
                "gold",
                "in_shop",
                "rot",
                "hooked",
                "upgrades",
                "items",
            )
        },
        "pudges": [
            {key: pudge[key] for key in ("id", "slot", "team", "x", "y", "hp", "alive")}
            for pudge in observation["visible"]["pudges"]
        ],
        "hooks": [
            {key: hook[key] for key in ("team", "x", "y", "victim", "flying")}
            for hook in observation["visible"]["hooks"]
        ],
        "runes": [
            {key: rune[key] for key in ("kind", "x", "y")}
            for rune in observation["visible"]["runes"]
        ],
        "rune_next": observation["rune_next"],
        "river_west": observation["river_west"],
        "river_east": observation["river_east"],
        "score": observation["score"],
    }


def current() -> dict:
    view = scene()
    candidates = {
        "hold": {
            "decision": {
                "mode": "noop",
                "x": 0,
                "y": 0,
                "target_id": 0,
                "buy_upgrade": "none",
                "buy_power": "none",
                "rot": "keep",
            },
            "criterion": "Hold the current order",
        },
        "river": {
            "decision": {
                "mode": "walk",
                "x": 64,
                "y": round(view["self"]["y"]),
                "target_id": 0,
                "buy_upgrade": "none",
                "buy_power": "none",
                "rot": "keep",
            },
            "criterion": "Walk toward the river",
        },
    }
    for pudge in view["pudges"]:
        if pudge["team"] != view["team"] and pudge["alive"]:
            target = {
                "x": round(pudge["x"]),
                "y": round(pudge["y"]),
                "target_id": 0,
                "buy_upgrade": "none",
                "buy_power": "none",
                "rot": "keep",
            }
            candidates[f"walk_{pudge['slot']}"] = {
                "decision": {"mode": "walk", **target},
                "criterion": f"Chase visible enemy {pudge['slot']}",
            }
            candidates[f"attack_{pudge['slot']}"] = {
                "decision": {"mode": "attack", **target, "target_id": pudge["id"]},
                "criterion": f"Attack visible enemy {pudge['slot']}",
            }
            if view["self"]["hook_ready"]:
                candidates[f"hook_{pudge['slot']}"] = {
                    "decision": {"mode": "hook", **target},
                    "criterion": f"Hook visible enemy {pudge['slot']}",
                }
    return {
        "kind": "decision",
        "game": "pudge-wars",
        "decision_id": observation["tick"],
        "seat": 0,
        "engine_seat": seat,
        "turn": observation["tick"],
        "semantic_view": view,
        "inbox": [],
        "messages": [
            {
                "role": "system",
                "content": "Control one butcher using visible state. Choose one spatial action and optional purchase or Rot setting.",
            },
            {"role": "user", "content": json.dumps(view, separators=(",", ":"))},
        ],
        "speech_messages": [],
        "action_schema": {
            "type": "object",
            "properties": {
                "mode": {"enum": MODES},
                "x": {"type": "integer", "minimum": 0, "maximum": 127},
                "y": {"type": "integer", "minimum": 0, "maximum": 127},
                "target_id": {"type": "integer", "minimum": 0, "maximum": 10},
                "buy_upgrade": {"enum": UPGRADES},
                "buy_power": {"enum": POWERS},
                "rot": {"enum": ROT},
            },
            "required": [
                "mode",
                "x",
                "y",
                "target_id",
                "buy_upgrade",
                "buy_power",
                "rot",
            ],
        },
        "typed_question": {
            "state": view,
            "instructions": "Choose the action most likely to increase your team's kill margin.",
            "candidates": candidates,
        },
    }


def encoding() -> dict:
    me = observation["self"]
    values = [
        observation["tick"] / max_ticks,
        seat / seats,
        me["team"],
        observation["score"]["west"] / observation["kill_goal"],
        observation["score"]["east"] / observation["kill_goal"],
        me["x"] / 128,
        me["y"] / 128,
        me["hp"] / me["max_hp"],
        float(me["hook_ready"]),
        float(me["blink_ready"]),
        me["gold"] / 100,
        me["points"] / 10,
        float(me["in_shop"]),
        float(me["rot"]),
        float(me["hooked"]),
        *[rank / 10 for rank in me["upgrades"]],
        *[rank / 5 for rank in me["items"]],
        observation["rune_next"]["soon"] / 1000,
    ]
    pudges = sorted(observation["visible"]["pudges"], key=lambda pudge: pudge["slot"])
    for pudge in pudges:
        values.extend(
            [
                1.0,
                pudge["id"] / MAX_PLAYERS,
                pudge["slot"] / MAX_PLAYERS,
                float(pudge["team"]),
                pudge["x"] / 128,
                pudge["y"] / 128,
                pudge["hp"] / pudge["max_hp"],
                float(pudge["alive"]),
                float(pudge["hook_ready"]),
                float(pudge["blink_ready"]),
            ]
        )
    values.extend([0.0] * (10 * (MAX_PLAYERS - len(pudges))))
    hooks = sorted(
        observation["visible"]["hooks"],
        key=lambda hook: (hook["x"] - me["x"]) ** 2 + (hook["y"] - me["y"]) ** 2,
    )[:MAX_HOOKS]
    for hook in hooks:
        values.extend(
            [
                1.0,
                float(hook["team"]),
                hook["x"] / 128,
                hook["y"] / 128,
                float(hook["flying"]),
            ]
        )
    values.extend([0.0] * (5 * (MAX_HOOKS - len(hooks))))
    runes = sorted(
        observation["visible"]["runes"],
        key=lambda rune: (rune["x"] - me["x"]) ** 2 + (rune["y"] - me["y"]) ** 2,
    )[:MAX_RUNES]
    for rune in runes:
        values.extend([1.0, rune["kind"] / 10, rune["x"] / 128, rune["y"] / 128])
    values.extend([0.0] * (4 * (MAX_RUNES - len(runes))))
    targets = [0, *[pudge["id"] for pudge in pudges]]
    targets.extend([None] * (MAX_PLAYERS + 1 - len(targets)))
    return {
        "decision_id": observation["tick"],
        "values": values,
        "action_heads": [
            {"name": "mode", "choices": MODES},
            {"name": "x", "choices": COORDINATES},
            {"name": "y", "choices": COORDINATES},
            {"name": "target_id", "choices": targets},
            {"name": "buy_upgrade", "choices": UPGRADES},
            {"name": "buy_power", "choices": POWERS},
            {"name": "rot", "choices": ROT},
        ],
    }


def terminal() -> dict:
    score = observation["score"]
    ours = score["west"] if observation["self"]["team"] == 0 else score["east"]
    theirs = score["east"] if observation["self"]["team"] == 0 else score["west"]
    return {
        "kind": "terminal",
        "scores": {"0": ours},
        "utilities": {"0": (ours - theirs) / observation["kill_goal"]},
    }


def reset(request: dict) -> dict:
    global observation, seat, seats, max_ticks, teacher
    if request["players"] != 1:
        raise ValueError("Fresh Meat trains one controlled butcher")
    seed = (
        int.from_bytes(hashlib.sha256(request["seed"].encode()).digest()[:4], "little")
        & 0x7FFFFFFF
    )
    seat = seed % seats
    teacher = BasePolicy()
    observation = exchange(
        {
            "kind": "reset",
            "seats": seats,
            "seed": seed,
            "learner_slot": seat,
            "max_ticks": max_ticks,
        }
    )["observation"]
    return current()


def teacher_action() -> dict:
    raw = teacher.choose_action(observation)
    modes = (
        ("hook", "hook_to"),
        ("blink", "blink_to"),
        ("place_ward", "place_ward"),
        ("place_wall", "place_wall"),
        ("place_mine", "place_mine"),
        ("attack", "attack_target"),
        ("walk", "walk_to"),
        ("ping", "ping"),
    )
    mode = next(
        (name for name, key in modes if key in raw), "halt" if "halt" in raw else "noop"
    )
    key = dict(modes)[mode] if mode not in ("noop", "halt") else None
    point = raw[key] if key and mode != "attack" else [0, 0]
    return {
        "mode": mode,
        "x": max(0, min(127, round(point[0]))),
        "y": max(0, min(127, round(point[1]))),
        "target_id": raw["attack_target"] if mode == "attack" else 0,
        "buy_upgrade": raw["buy_upgrade"][0] if raw.get("buy_upgrade") else "none",
        "buy_power": raw["buy_power"][0] if raw.get("buy_power") else "none",
        "rot": "on"
        if raw.get("rot") is True
        else "off"
        if raw.get("rot") is False
        else "keep",
    }


def handle(request: dict) -> dict:
    global observation
    if request["kind"] == "reset":
        return reset(request)
    if request["kind"] == "encode":
        return encoding()
    if request["kind"] == "teacher":
        return {"response": json.dumps(teacher_action(), separators=(",", ":"))}
    if request["kind"] == "step":
        if request["decision_id"] != observation["tick"]:
            raise ValueError("Action belongs to another tick")
        action = json.loads(request["response"])
        heads = encoding()["action_heads"]
        if any(action[head["name"]] not in head["choices"] for head in heads):
            raise ValueError("Action does not match Fresh Meat codec")
        command = {}
        if action["mode"] in ("walk", "hook", "blink"):
            command[action["mode"] + "_to"] = [action["x"], action["y"]]
        elif action["mode"] in ("place_wall", "place_mine", "place_ward", "ping"):
            command[action["mode"]] = [action["x"], action["y"]]
        elif action["mode"] == "attack":
            command["attack_target"] = action["target_id"]
        elif action["mode"] == "halt":
            command["halt"] = True
        if action["buy_upgrade"] != "none":
            command["buy_upgrade"] = action["buy_upgrade"]
        if action["buy_power"] != "none":
            command["buy_power"] = action["buy_power"]
        if action["rot"] != "keep":
            command["rot"] = action["rot"] == "on"
        reply = exchange(
            {"kind": "step", "tick": observation["tick"], "action": command}
        )
        observation = reply["observation"]
        return {
            "kind": "accepted",
            "action": action,
            "observation": terminal() if reply["done"] else current(),
        }
    raise ValueError("Unknown bridge command")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(
            "usage: python coworld/player/training_bridge.py HOST SEATS MAX_TICKS"
        )
    seats, max_ticks = int(sys.argv[2]), int(sys.argv[3])
    if seats not in (2, 4, 6, 8, 10) or max_ticks < 1:
        raise ValueError("Require an even roster of 2-10 and positive max ticks")
    host = subprocess.Popen(
        [sys.argv[1]],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
        cwd=Path(__file__).resolve().parents[2],
    )
    for line in sys.stdin:
        print(json.dumps(handle(json.loads(line)), separators=(",", ":")), flush=True)
