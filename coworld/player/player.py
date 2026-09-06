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

BLINK_RANGE = 20.0
WALK_TILES_PER_TICK = 27_000.0 / 60_000.0
VEL_SAMPLE = 8
RESPAWN_TICKS = 32 * 4
GHOST_FORGET = 32 * 12
Y_MIN = 16.0
Y_MAX = 111.0
MAX_UPGRADE = 10
MAX_ITEM_RANK = 5
# Kill-point skills: 0 damage, 1 distance, 2 speed, 3 radius.
UPGRADE_ORDER = {
    "rusher": (3, 1, 2, 0),  # radius, distance, speed, damage
    "camper": (3, 1, 2, 0),
    "sniper": (1, 3, 0, 2),  # distance first; radius next
    "partner": (3, 1, 2, 0),  # BASIC v66: radius, distance, speed, damage
}
SHOP_FLASK = 0
SHOP_BIG_HOOK = 3
SHOP_BOOTS = 5
SHOP_LONGSHOT = 6
SHOP_WALL = 7
SHOP_MINE = 8
SHOP_WARD = 9
SHOP_PRICES = {
    SHOP_FLASK: 5,
    SHOP_BIG_HOOK: 6,
    SHOP_BOOTS: 10,
    SHOP_LONGSHOT: 12,
    SHOP_WALL: 10,
    SHOP_MINE: 10,
    SHOP_WARD: 8,
}

_tracks: dict[int, "Ghost"] = {}
_last_tick = -1
_dodge_side = 0
_last_fly: tuple[float, float, int] | None = None
_last_seen: tuple[int, float, float, int] | None = None


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


def _levels(me: dict[str, Any], key: str, n: int) -> list[int]:
    raw = me.get(key) or []
    out: list[int] = []
    for i in range(n):
        try:
            out.append(int(raw[i]))
        except (IndexError, TypeError, ValueError, KeyError):
            out.append(0)
    return out


def _item_ranks(me: dict[str, Any]) -> list[int]:
    if me.get("items"):
        return _levels(me, "items", 5)
    return _levels(me, "item_ranks", 5)


def _upgrade(me: dict[str, Any], kind: int) -> int:
    return _levels(me, "upgrades", 4)[kind]


def _spend_upgrades(me: dict[str, Any]) -> list[int]:
    left = int(me.get("points") or 0)
    if left <= 0:
        return []
    levels = _levels(me, "upgrades", 4)
    order = UPGRADE_ORDER.get(PERSONALITY, UPGRADE_ORDER["rusher"])
    bought: list[int] = []
    while left > 0:
        kind = next((k for k in order if levels[k] < MAX_UPGRADE), None)
        if kind is None:
            break
        bought.append(kind)
        levels[kind] += 1
        left -= 1
    return bought


def _spend_shop(me: dict[str, Any]) -> list[int]:
    if not me.get("in_shop"):
        return []
    gold = int(me.get("gold") or 0)
    if gold <= 0:
        return []
    ranks = _item_ranks(me)
    buys: list[int] = []
    hp = float(me.get("hp") or 0)
    max_hp = float(me.get("max_hp", 840))
    if hp * 2 < max_hp and gold >= SHOP_PRICES[SHOP_FLASK]:
        buys.append(SHOP_FLASK)
        gold -= SHOP_PRICES[SHOP_FLASK]

    def take(item: int, rank_i: int | None, price: int) -> None:
        nonlocal gold
        if gold < price:
            return
        if rank_i is not None and ranks[rank_i] >= MAX_ITEM_RANK:
            return
        buys.append(item)
        gold -= price
        if rank_i is not None:
            ranks[rank_i] += 1

    if PERSONALITY == "partner":
        take(SHOP_BIG_HOOK, None, SHOP_PRICES[SHOP_BIG_HOOK])
        take(SHOP_LONGSHOT, 1, SHOP_PRICES[SHOP_LONGSHOT])
        take(SHOP_BOOTS, 0, SHOP_PRICES[SHOP_BOOTS])
        take(SHOP_WALL, 2, SHOP_PRICES[SHOP_WALL])
        take(SHOP_MINE, 3, SHOP_PRICES[SHOP_MINE])
        take(SHOP_WARD, 4, SHOP_PRICES[SHOP_WARD])
        return buys
    take(SHOP_LONGSHOT, 1, SHOP_PRICES[SHOP_LONGSHOT])
    take(SHOP_BOOTS, 0, SHOP_PRICES[SHOP_BOOTS])
    take(SHOP_BIG_HOOK, None, SHOP_PRICES[SHOP_BIG_HOOK])
    take(SHOP_WALL, 2, SHOP_PRICES[SHOP_WALL])
    take(SHOP_MINE, 3, SHOP_PRICES[SHOP_MINE])
    take(SHOP_WARD, 4, SHOP_PRICES[SHOP_WARD])
    return buys


