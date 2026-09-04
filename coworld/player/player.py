from __future__ import annotations

import asyncio
import json
import math
import os
from dataclasses import dataclass
from typing import Any, cast

# Bundled league personalities. `idle` used to stand at spawn; it now
# aliases rusher so old seat env still plays.
PERSONALITY = os.environ.get("PUDGE_PERSONALITY", "rusher")
if PERSONALITY == "idle":
    PERSONALITY = "rusher"

BLINK_RANGE = 48.0
WALK_TILES_PER_TICK = 27_000.0 / 60_000.0
VEL_SAMPLE = 8
RESPAWN_TICKS = 32 * 4
GHOST_FORGET = 32 * 12
Y_MIN = 16.0
Y_MAX = 111.0

_tracks: dict[int, "Ghost"] = {}
_last_tick = -1
_dodge_side = 0


@dataclass
class Ghost:
    id: int
    x: float
    y: float
    vx: float = 0.0
    vy: float = 0.0
    tick: int = 0
    hp: float = 840.0
    layer: int = 1
    in_river: bool = False
    alive: bool = True
    sample_x: float = 0.0
    sample_y: float = 0.0
    sample_tick: int = -8


def reset_memory() -> None:
    global _last_tick, _dodge_side
    _tracks.clear()
    _last_tick = -1
    _dodge_side = 0


async def main() -> None:
    import websockets

    from coworld.examples.pudgewars.shared.log_shipper import get_logger

    logger = get_logger("pudgewars.player")
    url = os.environ["COWORLD_PLAYER_WS_URL"]
    logger.info("connecting personality=%s", PERSONALITY)
    async with websockets.connect(url, ping_timeout=None) as websocket:
        async for raw_message in websocket:
            message = cast(dict[str, Any], json.loads(raw_message))
            if message.get("type") == "final" or message.get("done"):
                logger.info("received final message, exiting")
                return
            if message.get("type") == "observation":
                await websocket.send(json.dumps(choose_action(message)))


