"""Base's validated economy, vision, aiming and defensive posture over JSON.

The live Coworld applies replies one tick later. Purchases precede movement
and casting, while halt discards the rest of a reply. Keep those differences
from the synchronous BASIC API explicit here.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from collections import deque
from typing import Any


def distance(a: dict, b: dict) -> float:
    return math.hypot(a["x"] - b["x"], a["y"] - b["y"])


def point(x: float, y: float) -> list[float]:
    return [max(8.0, min(119.0, x)), max(8.0, min(119.0, y))]


def segment_distance(start: list[float], end: list[float], at: list[float]) -> float:
    dx, dy = end[0] - start[0], end[1] - start[1]
    length2 = dx * dx + dy * dy
    fraction = max(0.0, min(1.0, ((at[0] - start[0]) * dx + (at[1] - start[1]) * dy) / length2)) if length2 else 0.0
    return math.hypot(at[0] - start[0] - fraction * dx, at[1] - start[1] - fraction * dy)


@dataclass
class BasePolicy:
    heal_allies: bool = False
    spread_fishing: bool = False
    trace: bool = False
    recovering: bool = False
    tick: int = -1
    samples: dict[int, tuple[int, float, float, float, float]] = field(default_factory=dict)
    last_enemy: dict | None = None
    last_seen: int = -1
    dodge_side: int = 0
    rescue_until: int = 0
    team_roster: set[int] = field(default_factory=set)
    hook_track: dict[int, tuple[int, float, float, str]] = field(default_factory=dict)
    threat_info: dict[str, Any] = field(default_factory=dict)
    events: deque = field(default_factory=lambda: deque(maxlen=256))

    def reset(self) -> None:
        self.recovering = False
        self.tick = -1
        self.samples.clear()
        self.last_enemy = None
        self.last_seen = -1
        self.dodge_side = 0
        self.rescue_until = 0
        self.team_roster.clear()
        self.hook_track.clear()
        self.threat_info.clear()
        self.events.clear()

    def record(self, event: str, **values: Any) -> None:
        if self.trace:
            self.events.append(dict(event=event, tick=self.tick, **values))

    def collision_threat(self, me: dict, hooks: list[dict], team: int) -> dict | None:
        """Nearest enemy hook in flight whose straight path can actually reach us.

        Heading comes from the head's displacement since the previous tick;
        the owner's position is not used because the owner may Blink after
        the throw while the head keeps its heading. An untracked head is a
        threat when close (blind) and otherwise waits one tick for a track
        (pending). Hooks moving away or passing wide are ignored.
        """
        tick = self.tick
        seen: dict[int, tuple[int, float, float, str]] = {}
        threats = []
        for hook in hooks:
            if hook["team"] == team or not hook["flying"]:
                continue
            owner_id = hook["owner_id"]
            old = self.hook_track.get(owner_id)
            dx = dy = 0.0
            source = "none"
            if old is not None and 0 < tick - old[0] <= 4:
                dx, dy = hook["x"] - old[1], hook["y"] - old[2]
                if math.hypot(dx, dy) >= 0.05:
                    source = "track"
            dist = distance(me, hook)
            cls = old[3] if old is not None else ""
            if dist <= 22:
                along = perp = None
                if source == "none":
                    cls = "blind" if dist <= 10 else "pending"
                else:
                    length = math.hypot(dx, dy)
                    ux, uy = dx / length, dy / length
                    rx, ry = me["x"] - hook["x"], me["y"] - hook["y"]
                    along = rx * ux + ry * uy
                    perp = abs(rx * uy - ry * ux)
                    cls = "away" if along < 0 else "wide" if perp > 8 else "hit"
                if cls in {"hit", "blind"}:
                    threats.append((dist, hook, cls, along, perp))
                if old is None or old[3] != cls:
                    self.record("threat_class", owner=owner_id, cls=cls, src=source, dist=round(dist, 1),
                                along=None if along is None else round(along, 1),
                                perp=None if perp is None else round(perp, 1))
            seen[owner_id] = (tick, hook["x"], hook["y"], cls)
        self.hook_track = seen
        if not threats:
            return None
        dist, hook, cls, along, perp = min(threats, key=lambda t: t[0])
        self.threat_info = {"owner": hook["owner_id"], "cls": cls,
                            "along": None if along is None else round(along, 1),
                            "perp": None if perp is None else round(perp, 1)}
        return hook

    @staticmethod
    def healing_pair(players: list[dict], enemies: list[dict], hooks: list[dict], team: int) -> tuple[dict, dict] | None:
        """Claim one short heal for the whole team, away from active combat."""
        def safe(unit: dict) -> bool:
            return (unit["alive"] and unit["layer"] == team and not unit["hooked"]
                    and not unit["shield"] and not unit["rot"]
                    and all(distance(unit, enemy) > 28 for enemy in enemies)
                    and all(h["team"] == team or distance(unit, h) > 28 for h in hooks)
                    and not any(h["victim"] == unit["id"] for h in hooks))
        safe_players = [p for p in players if safe(p)]
        pairs = []
        for recipient in safe_players:
            if recipient["max_hp"] - recipient["hp"] < 120:
                continue
            for healer in safe_players:
                gap = distance(healer, recipient)
                if (healer["id"] == recipient["id"] or not healer["hook_ready"]
                        or any(h["owner_id"] == healer["id"] for h in hooks)
                        or healer["hp"] < healer["max_hp"] * 0.6 or not 4 <= gap <= 24):
                    continue
                # Do not drag a recovering ally appreciably toward the river.
                forward = healer["x"] - recipient["x"] if team == 0 else recipient["x"] - healer["x"]
                if forward <= 4:
                    pairs.append((healer, recipient))
        return min(pairs, key=lambda pair: (pair[1]["hp"] / pair[1]["max_hp"], distance(*pair), pair[0]["id"], pair[1]["id"]), default=None)

    def fishing_lanes(self, players: list[dict], upcoming: dict, team: int) -> tuple[dict[int, float], int | None]:
        """Stable lanes retain their rank through deaths; one player tracks a drop."""
        ids = sorted(self.team_roster)
        lanes = {pid: 32.0 + 64.0 * rank / (len(ids) - 1) for rank, pid in enumerate(ids)}
        collector = None
        if 0 < upcoming["soon"] <= 256:
            eligible = [p for p in players if p["alive"] and p["layer"] == team
                        and not p["hooked"] and not p["rot"] and p["hp"] >= p["max_hp"] * 0.4]
            chosen = min(eligible, key=lambda p: (distance(p, upcoming), p["id"]), default=None)
            if chosen is not None:
                collector = chosen["id"]
                lanes[collector] = max(16.0, min(111.0, upcoming["y"]))
                reserved = [lanes[collector]]
                for pid in ids:
                    if pid == collector:
                        continue
                    choices = [float(y) for y in range(16, 112, 4) if all(abs(y - other) >= 24 for other in reserved)]
                    lanes[pid] = min(choices, key=lambda y: (abs(y - lanes[pid]), y))
                    reserved.append(lanes[pid])
        return lanes, collector

    def velocity(self, unit: dict) -> tuple[float, float]:
        sample = self.samples.get(unit["id"])
        return (sample[3], sample[4]) if sample else (0.0, 0.0)

    @staticmethod
    def fountain_escape(obs: dict, enemies: list[dict], retreat: bool) -> list[float] | None:
        """Return to our bank without clipping the hop into water or a body."""
        me = obs["self"]
        # Older hosts explicitly forbid crossing banks, even within range.
        if (obs.get("game_version", 0) < 35 or me["layer"] in (me["team"], 2)
                or me["hooked"] or me["rot"] or not 56 <= me["y"] <= 72):
            return None
        if not retreat and any(distance(me, enemy) <= 12 for enemy in enemies):
            return None
        row = int(me["y"])
        dy = row - 64
        half = 11 - 6 * (256 - dy * dy) // 256
        landing = [float(64 - half - 2 if me["team"] == 0 else 64 + half + 2), float(row)]
        start = [me["x"], me["y"]]
        if math.dist(start, landing) > 20:
            return None
        units = [p for p in obs["visible"]["pudges"] if p["alive"] and p["id"] != me["id"]]
        if any(p["rot"] and math.dist([p["x"], p["y"]], landing) <= 12 for p in units):
            return None
        obstacles = [p for p in units if p["layer"] != me["layer"]]
        obstacles += [p for p in obs["visible"].get("props", []) if p["kind"] == "wall"]
        if any(segment_distance(start, landing, [p["x"], p["y"]]) <= 4 for p in obstacles):
            return None
        return landing

    def choose_action(self, obs: dict[str, Any]) -> dict[str, Any]:
        tick = obs["tick"]
        if tick < self.tick:
            self.reset()
        self.tick = tick
        me = obs["self"]
        if not me["alive"]:
            self.recovering = False
            self.rescue_until = 0
            return {}
        team = me["team"]
        if self.spread_fishing:
            self.team_roster.update(p["id"] for p in obs["visible"]["pudges"] if p["team"] == team)
        own_land = me["layer"] == team
        river = me["layer"] == 2
        low = me["hp"] * 100 < me["max_hp"] * 40
        # A full recovery costs less than repeatedly returning to the front
        # with barely 40% HP. Percentage healing scales with kill-earned HP.
        if me["hp"] >= me["max_hp"] * 0.75:
            if self.recovering:
                self.record("recovered", hp=me["hp"])
            self.recovering = False
        elif low and not self.recovering:
            self.recovering = True
            self.record("recovery_start", hp=me["hp"])
        if sum(p["team"] == team for p in obs["visible"]["pudges"]) > 1:
            low = self.recovering
        units = [p for p in obs["visible"]["pudges"] if p["alive"]]
        allies = [p for p in units if p["team"] == team and p["id"] != me["id"]]
        enemies = sorted((p for p in units if p["team"] != team and not p["shield"]), key=lambda p: distance(me, p))
        hooks = obs["visible"]["hooks"]
        for unit in units:
            old = self.samples.get(unit["id"])
            if old is None:
                self.samples[unit["id"]] = (tick, unit["x"], unit["y"], 0.0, 0.0)
            elif tick - old[0] >= 8:
                scale = 8.0 / (tick - old[0])
                self.samples[unit["id"]] = (tick, unit["x"], unit["y"],
                    (unit["x"] - old[1]) * scale, (unit["y"] - old[2]) * scale)
        target = enemies[0] if enemies else None
        if target is not None:
            self.last_enemy = target.copy()
            self.last_seen = tick
        west, east = obs["play_west_max"], obs["play_east_min"]
        hold_x = west - 16 if team == 0 else east + 16
        home = [me["home_x"], me["home_y"]]
        rank = sum(p["id"] < me["id"] for p in allies)
        threat = self.collision_threat(me, hooks, team)
        if threat is None:
            self.dodge_side = 0
        elif self.dodge_side == 0:
            self.dodge_side = -1 if threat["y"] > me["y"] else 1
            if me["y"] < 20:
                self.dodge_side = 1
            elif me["y"] > 108:
                self.dodge_side = -1
        caught = next((p for p in enemies if p["hooked"]), None)
        swimming = next((p for p in enemies if p["layer"] == 2), None)
        brawl = target is not None and (me["hp"] + 40 >= target["hp"] or target["hp"] <= 120 or (not own_land and not river))
        rot = bool(target and any(distance(me, p) <= 8 for p in enemies)
                   and brawl and not river and not low and me["hp"] > 96)
        foreign_rot = any(p["rot"] and distance(me, p) <= 8 for p in units if p["id"] != me["id"])
        flee_rot = foreign_rot and not rot

        action: dict[str, Any] = {}
        levels = list(me["upgrades"])
        purchases = []
        for _ in range(me["points"]):
            kind = next((k for k in (1, 2, 0, 3) if levels[k] < 10), None)
            if kind is None:
                break
            levels[kind] += 1
            purchases.append(kind)
        if purchases:
            action["buy_upgrade"] = purchases
        ranks = list(me["item_ranks"])
        gold = me["gold"]
        buff = me["buff"]
        # Free charges and 32-tile placement arrived with ward_restock.
        # Released 0.3.13 has paid, permanent wards with 3-tile placement.
        modern_wards = "ward_restock" in me
        if me["in_shop"]:
            buys = []
            if modern_wards and ranks[4] == 0 and me["ward_restock"] == 0:
                buys.append(9)
                ranks[4] = 1
            if me["hp"] * 2 < me["max_hp"] and gold >= 5:
                buys.append(0)
                gold -= 5
            while True:
                count = len(buys)
                for item, rank_index, price in [(6, 1, 12), (5, 0, 10)]:
                    if ranks[rank_index] < 5 and gold >= price:
                        buys.append(item)
                        ranks[rank_index] += 1
                        gold -= price
                if len(buys) == count:
                    break
            if ranks[1] and buff == 0 and gold >= 6:
                buys.append(3)
                buff = 4
            if buys:
                action["buy_power"] = buys
        if rot != me["rot"]:
            action["rot"] = rot
        reach = 60.0 + 4.0 * levels[1]
        radius = 2.75 + 0.125 * levels[3]
        if buff == 4:
            reach *= 1.5
            radius *= 1.5

        def throw(aim: list[float], rescue_id: int = 0) -> bool:
            if not me["hook_ready"] or me["hooked"] or "hook_to" in action:
                return False
            start = action.get("blink_to", [me["x"], me["y"]])
            length = math.dist(start, aim)
            if length < 0.01:
                return False
            end = [start[i] + (aim[i] - start[i]) * min(1.0, reach / length) for i in range(2)]
            for ally in allies:
                if ally["id"] == rescue_id or ally["shield"] > 9:
                    continue
                vx, vy = self.velocity(ally)
                for at in [[ally["x"], ally["y"]], [ally["x"] + vx / 2, ally["y"] + vy / 2]]:
                    if segment_distance(start, end, at) <= radius + 3.1:
                        return False
            action["hook_to"] = point(*aim)
            return True

        # A friendly chain already returning a victim owns that rescue.
        carried = {h["victim"]: h for h in hooks if h["victim"]}
        ping = obs["ally_ping"]
        fresh_ping = ping is not None and 0 <= ping["age"] < 96
        rescue = []
        for ally in allies:
            chain = carried.get(ally["id"])
            if chain is not None:
                needs_help = chain["team"] != team
            else:
                requested = fresh_ping and ping["by"] == ally["id"] and distance(ping, ally) <= 4
                needs_help = ally["layer"] == 2 and (ally["hp"] * 100 <= ally["max_hp"] * 60 or requested)
            if needs_help and not ally["shield"] and distance(me, ally) <= reach:
                rescue.append(ally)
        rescue.sort(key=lambda p: distance(me, p))
        free = own_land and not me["hooked"] and not low and threat is None and not flee_rot
        own_rescue = any(h["owner_id"] == me["id"] and any(p["id"] == h["victim"] for p in allies) for h in hooks)
        if free and (own_rescue or tick < self.rescue_until):
            # halt is an exclusive wire action; do not drop shop purchases.
            action["walk_to"] = [me["x"], me["y"]]
            return action
        if free and not foreign_rot and rescue:
            victim = rescue[0]
            rescuers = [p for p in [me, *allies] if p["id"] != victim["id"] and p["hook_ready"]
                        and not p["hooked"] and p["layer"] == team and p["hp"] * 100 >= p["max_hp"] * 40]
            owner = min(rescuers, key=lambda p: (distance(p, victim), p["id"]), default=None)
            if owner is not None and owner["id"] == me["id"] and throw([victim["x"], victim["y"]], victim["id"]):
                self.rescue_until = tick + 10
                action["walk_to"] = [me["x"], me["y"]]
                return action

        if me["blink_ready"]:
            crossing = self.fountain_escape(obs, enemies, low)
            if crossing is not None:
                action["blink_to"] = crossing
                self.record("fountain_escape", destination=crossing)
            elif river:
                action["blink_to"] = point(west if team == 0 else east, me["y"])
            elif threat is not None:
                # Keep the requested hop inside Blink's actual 20-tile disk.
                x, y = point(me["x"] + (-16 if me["layer"] == 0 else 16), me["y"] + 16 * self.dodge_side)
                scale = min(1.0, 20.0 / math.hypot(x - me["x"], y - me["y"]))
                action["blink_to"] = [me["x"] + (x - me["x"]) * scale, me["y"] + (y - me["y"]) * scale]
                self.record("dodge_blink", **self.threat_info)
        if me["hooked"]:
            return action

        if target is not None and distance(me, target) <= 20 and not river:
            throw([target["x"], target["y"]])
        if caught is not None:
            reeler = carried.get(caught["id"])
            owner = next((p for p in units if reeler is not None and p["id"] == reeler["owner_id"]), caught)
            throw([(caught["x"] + owner["x"]) / 2, (caught["y"] + owner["y"]) / 2])
        if threat is not None and distance(me, threat) <= 14:
            throw([threat["x"], threat["y"]])
        if swimming is not None:
            throw([swimming["x"], swimming["y"]])
        if self.heal_allies and free and not foreign_rot and caught is None and swimming is None and "hook_to" not in action:
            # Urgent combat/rescue has already had its chance. Healing can
            # replace a speculative long shot, never an emergency response.
            pair = self.healing_pair([me, *allies], [p for p in units if p["team"] != team], hooks, team)
            if pair is not None and pair[0]["id"] == me["id"]:
                recipient = pair[1]
                if throw([recipient["x"], recipient["y"]], recipient["id"]):
                    self.rescue_until = tick + 10
                    action["walk_to"] = [me["x"], me["y"]]
                    self.record("heal_request", healer=me["id"], recipient=recipient["id"], hp=recipient["hp"], max_hp=recipient["max_hp"], at=[recipient["x"], recipient["y"]])
                    return action
        if target is not None and distance(me, target) <= reach + radius:
            vx, vy = self.velocity(target)
            span = max(abs(me["x"] - target["x"]), abs(me["y"] - target["y"]))
            aim = point(target["x"] + vx * span / (30 + levels[2]), target["y"] + vy * span / (30 + levels[2]))
            if segment_distance([me["x"], me["y"]], aim, [64, 64]) > 5:
                throw(aim)
        if not river:
            for rune in obs["visible"]["runes"]:
                if abs(me["x"] - rune["x"]) <= 36 and abs(me["y"] - rune["y"]) <= 36:
                    if throw([rune["x"], rune["y"]]):
                        break
        if target is None and not river and tick > 8:
            poke_x = east + 8 if team == 0 else west - 8
            poke_y = me["y"]
            if self.last_enemy is not None:
                age = tick - self.last_seen
                vx, vy = self.velocity(self.last_enemy)
                poke_y = self.last_enemy["y"] + vy * age / 8
                if age <= 96:
                    poke_x = self.last_enemy["x"] + vx * age / 8
                else:
                    poke_x = east + 2 if team == 0 else west - 2
            poke_x = max(east + 1, min(113, poke_x)) if team == 0 else min(west - 1, max(14, poke_x))
            throw(point(poke_x, max(16, min(111, poke_y))))

        if target is not None and distance(me, target) <= 5.5 and brawl and not flee_rot:
            action["attack_target"] = target["id"]
        if "blink_to" in action:
            return action
        busy = True
        if flee_rot:
            action["walk_to"] = point(home[0], me["y"] + (((tick // 12) % 2) * 2 - 1) * 8)
        elif threat is not None:
            action["walk_to"] = point(me["x"] + (-2 if team == 0 else 2), me["y"] + self.dodge_side * 10)
        elif river:
            action["walk_to"] = [hold_x, me["y"]]
        elif "attack_target" in action:
            pass
        elif caught is not None and not low:
            finish_x = min(caught["x"], hold_x) if team == 0 else max(caught["x"], hold_x)
            action["walk_to"] = point(finish_x, caught["y"])
        elif low or (target is not None and distance(me, target) <= 12 and not brawl):
            action["walk_to"] = home
        else:
            busy = False
            if fresh_ping and ping["by"] != me["id"]:
                responders = [p for p in [me, *allies] if p["id"] != ping["by"] and not p["hooked"]
                              and p["layer"] == team and p["hp"] * 100 >= p["max_hp"] * 40]
                responder = min(responders, key=lambda p: (distance(p, ping), p["id"]), default=None)
                if responder is not None and responder["id"] == me["id"]:
                    x = min(ping["x"], hold_x) if team == 0 else max(ping["x"], hold_x)
                    action["walk_to"] = point(x, ping["y"])
                    busy = True
            if not busy:
                if not me["in_shop"] and gold >= 12 and (ranks[0] < 5 or ranks[1] < 5):
                    action["walk_to"] = [22 if team == 0 else 106, 64]
                    busy = True
                else:
                    phase = (tick // 6 + me["id"] * 7) % 24
                    juke = phase // 3 - 2 if phase < 12 else 6 - phase // 3
                    y = 40 + rank * 24 + juke if allies else (target["y"] if target else me["y"]) + juke * 1.5
                    upcoming = obs["rune_next"]
                    if self.spread_fishing and len(self.team_roster) > 1:
                        lanes, collector = self.fishing_lanes([me, *allies], upcoming, team)
                        y = lanes[me["id"]] + (0 if me["id"] == collector else juke)
                        if tick % 64 == 0:
                            self.record("fishing_formation", player=me["id"], y=y, collector=collector, lanes=lanes)
                    elif 0 < upcoming["soon"] <= 256:
                        y = upcoming["y"]
                    action["walk_to"] = point(hold_x, y)

        # A purchase request may be refused by the live restock timer.
        # Start the ward trip only once a later observation confirms it.
        if modern_wards and me["item_ranks"][4] > 0 and own_land:
            ward_x = east + 3 if team == 0 else west - 3
            ward_y = 50 if 54 < me["y"] < 74 else me["y"]
            if math.hypot(ward_x - me["x"], ward_y - me["y"]) <= 32:
                action["place_ward"] = [ward_x, ward_y]
            elif not busy:
                action["walk_to"] = [west - 5 if team == 0 else east + 5, ward_y]
        return action