def _want_shop(me: dict[str, Any]) -> bool:
    gold = int(me.get("gold") or 0)
    if gold < 10 or me.get("in_shop"):
        return False
    ranks = _item_ranks(me)
    if ranks[0] < MAX_ITEM_RANK or ranks[1] < MAX_ITEM_RANK:
        return True
    hp = float(me.get("hp") or 0)
    max_hp = float(me.get("max_hp", 840))
    return hp * 2 < max_hp and gold >= 5


def _place_gadgets(
    me: dict[str, Any],
    river_west: float,
    river_east: float,
    action: dict[str, Any],
) -> None:
    if int(me.get("layer", 0)) == 2:
        return
    ranks = _item_ranks(me)
    if ranks[2] <= 0 and ranks[3] <= 0 and ranks[4] <= 0:
        return
    x = float(me["x"])
    y = float(me["y"])
    if int(me["team"]) == 0:
        wall_x = min(x + 3.0, river_west)
    else:
        wall_x = max(x - 3.0, river_east)
    if ranks[2] > 0:
        action.setdefault("place_wall", [wall_x, y])
    if ranks[3] > 0:
        mine_y = max(Y_MIN, min(Y_MAX, y + 3.0))
        action.setdefault("place_mine", [wall_x, mine_y])
    if ranks[4] > 0:
        team = int(me["team"])
        # Wards only matter on the far bank (home + river are already
        # lit). Drop range is 3 tiles; plant inland of the waterline.
        if team == 0 and x > river_east:
            action.setdefault("place_ward", [min(x + 3.0, river_east + 16.0), y])
        elif team == 1 and x < river_west:
            action.setdefault("place_ward", [max(x - 3.0, river_west - 16.0), y])