def choose_action(obs: dict[str, Any]) -> dict[str, Any]:
    global _dodge_side
    me = obs["self"]
    if not me.get("alive"):
        return {}

    river_west = float(obs["river_west"])
    river_east = float(obs["river_east"])
    width = float(obs.get("width", 128))
    height = float(obs.get("height", 128))
    tick = int(obs.get("tick", 0))
    visible = obs.get("visible", {})
    pudges = list(visible.get("pudges") or [])
    hooks = list(visible.get("hooks") or [])
    runes = list(visible.get("runes") or [])
    ping = obs.get("ally_ping")

    _sync_clock(tick)

    enemies = [
        p for p in pudges
        if p.get("team") != me["team"] and p.get("alive")
    ]
    allies = [
        p for p in pudges
        if p.get("team") == me["team"] and p.get("alive")
        and p.get("id") != me.get("id")
    ]
    _update_tracks(enemies, tick)

    hooked = [p for p in enemies if p.get("hooked")]
    drowning = [
        p for p in enemies
        if p.get("in_river") or int(p.get("layer", -1)) == 2
    ]
    saves = [
        p for p in allies
        if p.get("hooked") or p.get("in_river") or int(p.get("layer", -1)) == 2
    ]
    close = [p for p in enemies if _dist(me, p) <= 5.2]
    prey_rot = any(_dist(me, p) <= 8 for p in enemies)
    foreign_rot = any(
        p.get("rot") and _dist(me, p) <= 8
        for p in pudges
        if p.get("id") != me.get("id")
    )
    inbound = [
        h for h in hooks
        if h.get("team") != me["team"]
        and h.get("flying", True)
        and _dist(me, h) <= 22
    ]
    carrying = [
        h for h in inbound
        if h.get("victim") not in (None, 0)
    ]
    own_hook = next(
        (
            h for h in hooks
            if h.get("flying", True)
            and h.get("owner_id") == me.get("id")
            and h.get("victim") in (None, 0)
        ),
        None,
    )
    threat = _nearest(me, inbound)

    seen = hooked[0] if hooked else drowning[0] if drowning else _nearest(
        me, enemies
    )
    ghost_aim, ghost_chance = _best_ghost(
        me, tick, river_west, river_east, width, height, ping
    )
    target = seen
    aim = _lead_point(me, target, width, height) if target is not None else None
    if aim is None and ghost_aim is not None:
        aim = ghost_aim
        target = {
            "x": ghost_aim[0],
            "y": ghost_aim[1],
            "shield": False,
            "ghost": True,
        }

    camper = PERSONALITY == "camper"
    sniper = PERSONALITY == "sniper"
    hold_x = _home_edge(me, river_west, river_east, camper or sniper)
    lane = _lane_y(me, obs, seen if seen is not None else (
        {"y": ghost_aim[1]} if ghost_aim is not None else None
    ))

    if threat is None:
        _dodge_side = 0

    low_hp = float(me["hp"]) * 100 < float(me.get("max_hp", 840)) * 40
    in_river = bool(me.get("in_river") or int(me.get("layer", 0)) == 2)
    dump_chase = bool(drowning or any(
        int(p.get("layer", -1)) == 2 for p in hooked
    ))

    action: dict[str, Any] = {}

    want_rot = (
        prey_rot
        and not in_river
        and not (target and target.get("shield"))
        and float(me["hp"]) * 100 >= float(me.get("max_hp", 840)) * 40
        and not sniper
    )
    if want_rot != bool(me.get("rot")):
        action["rot_toggle"] = True

    blink = _pick_blink(
        me,
        threat,
        own_hook,
        hooked,
        drowning,
        dump_chase,
        low_hp,
        in_river,
        seen,
        hold_x,
        river_west,
        river_east,
        height,
    )
    if blink is not None:
        action["blink_to"] = blink
        if me.get("hook_ready") and not in_river:
            thrown = _pick_hook(
                me, target, aim, seen, ghost_aim, ghost_chance,
                carrying, inbound, saves, hooked, drowning, runes,
                camper, sniper, tick, width, height,
                river_west, river_east,
            )
            if thrown is not None:
                action["hook_to"] = thrown
        return action

    if foreign_rot and not want_rot:
        action["walk_to"] = [float(me.get("home_x", hold_x)), lane]
        return action

    if close and not sniper and not (target and target.get("shield")):
        action["attack_target"] = int(close[0]["id"])
    elif me.get("hook_ready"):
        thrown = _pick_hook(
            me, target, aim, seen, ghost_aim, ghost_chance,
            carrying, inbound, saves, hooked, drowning, runes,
            camper, sniper, tick, width, height,
            river_west, river_east,
        )
        if thrown is not None:
            action["hook_to"] = thrown

    if threat is not None:
        if _dodge_side == 0:
            _dodge_hop(me, threat, river_west, river_east, height)
        step = -2.0 if int(me["team"]) == 0 else 2.0
        action["walk_to"] = [
            float(me["x"]) + step,
            float(me["y"]) + _dodge_side * 10,
        ]
    elif in_river:
        action["walk_to"] = [hold_x, float(me["y"])]
    elif not camper and not sniper and seen is not None and not me.get("hooked"):
        if _dist(me, seen) <= 52:
            action["walk_to"] = [float(seen["x"]), float(seen["y"])]
        else:
            action["walk_to"] = [hold_x, float(seen["y"])]
    elif seen is None and ghost_aim is not None and ghost_chance >= 0.2:
        action["walk_to"] = [hold_x, ghost_aim[1]]
    else:
        action["walk_to"] = [hold_x, lane]

    return action


def _pick_blink(
    me: dict[str, Any],
    threat: dict[str, Any] | None,
    own_hook: dict[str, Any] | None,
    hooked: list[dict[str, Any]],
    drowning: list[dict[str, Any]],
    dump_chase: bool,
    low_hp: bool,
    in_river: bool,
    seen: dict[str, Any] | None,
    hold_x: float,
    river_west: float,
    river_east: float,
    height: float,
) -> list[float] | None:
    if not me.get("blink_ready"):
        return None
    if in_river:
        if dump_chase and not low_hp:
            prey = drowning[0] if drowning else hooked[0]
            return _clamp_point(
                [float(prey["x"]), float(prey["y"])], height
            )
        return _clamp_point([hold_x, float(me["y"])], height)
    if threat is not None:
        return _dodge_hop(me, threat, river_west, river_east, height)
    if own_hook is not None:
        stretch = _stretch_landing(
            me, own_hook, river_west, river_east, height
        )
        if stretch is not None:
            return stretch
    if dump_chase and not low_hp:
        prey = drowning[0] if drowning else next(
            (p for p in hooked if int(p.get("layer", -1)) == 2),
            None,
        )
        if prey is not None:
            return _clamp_point(
                [float(prey["x"]), float(prey["y"])], height
            )
    if hooked and not low_hp:
        prey = hooked[0]
        if int(prey.get("layer", -1)) != int(me.get("layer", 0)):
            if PERSONALITY == "rusher":
                return _clamp_point(
                    [float(prey["x"]), float(prey["y"])], height
                )
            return _clamp_point([hold_x, float(prey["y"])], height)
        if _dist(me, prey) > 10:
            return _clamp_point(
                [float(prey["x"]), float(prey["y"])], height
            )
    if (
        PERSONALITY == "rusher"
        and seen is not None
        and not low_hp
        and not seen.get("shield")
        and int(seen.get("layer", 0)) != int(me.get("layer", 0))
        and _dist(me, seen) <= BLINK_RANGE + 8
        and float(me["hp"]) + 40 >= float(seen.get("hp", 840))
    ):
        return _clamp_point([float(seen["x"]), float(seen["y"])], height)
    return None