def reset_memory() -> None:
    global _last_tick, _dodge_side, _last_fly, _last_seen
    _tracks.clear()
    _last_tick = -1
    _dodge_side = 0
    _last_fly = None
    _last_seen = None


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
    if PERSONALITY == "partner":
        return _choose_partner(obs)
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
    ally_flies = [
        h for h in hooks
        if h.get("team") == me["team"]
        and h.get("flying", True)
        and h.get("owner_id") != me.get("id")
        and h.get("victim") in (None, 0)
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
    rusher = PERSONALITY == "rusher"
    patient = camper or sniper or rusher
    convert = bool(hooked or drowning)
    hold_x = _clone_hold_x(
        me, _home_edge(me, river_west, river_east, patient), allies
    )
    rune_next = obs.get("rune_next") or {}
    soon = int(rune_next.get("soon") or 0)
    lane = _lane_y(
        me,
        obs,
        seen if seen is not None else (
            {"y": ghost_aim[1]} if ghost_aim is not None else None
        ),
        allies,
        convert,
    )
    if soon > 0 and soon <= 256 and float(rune_next.get("y", -1)) >= 0:
        lane = max(Y_MIN, min(height - 17.0, float(rune_next["y"])))
        if soon <= 16 and float(rune_next.get("x", -1)) >= 0:
            runes.append({
                "x": float(rune_next["x"]),
                "y": float(rune_next["y"]),
            })

    if threat is None:
        _dodge_side = 0

    low_hp = float(me["hp"]) * 100 < float(me.get("max_hp", 840)) * 40
    in_river = bool(me.get("in_river") or int(me.get("layer", 0)) == 2)
    dump_chase = bool(drowning or any(
        int(p.get("layer", -1)) == 2 for p in hooked
    ))

    action: dict[str, Any] = {}
    upgrades = _spend_upgrades(me)
    if upgrades:
        action["buy_upgrade"] = upgrades if len(upgrades) > 1 else upgrades[0]
    shop = _spend_shop(me)
    if shop:
        action["buy_power"] = shop if len(shop) > 1 else shop[0]

    want_rot = (
        prey_rot
        and not in_river
        and not (target and target.get("shield"))
        and float(me["hp"]) * 100 >= float(me.get("max_hp", 840)) * 40
        and not sniper
    )
    if want_rot != bool(me.get("rot")):
        # Set, not toggle: idempotent under the 1-tick apply latency, so
        # a repeated ask cannot flicker Rot off and on.
        action["rot"] = want_rot

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
    def _throw() -> list[float] | None:
        return _pick_hook(
            me, target, aim, seen, ghost_aim, ghost_chance,
            carrying, inbound, saves, hooked, drowning, runes,
            camper, sniper, tick, width, height,
            river_west, river_east, allies, ally_flies,
        )

    thrown = None
    close_swing = (
        close and not sniper and not hooked
        and not (target and target.get("shield"))
    )
    if me.get("hook_ready") and (not in_river or blink is None):
        thrown = _throw()
        if thrown is not None:
            action["hook_to"] = thrown

    if blink is not None:
        action["blink_to"] = blink
        _stamp_convert_ping(action, thrown, hooked, drowning, seen)
        _place_gadgets(me, river_west, river_east, action)
        return action
    if (
        me.get("blink_ready")
        and thrown is not None
        and not in_river
    ):
        action["blink_to"] = _clamp_point([hold_x, float(me["y"])], height)
        _stamp_convert_ping(action, thrown, hooked, drowning, seen)
        _place_gadgets(me, river_west, river_east, action)
        return action

    if foreign_rot and not want_rot:
        action["walk_to"] = [float(me.get("home_x", hold_x)), lane]
        _place_gadgets(me, river_west, river_east, action)
        return action

    if thrown is None and close_swing:
        action["attack_target"] = int(close[0]["id"])
        _place_gadgets(me, river_west, river_east, action)
        return action
    _stamp_convert_ping(action, thrown, hooked, drowning, seen)

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
    elif hooked:
        action["walk_to"] = [hold_x, float(hooked[0]["y"])]
    elif rusher and seen is not None and not me.get("hooked"):
        if int(me["team"]) == 0:
            seen_home = float(seen["x"]) < river_west
        else:
            seen_home = float(seen["x"]) > river_east
        home_fight = (
            seen_home
            and int(seen.get("layer", 0)) == int(me.get("layer", 0))
            and not seen.get("in_river")
            and not in_river
        )
        if home_fight and _dist(me, seen) <= _engage_range(me, patient) + 18:
            action["walk_to"] = [float(seen["x"]), float(seen["y"])]
        else:
            action["walk_to"] = [hold_x, lane]
    elif seen is None and ghost_aim is not None and ghost_chance >= 0.2:
        action["walk_to"] = [hold_x, lane if allies else ghost_aim[1]]
    elif _want_shop(me) and threat is None and not dump_chase:
        action["walk_to"] = [float(me.get("home_x", hold_x)), lane]
    else:
        action["walk_to"] = [hold_x, lane]

    _place_gadgets(me, river_west, river_east, action)
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
            return _clamp_point([hold_x, float(prey["y"])], height)
        if _dist(me, prey) > 10:
            if int(me["team"]) == 0:
                on_home = float(prey["x"]) < river_west
            else:
                on_home = float(prey["x"]) > river_east
            if on_home and not prey.get("in_river"):
                return _clamp_point(
                    [float(prey["x"]), float(prey["y"])], height
                )
            return _clamp_point([hold_x, float(prey["y"])], height)
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
    allies: list[dict[str, Any]],
    ally_flies: list[dict[str, Any]],
) -> list[float] | None:
    if carrying:
        h = carrying[0]
        return [float(h["x"]), float(h["y"])]
    if inbound and _dist(me, inbound[0]) <= 14:
        h = inbound[0]
        return [float(h["x"]), float(h["y"])]
    if hooked:
        prey = hooked[0]
        return _partner_headshot_aim(prey, _reeler(prey, allies, me))
    if ally_flies:
        fly = ally_flies[0]
        pred = {"x": _far_lip(me, river_west, river_east), "y": float(fly["y"])}
        return _partner_headshot_aim(pred, _reeler(pred, allies, me))
    if drowning:
        t = drowning[0]
        return [float(t["x"]), float(t["y"])]
    if saves:
        s = saves[0]
        return [float(s["x"]), float(s["y"])]
    if (
        seen is not None
        and aim is not None
        and not seen.get("shield")
        and not seen.get("ghost")
    ):
        if sniper and float(seen.get("hp", 840)) > _wound_max(me):
            pass
        elif _in_range(
            me, seen, _engage_range(me, camper or sniper or PERSONALITY == "rusher")
        ):
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


def _engage_range(me: dict[str, Any], patient: bool) -> float:
    reach = (44.0 if patient else 34.0) + 4.0 * _upgrade(me, 1) + float(
        _upgrade(me, 3)
    )
    if int(me.get("buff") or 0) == 4:
        reach *= 1.5
    return reach


def _wound_max(me: dict[str, Any]) -> float:
    return float(me.get("max_hp", 840)) * 0.5 + 30.0 * _upgrade(me, 0)


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
    me: dict[str, Any],
    obs: dict[str, Any],
    target: dict[str, Any] | None,
    allies: list[dict[str, Any]] | None = None,
    convert: bool = False,
) -> float:
    height = float(obs.get("height", 128))
    if convert and target is not None:
        return max(Y_MIN, min(height - 17.0, float(target["y"])))
    home_y = float(me.get("home_y", 64))
    living = [a for a in (allies or []) if a.get("alive")]
    if len(living) >= 2:
        if home_y < 52:
            y = 44.0
        elif home_y > 76:
            y = 84.0
        else:
            y = 64.0
        return max(Y_MIN, min(height - 17.0, y))
    if living:
        ally = min(living, key=lambda a: abs(float(a["y"]) - float(me["y"])))
        if abs(float(ally["y"]) - float(me["y"])) <= 4:
            y = float(me["y"]) + (10.0 if home_y >= 64 else -10.0)
            return max(Y_MIN, min(height - 17.0, y))
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


def _clone_hold_x(
    me: dict[str, Any], hold_x: float, allies: list[dict[str, Any]]
) -> float:
    if not allies:
        return hold_x
    home_y = float(me.get("home_y", 64))
    if home_y > 76:
        x_off = 6.0
    elif home_y >= 52:
        x_off = 3.0
    else:
        x_off = 0.0
    if int(me["team"]) == 0:
        return max(8.0, hold_x - x_off)
    return min(119.0, hold_x + x_off)


def _stamp_convert_ping(
    action: dict[str, Any],
    thrown: list[float] | None,
    hooked: list[dict[str, Any]],
    drowning: list[dict[str, Any]],
    seen: dict[str, Any] | None,
) -> None:
    if thrown is None:
        return
    mark = None
    if hooked:
        mark = hooked[0]
    elif drowning:
        mark = drowning[0]
    elif (
        seen is not None
        and not seen.get("ghost")
        and not seen.get("shield")
    ):
        mark = seen
    if mark is not None:
        action["ping"] = [float(mark["x"]), float(mark["y"])]


def _dodge_hop(
    me: dict[str, Any],
    threat: dict[str, Any],
    river_west: float,
    river_east: float,
    height: float,
    inland: float = 16.0,
) -> list[float]:
    global _dodge_side
    if _dodge_side == 0:
        _dodge_side = -1 if float(threat["y"]) > float(me["y"]) else 1
        if float(me["y"]) < 20:
            _dodge_side = 1
        if float(me["y"]) > 108:
            _dodge_side = -1
    if int(me["team"]) == 0:
        hop_x = min(float(me["x"]) - inland, river_west - 1.0)
    else:
        hop_x = max(float(me["x"]) + inland, river_east + 1.0)
    hop_y = float(me["y"]) + _dodge_side * 16.0
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
    lead_div = max(1.0, 9.0 + float(_upgrade(me, 2)))
    ax = float(target["x"]) + vx * span / lead_div
    ay = float(target["y"]) + vy * span / lead_div
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


def _reeler(
    target: dict[str, Any],
    allies: list[dict[str, Any]],
    me: dict[str, Any],
) -> dict[str, Any]:
    if allies:
        return min(allies, key=lambda a: _dist(target, a))
    return {
        "x": float(me.get("home_x", me["x"])),
        "y": float(me.get("home_y", me["y"])),
    }


def _headshot_point(
    target: dict[str, Any], reeler: dict[str, Any], t: float = 0.55
) -> list[float]:
    tx = float(target["x"])
    ty = float(target["y"])
    return [
        tx + (float(reeler["x"]) - tx) * t,
        ty + (float(reeler["y"]) - ty) * t,
    ]


def _in_range(me: dict[str, Any], other: dict[str, Any], reach: float) -> bool:
    return _dist(me, other) <= reach


def _partner_hold_spread(
    line_x: float,
    line_y: float,
    me: dict[str, Any],
    allies: list[dict[str, Any]],
    best: dict[str, Any] | None,
    juke: float,
    team: int,
    head: dict[str, Any] | None,
    fly: dict[str, Any] | None,
    fight: dict[str, Any] | None = None,
    ally_swim: bool = False,
) -> tuple[float, float]:
    """Teammate same-Y split + small inland X stagger.

    When a living ally sits on our hold Y (ady <= 4), take the other
    ±10 split by homeY (north vs south of 64). Two-plus allies on the
    lane use homeY tertiles so 3v3 is not two-on-one. Combat snaps
    (head/fly/fight/swim) already applied; do not override those.
    Hold stays camper-depth; stagger is inland only.
    """
    home_y = float(me.get("home_y", 64))
    if head is None and fly is None and fight is None and not ally_swim:
        if best is not None and abs(float(best["y"]) - float(me["y"])) <= 4:
            line_y = line_y - 10.0 if float(best["y"]) >= 64 else line_y + 10.0
        self_y = float(me["y"])
        lane_n = 0
        for ally in allies:
            ay = float(ally["y"])
            if abs(ay - line_y) <= 4 or abs(ay - self_y) <= 4:
                lane_n += 1
        if lane_n >= 2:
            if home_y < 52:
                line_y = 44.0 + juke
            elif home_y > 76:
                line_y = 84.0 + juke
            else:
                line_y = 64.0 + juke
        elif lane_n == 1:
            line_y = line_y + 10.0 if home_y >= 64 else line_y - 10.0
    if allies:
        if home_y > 76:
            x_off = 6.0
        elif home_y >= 52:
            x_off = 3.0
        else:
            x_off = 0.0
        if team == 0:
            line_x -= x_off
        else:
            line_x += x_off
    return max(8.0, min(119.0, line_x)), max(8.0, min(119.0, line_y))