def _pick_hook(
    me: dict[str, Any],
    target: dict[str, Any] | None,
    aim: list[float] | None,
    seen: dict[str, Any] | None,
    ghost_aim: list[float] | None,
    ghost_chance: float,
    carrying: list[dict[str, Any]],
    inbound: list[dict[str, Any]],
    saves: list[dict[str, Any]],
    hooked: list[dict[str, Any]],
    drowning: list[dict[str, Any]],
    runes: list[dict[str, Any]],
    camper: bool,
    sniper: bool,
    tick: int,
    width: float,
    height: float,
    river_west: float,
    river_east: float,
) -> list[float] | None:
    if carrying:
        h = carrying[0]
        return [float(h["x"]), float(h["y"])]
    if inbound and _dist(me, inbound[0]) <= 14:
        h = inbound[0]
        return [float(h["x"]), float(h["y"])]
    if saves:
        s = saves[0]
        return [float(s["x"]), float(s["y"])]
    if hooked:
        t = hooked[0]
        return [float(t["x"]), float(t["y"])]
    if drowning:
        t = drowning[0]
        return [float(t["x"]), float(t["y"])]
    if (
        seen is not None
        and aim is not None
        and not seen.get("shield")
        and not seen.get("ghost")
    ):
        if sniper and float(seen.get("hp", 840)) * 2 > float(
            me.get("max_hp", 840)
        ):
            pass
        elif _in_range(me, seen, _engage_range(camper or sniper)):
            return aim
    if ghost_aim is not None and ghost_chance >= _ghost_throw_floor():
        return ghost_aim
    if tick > 8:
        rune = _nearest_rune(me, runes, 26 if camper or sniper else 36)
        if rune is not None:
            return [float(rune["x"]), float(rune["y"])]
        if ghost_aim is not None:
            return ghost_aim
        return _fog_poke(me, river_west, river_east, width, height)
    return None


def _ghost_throw_floor() -> float:
    if PERSONALITY == "sniper":
        return 0.36
    if PERSONALITY == "camper":
        return 0.22
    return 0.14


def _sync_clock(tick: int) -> None:
    global _last_tick
    if _last_tick >= 0 and tick + 8 < _last_tick:
        reset_memory()
    _last_tick = tick


def _update_tracks(enemies: list[dict[str, Any]], tick: int) -> None:
    seen_ids: set[int] = set()
    for enemy in enemies:
        eid = int(enemy.get("id", 0))
        if eid == 0:
            continue
        seen_ids.add(eid)
        x = float(enemy["x"])
        y = float(enemy["y"])
        ghost = _tracks.get(eid)
        if ghost is None or ghost.id != eid:
            _tracks[eid] = Ghost(
                id=eid,
                x=x,
                y=y,
                tick=tick,
                hp=float(enemy.get("hp", 840)),
                layer=int(enemy.get("layer", 1)),
                in_river=bool(
                    enemy.get("in_river") or int(enemy.get("layer", -1)) == 2
                ),
                alive=True,
                sample_x=x,
                sample_y=y,
                sample_tick=tick,
            )
            continue
        if tick - ghost.sample_tick >= VEL_SAMPLE:
            ghost.vx = x - ghost.sample_x
            ghost.vy = y - ghost.sample_y
            ghost.sample_x = x
            ghost.sample_y = y
            ghost.sample_tick = tick
        ghost.x = x
        ghost.y = y
        ghost.tick = tick
        ghost.hp = float(enemy.get("hp", ghost.hp))
        ghost.layer = int(enemy.get("layer", ghost.layer))
        ghost.in_river = bool(
            enemy.get("in_river") or ghost.layer == 2
        )
        ghost.alive = True
    stale = [
        eid for eid, ghost in _tracks.items()
        if eid not in seen_ids and tick - ghost.tick > GHOST_FORGET
    ]
    for eid in stale:
        del _tracks[eid]


def _best_ghost(
    me: dict[str, Any],
    tick: int,
    river_west: float,
    river_east: float,
    width: float,
    height: float,
    ping: Any,
) -> tuple[list[float] | None, float]:
    best_point: list[float] | None = None
    best_chance = 0.0
    for ghost in _tracks.values():
        if ghost.tick == tick:
            continue
        point, chance, _ = _predict_ghost(
            me, ghost, tick, river_west, river_east, width, height
        )
        if chance > best_chance:
            best_chance = chance
            best_point = point
    if isinstance(ping, dict) and ping.get("x") is not None:
        age = tick - int(ping.get("tick", tick))
        if 0 <= age < 96:
            ping_point = [
                float(ping["x"]),
                max(Y_MIN, min(height - 17.0, float(ping["y"]))),
            ]
            ping_chance = max(0.25, 0.7 - age / 160.0)
            if ping_chance > best_chance:
                return ping_point, ping_chance
    return best_point, best_chance


def _predict_ghost(
    me: dict[str, Any],
    ghost: Ghost,
    tick: int,
    river_west: float,
    river_east: float,
    width: float,
    height: float,
) -> tuple[list[float], float, float]:
    age = max(tick - ghost.tick, 0)
    lip = _far_lip(me, river_west, river_east)
    far_lo, far_hi = _far_bank_span(me, river_west, river_east, width)
    pred_x = ghost.x + ghost.vx * age / float(VEL_SAMPLE)
    pred_y = ghost.y + ghost.vy * age / float(VEL_SAMPLE)
    # A vanished butcher cannot still be in the river or on our bank:
    # those columns stay lit. The ghost lives on the far bank.
    if ghost.in_river or ghost.layer == 2:
        pred_x = lip + ghost.vx * age / float(VEL_SAMPLE * 2)
    pred_x = max(far_lo, min(far_hi, pred_x))
    pred_y = max(Y_MIN, min(height - 17.0, pred_y))
    lip_mix = min(1.0, age / 96.0)
    pred_x = pred_x * (1.0 - 0.6 * lip_mix) + lip * (0.6 * lip_mix)
    pred_x = max(far_lo, min(far_hi, pred_x))
    walk_reach = WALK_TILES_PER_TICK * float(age)
    uncertainty = walk_reach + min(BLINK_RANGE, 6.0 + age * 0.35)
    recency = max(0.0, 1.0 - age / float(GHOST_FORGET))
    lip_bias = 1.0 if abs(ghost.x - lip) < 14 or ghost.in_river else 0.7
    hp_bias = 1.1 if ghost.hp <= 180 else 1.0
    chance = recency * recency * lip_bias * hp_bias
    if ghost.hp <= 80 and age < RESPAWN_TICKS:
        chance *= 0.35
        pred_x = _far_pad_x(me)
    return [pred_x, pred_y], min(1.0, chance), uncertainty


def _engage_range(patient: bool) -> float:
    return 44.0 if patient else 34.0


def _home_edge(
    me: dict[str, Any], river_west: float, river_east: float, patient: bool
) -> float:
    standoff = 16.0 if patient else 4.0
    if int(me["team"]) == 0:
        return (river_west - 1.0) - standoff
    return (river_east + 1.0) + standoff


def _far_lip(
    me: dict[str, Any], river_west: float, river_east: float
) -> float:
    if int(me["team"]) == 0:
        return river_east + 1.0
    return river_west - 1.0


def _far_bank_span(
    me: dict[str, Any],
    river_west: float,
    river_east: float,
    width: float,
) -> tuple[float, float]:
    if int(me["team"]) == 0:
        return river_east + 1.0, width - 15.0
    return 14.0, river_west - 1.0


def _far_pad_x(me: dict[str, Any]) -> float:
    return 106.0 if int(me["team"]) == 0 else 22.0