def _choose_partner(obs: dict[str, Any]) -> dict[str, Any]:
    """JSON port of private partner.bas v66. Headshot/combo first,
    hook-before-melee, no fight-dump ping, river-side far-ping dive only.
    Below half HP: blink and walk out of the river even if
    drown/headshot/far ping would otherwise stay.
    Cross-bank headshot aim snaps into the river.
    Inbound threat: 22-tile circle, or a river-lit
    lane poke (|dy|<=10, |dx|<=45, approaching).
    Rot on close / head / fight / ownCatch.
    Default hold is camper-depth (standoff 16) with no lip
    collapse. Blink/walk home land at line_x, not the lip.
    May still enter the river for drown / water-head / far ping.
    After a throw, blink home to line_x so the windup is inland.
    Do not walk to the victim.
    Intercept an inbound disk within 14 tiles before poke.
    Visible combo searches 40 tiles ahead of an ally fly
    (BASIC comboD2=1600). Blind combo stays half-lead.
    Idle throws use camper engage range and ghost floor 0.22.
    Upgrade order is radius, distance, speed, damage.
    Teammate same-Y split: ally on hold lane → lineY ±10 by homeY.
    """
    global _dodge_side, _last_fly, _last_seen
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
    rune_next = obs.get("rune_next") or {}

    _sync_clock(tick)

    team = int(me["team"])
    self_id = int(me.get("id") or 0)
    in_river = bool(me.get("in_river") or int(me.get("layer", 0)) == 2)
    hook_ready = bool(me.get("hook_ready"))
    blink_ready = bool(me.get("blink_ready"))
    low_hp = float(me.get("hp", 840)) * 2 < float(me.get("max_hp", 840))

    enemies = [
        p for p in pudges
        if p.get("team") != me["team"] and p.get("alive") and not p.get("shield")
    ]
    allies = [
        p for p in pudges
        if p.get("team") == me["team"] and p.get("alive")
        and int(p.get("id") or 0) != self_id
        and int(p.get("kind") or 1) == 1
    ]
    _update_tracks(enemies, tick)
    ghost_aim, ghost_chance = _best_ghost(
        me, tick, river_west, river_east, width, height, ping
    )

    ally = min(allies, key=lambda a: _dist(me, a)) if allies else None
    ally_alive = ally is not None
    ally_swim = bool(
        ally is not None
        and (ally.get("in_river") or int(ally.get("layer", -1)) == 2)
    )

    own_catch = 0
    own_hook = None
    ally_catch = 0
    ally_hook = None
    reel_owner = 0
    fly = None
    threat = None
    threat_d2 = 1e18
    cut = None
    for h in hooks:
        hx = float(h["x"])
        hy = float(h["y"])
        hd2 = (hx - float(me["x"])) ** 2 + (hy - float(me["y"])) ** 2
        victim = int(h.get("victim") or 0)
        owner = int(h.get("owner_id") or 0)
        if int(h.get("team", -1)) != team:
            hdx = abs(hx - float(me["x"]))
            hdy = abs(hy - float(me["y"]))
            inbound = bool(h.get("flying", True)) and hd2 <= 484
            if h.get("flying", True) and hdy <= 10 and hdx <= 45:
                if (team == 0 and hx > float(me["x"])) or (
                    team == 1 and hx < float(me["x"])
                ):
                    inbound = True
            if inbound and hd2 < threat_d2:
                threat_d2 = hd2
                threat = h
            if victim not in (0, self_id):
                cut = h
        elif owner == self_id:
            if victim:
                own_catch = victim
                own_hook = h
        else:
            if h.get("flying", True) and victim == 0:
                fly = h
            if victim:
                ally_catch = victim
                ally_hook = h
                reel_owner = owner

    if fly is not None:
        _last_fly = (float(fly["x"]), float(fly["y"]), tick)
    elif _last_fly is not None and tick - _last_fly[2] <= 16:
        fly = {"x": _last_fly[0], "y": _last_fly[1], "flying": True, "victim": 0}
    else:
        _last_fly = None

    if threat is None:
        _dodge_side = 0
    elif _dodge_side == 0:
        _dodge_side = -1 if float(threat["y"]) > float(me["y"]) else 1
        if float(me["y"]) < 20:
            _dodge_side = 1
        if float(me["y"]) > 108:
            _dodge_side = -1

    head = None
    drown = None
    close = None
    best = None
    save = None
    ping_enemy = False
    prey_rot = False
    foreign_rot = False
    for p in pudges:
        if not p.get("alive"):
            continue
        d = _dist(me, p)
        if p.get("rot") and d <= 8 and int(p.get("id") or 0) != self_id:
            foreign_rot = True
        if p.get("team") == me["team"]:
            if int(p.get("id") or 0) != self_id and (
                p.get("hooked") or p.get("in_river") or int(p.get("layer", -1)) == 2
            ):
                save = p
            continue
        if p.get("shield"):
            continue
        if best is None:
            best = p
        if p.get("hooked") and int(p.get("id") or 0) != own_catch:
            if head is None or d < _dist(me, head):
                head = p
        if p.get("in_river") or int(p.get("layer", -1)) == 2:
            if drown is None:
                drown = p
        if int(p.get("kind") or 1) == 1:
            if d < 6.0 and (close is None or d < _dist(me, close)):
                close = p
            if d <= 8:
                prey_rot = True
        if isinstance(ping, dict) and ping.get("x") is not None:
            age = tick - int(ping.get("tick", tick))
            if 0 <= age < 96:
                if abs(float(p["x"]) - float(ping["x"])) <= 8 and abs(
                    float(p["y"]) - float(ping["y"])
                ) <= 8:
                    ping_enemy = True

    if head is None and ally_catch and ally_hook is not None:
        head = {
            "id": ally_catch,
            "x": float(ally_hook["x"]),
            "y": float(ally_hook["y"]),
            "layer": 0,
            "hooked": True,
        }

    reel = None
    if reel_owner:
        reel = next((a for a in allies if int(a.get("id") or 0) == reel_owner), None)
    if reel is None and head is not None and allies:
        reel = min(allies, key=lambda a: _dist(head, a))
    if reel is None:
        reel = ally if ally is not None else {
            "x": float(me.get("home_x", me["x"])),
            "y": float(me.get("home_y", me["y"])),
        }

    fight = None
    if ally_catch and ally_hook is not None:
        fight = {"id": ally_catch, "x": float(ally_hook["x"]), "y": float(ally_hook["y"])}
    if ally is not None:
        for p in enemies:
            if ally_catch and int(p.get("id") or 0) == ally_catch:
                fight = p
                break
            if not ally_catch:
                ad2 = (float(p["x"]) - float(ally["x"])) ** 2 + (
                    float(p["y"]) - float(ally["y"])
                ) ** 2
                if ad2 <= 144 and (fight is None or ad2 < (
                    (float(fight["x"]) - float(ally["x"])) ** 2
                    + (float(fight["y"]) - float(ally["y"])) ** 2
                )):
                    fight = p

    if best is not None:
        _last_seen = (int(best.get("id") or 0), float(best["x"]), float(best["y"]), tick)
        _update_tracks([best], tick)

    combo = None
    if fly is not None:
        hvx = float(fly["x"]) - float(ally["x"]) if ally is not None else (
            -1.0 if team == 1 else 1.0
        )
        hvy = float(fly["y"]) - float(ally["y"]) if ally is not None else 0.0
        combo_d2 = 1600.0
        for p in enemies:
            fdx = float(p["x"]) - float(fly["x"])
            fdy = float(p["y"]) - float(fly["y"])
            fd2 = fdx * fdx + fdy * fdy
            ahead = fdx * hvx + fdy * hvy > 0
            if ahead and fd2 < combo_d2:
                combo_d2 = fd2
                combo = p

    line_combo = None
    if fly is not None:
        lip_x = river_east + 2.0 if team == 0 else river_west - 2.0
        line_y = float(fly["y"])
        if ally is not None:
            den = float(fly["x"]) - float(ally["x"])
            if abs(den) >= 3:
                span = lip_x - float(ally["x"])
                line_y = float(ally["y"]) + (float(fly["y"]) - float(ally["y"])) * span / den
        line_combo = [lip_x, max(16.0, min(111.0, line_y))]

    edge_x = river_west if team == 0 else river_east
    poke_x = (river_east + 8.0) if team == 0 else (river_west - 8.0)
    # 3× camper:v6 won 30–25 by staying ~16 inland. :v22 collapsed
    # to the lip on convert and died 30 again. Hold 16 always.
    # River entry stays for drown / water-head / river-side far ping.
    standoff = 16.0
    line_x = (edge_x - standoff) if team == 0 else (edge_x + standoff)
    line_x = max(8.0, min(119.0, line_x))

    poke_y = float(me.get("home_y", 64))
    if _last_seen is not None:
        poke_y = _last_seen[2]
        age = tick - _last_seen[3]
        ghost = _tracks.get(_last_seen[0])
        if ghost is not None:
            poke_y = _last_seen[2] + ghost.vy * age / 8.0
        if age > 8:
            poke_x = (river_east + 2.0) if team == 0 else (river_west - 2.0)
    poke_y = max(16.0, min(111.0, poke_y))

    fresh_ping = False
    far_ping = False
    if isinstance(ping, dict) and ping.get("x") is not None:
        age = tick - int(ping.get("tick", tick))
        if 0 <= age < 96:
            fresh_ping = True
            if team == 0 and float(ping["x"]) >= river_east:
                far_ping = True
            if team == 1 and float(ping["x"]) <= river_west:
                far_ping = True

    soon = int(rune_next.get("soon") or 0)
    rune_soonish = 0 < soon <= 256

    jphase = (tick // 6) % 24
    juke = (jphase // 3 - 2) if jphase < 12 else (6 - jphase // 3)
    line_y = float(me.get("home_y", 64)) + juke * 5
    if _last_seen is not None:
        line_y = _last_seen[2] + juke * 4
    if ally is not None:
        home_y = float(me.get("home_y", 64))
        if len(allies) >= 2:
            if home_y < 52:
                line_y = 44.0 + juke
            elif home_y > 76:
                line_y = 84.0 + juke
            else:
                line_y = 64.0 + juke
        else:
            line_y = float(ally["y"]) + (14 if home_y >= 64 else -14) + juke
    if line_combo is not None:
        line_y = line_combo[1] + juke * 2
    if head is not None:
        line_y = float(head["y"])
    if ally_swim and head is None and fly is None:
        line_y = float(ally["y"])
    if fight is not None and not ally_swim and head is None:
        line_y = float(fight["y"]) + juke
    if rune_soonish and fight is None and head is None and not ally_swim and not fresh_ping:
        line_y = float(rune_next.get("y", line_y))
    line_x, line_y = _partner_hold_spread(
        line_x, line_y, me, allies, best, float(juke), team, head, fly,
        fight, ally_swim,
    )

    action: dict[str, Any] = {}
    upgrades = _spend_upgrades(me)
    if upgrades:
        action["buy_upgrade"] = upgrades if len(upgrades) > 1 else upgrades[0]
    shop = _spend_shop(me)
    if shop:
        action["buy_power"] = shop if len(shop) > 1 else shop[0]

    want_rot = (
        prey_rot
        and not in_river
        and (
            close is not None
            or head is not None
            or fight is not None
            or bool(own_catch)
        )
        and float(me["hp"]) * 5 >= float(me.get("max_hp", 840)) * 2
    )
    if want_rot != bool(me.get("rot")):
        # Set, not toggle: idempotent under the 1-tick apply latency.
        action["rot"] = want_rot
    flee_rot = foreign_rot and not want_rot

    flashed = False
    dodge_flash = False
    if blink_ready:
        if in_river:
            may_stay = far_ping or drown is not None or (
                head is not None and int(head.get("layer", 0)) == 2
            )
            if low_hp:
                may_stay = False
            if not may_stay:
                action["blink_to"] = _clamp_point([line_x, float(me["y"])], height)
                flashed = True
        elif head is not None:
            action["blink_to"] = _clamp_point([line_x, float(head["y"])], height)
            flashed = True
        elif fly is not None and line_combo is not None:
            action["blink_to"] = _clamp_point([line_x, line_combo[1]], height)
            flashed = True
        elif threat is not None:
            hop = _dodge_hop(me, threat, river_west, river_east, height)
            action["blink_to"] = hop
            flashed = True
            dodge_flash = True

    did_melee = False
    mood = 0
    if hook_ready:
        if head is not None:
            ht = _partner_headshot_aim(head, reel)
            if team == 0 and float(head["x"]) >= river_east and float(reel["x"]) <= river_west:
                ht = [river_west + 8.0, ht[1]]
            if team == 1 and float(head["x"]) <= river_west and float(reel["x"]) >= river_east:
                ht = [river_east - 8.0, ht[1]]
            action["hook_to"] = ht
            action["ping"] = [float(head["x"]), float(head["y"])]
            mood = 6
        elif combo is not None:
            action["hook_to"] = _partner_lead_half(combo, reel)
            mood = 12
        elif line_combo is not None:
            action["hook_to"] = [
                line_combo[0] + (float(reel["x"]) - line_combo[0]) / 2.0,
                line_combo[1] + (float(reel["y"]) - line_combo[1]) / 2.0,
            ]
            mood = 12
        elif ally_swim and ally is not None:
            action["hook_to"] = [float(ally["x"]), float(ally["y"])]
            mood = 2
        elif close is not None:
            action["hook_to"] = [float(close["x"]), float(close["y"])]
            mood = 1
        elif fight is not None:
            action["hook_to"] = [float(fight["x"]), float(fight["y"])]
            mood = 11
        elif cut is not None:
            action["hook_to"] = [float(cut["x"]), float(cut["y"])]
            mood = 3
        elif threat is not None and threat_d2 <= 196:
            action["hook_to"] = [float(threat["x"]), float(threat["y"])]
            mood = 3
        elif save is not None:
            action["hook_to"] = [float(save["x"]), float(save["y"])]
            mood = 2
        elif dodge_flash:
            if best is not None:
                action["hook_to"] = _lead_point(me, best, width, height)
            else:
                action["hook_to"] = [poke_x, poke_y]
            mood = 9
        elif fresh_ping and ping_enemy and isinstance(ping, dict):
            action["hook_to"] = [float(ping["x"]), float(ping["y"])]
            mood = 4
        elif drown is not None:
            action["hook_to"] = [float(drown["x"]), float(drown["y"])]
            mood = 5
        elif not fresh_ping:
            rune = _nearest_rune(me, runes, 26)
            if rune is not None:
                action["hook_to"] = [float(rune["x"]), float(rune["y"])]
                mood = 17
            elif rune_soonish and soon <= 16:
                rx = float(rune_next.get("x", -1))
                ry = float(rune_next.get("y", -1))
                if abs(rx - float(me["x"])) <= 26 and abs(ry - float(me["y"])) <= 26:
                    action["hook_to"] = [rx, ry]
                    mood = 17
            elif best is not None and _in_range(
                me, best, _engage_range(me, True)
            ):
                action["hook_to"] = _lead_point(me, best, width, height)
                action["ping"] = [float(best["x"]), float(best["y"])]
                mood = 19
            elif ghost_aim is not None and ghost_chance >= 0.22:
                action["hook_to"] = ghost_aim
                mood = 19
            elif tick > 8:
                action["hook_to"] = [poke_x, poke_y]
                mood = 16

    if blink_ready and not flashed and action.get("hook_to") is not None:
        action["blink_to"] = _clamp_point([line_x, float(me["y"])], height)
        flashed = True

    if mood == 0 and not dodge_flash and not flee_rot:
        if close is not None:
            action["attack_target"] = int(close["id"])
            mood = 1
            did_melee = True
        elif fight is not None:
            action["attack_target"] = int(fight["id"])
            mood = 11
            did_melee = True
        elif own_catch:
            action["attack_target"] = own_catch
            mood = 18
            did_melee = True

    if not flashed and not me.get("hooked"):
        want_x = line_x
        want_y = line_y
        may_river = far_ping
        if ally_alive and ally is not None:
            if team == 0 and float(me["x"]) < float(ally["x"]):
                may_river = False
            if team == 1 and float(me["x"]) > float(ally["x"]):
                may_river = False
        if drown is not None:
            may_river = True
        if head is not None and int(head.get("layer", 0)) == 2:
            may_river = True
        if low_hp:
            may_river = False
        if in_river and not may_river:
            want_x = line_x
            want_y = float(me["y"])
        elif flee_rot:
            want_x = float(me.get("home_x", line_x))
            want_y = line_y
        elif threat is not None:
            step = -2.0 if team == 0 else 2.0
            want_x = float(me["x"]) + step
            want_y = float(me["y"]) + _dodge_side * 10
        else:
            if ally_swim and ally is not None:
                want_y = float(ally["y"])
            if fight is not None and not ally_swim:
                want_y = float(fight["y"])
            if fresh_ping and fight is None and not ally_swim and isinstance(ping, dict):
                pdx = float(ping["x"]) - float(me["x"])
                pdy = float(ping["y"]) - float(me["y"])
                if pdx * pdx + pdy * pdy > 64:
                    want_x = float(ping["x"]) if far_ping else line_x
                    want_y = float(ping["y"])
            if head is not None:
                want_x = line_x
                want_y = float(head["y"])
            if fly is not None and head is None and line_combo is not None:
                want_x = line_x
                want_y = line_combo[1]
            if (
                rune_soonish and fight is None and not ally_swim
                and head is None and fly is None and not fresh_ping
            ):
                want_x = line_x
                want_y = float(rune_next.get("y", want_y))
            if _want_shop(me) and threat is None and head is None and fly is None and not ally_swim and fight is None and not fresh_ping and not rune_soonish:
                want_x = float(me.get("home_x", line_x))
                want_y = float(me.get("home_y", line_y))
        if not may_river:
            if team == 0:
                want_x = min(want_x, river_west)
            else:
                want_x = max(want_x, river_east)
        want_y = max(8.0, min(119.0, want_y))
        if not did_melee:
            action["walk_to"] = [want_x, want_y]
        _place_gadgets(me, river_west, river_east, action)

    return action


def _partner_headshot_aim(head: dict[str, Any], reel: dict[str, Any]) -> list[float]:
    pull_x = float(reel["x"]) - float(head["x"])
    pull_y = float(reel["y"]) - float(head["y"])
    sep = max(abs(pull_x), abs(pull_y))
    if sep >= 20:
        t = 2.0 / 3.0
    elif sep >= 8:
        t = 0.5
    else:
        t = 1.0 / 3.0
    return [
        max(8.0, min(119.0, float(head["x"]) + pull_x * t)),
        max(8.0, min(119.0, float(head["y"]) + pull_y * t)),
    ]


def _partner_lead_half(target: dict[str, Any], reel: dict[str, Any]) -> list[float]:
    return [
        float(target["x"]) + (float(reel["x"]) - float(target["x"])) / 2.0,
        float(target["y"]) + (float(reel["y"]) - float(target["y"])) / 2.0,
    ]


if __name__ == "__main__":
    asyncio.run(main())