def _fog_poke(
    me: dict[str, Any],
    river_west: float,
    river_east: float,
    width: float,
    height: float,
) -> list[float]:
    lip = _far_lip(me, river_west, river_east)
    poke_x = lip + 8.0 if int(me["team"]) == 0 else lip - 8.0
    poke_x = max(14.0, min(width - 15.0, poke_x))
    ghost = next(iter(_tracks.values()), None)
    poke_y = float(ghost.y) if ghost is not None else float(me["y"])
    return [
        poke_x,
        max(Y_MIN, min(height - 17.0, poke_y)),
    ]


def _lane_y(
    me: dict[str, Any], obs: dict[str, Any], target: dict[str, Any] | None
) -> float:
    height = float(obs.get("height", 128))
    slot = int(me.get("slot", 0))
    band = height / 4.0
    y = band * ((slot % 3) + 1)
    if target is not None:
        y = (y + float(target["y"])) / 2.0
    else:
        ghost = next(iter(_tracks.values()), None)
        if ghost is not None:
            y = (y + ghost.y) / 2.0
    return max(Y_MIN, min(height - 17.0, y))


def _dodge_hop(
    me: dict[str, Any],
    threat: dict[str, Any],
    river_west: float,
    river_east: float,
    height: float,
) -> list[float]:
    global _dodge_side
    if _dodge_side == 0:
        _dodge_side = -1 if float(threat["y"]) > float(me["y"]) else 1
        if float(me["y"]) < 20:
            _dodge_side = 1
        if float(me["y"]) > 108:
            _dodge_side = -1
    if int(me["team"]) == 0:
        hop_x = min(float(me["x"]) - 16.0, river_west - 1.0)
    else:
        hop_x = max(float(me["x"]) + 16.0, river_east + 1.0)
    hop_y = float(me["y"]) + _dodge_side * 36.0
    return [
        max(14.0, min(113.0, hop_x)),
        max(Y_MIN, min(height - 17.0, hop_y)),
    ]


def _stretch_landing(
    me: dict[str, Any],
    hook: dict[str, Any],
    river_west: float,
    river_east: float,
    height: float,
) -> list[float] | None:
    dx = float(hook["x"]) - float(me["x"])
    dy = float(hook["y"]) - float(me["y"])
    dist = math.hypot(dx, dy)
    if dist < 12:
        return None
    scale = BLINK_RANGE / dist
    hop_x = float(me["x"]) + dx * scale
    hop_y = float(me["y"]) + dy * scale
    if PERSONALITY != "rusher":
        if int(me["team"]) == 0:
            hop_x = min(hop_x, river_west - 1.0)
        else:
            hop_x = max(hop_x, river_east + 1.0)
    return _clamp_point([hop_x, hop_y], height)


def _clamp_point(point: list[float], height: float) -> list[float]:
    return [
        max(8.0, min(119.0, point[0])),
        max(Y_MIN, min(height - 17.0, point[1])),
    ]


def _lead_point(
    me: dict[str, Any], target: dict[str, Any], width: float, height: float
) -> list[float]:
    eid = int(target.get("id", 0))
    ghost = _tracks.get(eid)
    vx = ghost.vx if ghost is not None else 0.0
    vy = ghost.vy if ghost is not None else 0.0
    span = max(_dist(me, target), 8.0)
    ax = float(target["x"]) + vx * span / 9.0
    ay = float(target["y"]) + vy * span / 9.0
    return [
        max(0.5, min(width - 0.5, ax)),
        max(0.5, min(height - 0.5, ay)),
    ]


def _nearest(
    me: dict[str, Any], others: list[dict[str, Any]]
) -> dict[str, Any] | None:
    best = None
    best_d = 1e9
    for other in others:
        d = _dist(me, other)
        if d < best_d:
            best = other
            best_d = d
    return best


def _nearest_rune(
    me: dict[str, Any], runes: list[dict[str, Any]], reach: float
) -> dict[str, Any] | None:
    rune = _nearest(me, runes)
    if rune is None or _dist(me, rune) > reach:
        return None
    return rune


def _dist(a: dict[str, Any], b: dict[str, Any]) -> float:
    return math.hypot(float(a["x"]) - float(b["x"]), float(a["y"]) - float(b["y"]))


def _in_range(me: dict[str, Any], other: dict[str, Any], reach: float) -> bool:
    return _dist(me, other) <= reach


if __name__ == "__main__":
    asyncio.run(main())
