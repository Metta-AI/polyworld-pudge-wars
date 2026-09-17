#!/usr/bin/env python3
"""Survey decoded hosted replays for one policy seat: where its hooks go, why
it dies, and how the opponent lands hooks on it.

Inputs: a replay root with `EPISODE_ID/row.json` (a clean_row from
`hosted.py xp summarize`: slot, opponents, score) and
`EPISODE_ID/decoded/latest/{events.jsonl,summary.json}` written by the
headless decoder (`pwheadless --replay replay.pwr --duellog decoded`) built from
the exact game source commit. The decoder must have printed
`replay verified: every tick matched` into `EPISODE_ID/decoder.log`.

    replay_survey.py <replay_root> --out <survey.json>

Definitions (engine logger, see games/pudge-wars/skills/replay-inspection):
`hook_launched.target` is the logger's nearest-enemy heuristic at launch, not
the policy's intent. `hook_missed.closest.dist` is the closest approach of the
head to any enemy. A kill's `layer` is the victim's last sampled `lay`
(0 west bank, 1 east bank, 2 river) within 8 ticks before death.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

BUCKETS = ((0, 15), (15, 30), (30, 45), (45, 60), (60, 1000))


def bucket(dist: float) -> str:
    for lo, hi in BUCKETS:
        if lo <= dist < hi:
            return f"{lo}-{hi}" if hi < 1000 else f"{lo}+"
    return "?"


def survey_episode(folder: Path) -> dict[str, Any] | None:
    row = json.loads((folder / "row.json").read_text())
    log = folder / "decoder.log"
    if log.exists() and "every tick matched" not in log.read_text():
        return None
    latest = folder / "decoded" / "latest"
    if not latest.exists():
        return None
    events = [json.loads(line) for line in (latest / "events.jsonl").open()]
    start = next(e for e in events if e["ev"] == "match_start")
    me = next(p["id"] for p in start["players"] if p["seat"] == row["slot"])
    opp_ids = {p["id"] for p in start["players"] if p["id"] != me}
    last_state: dict[int, dict[str, Any]] = {}
    launches: dict[int, dict[str, Any]] = {}
    throws: Counter[str] = Counter()
    hits: Counter[str] = Counter()
    misses: list[float] = []
    near_misses = 0
    deaths: list[dict[str, Any]] = []
    kills: list[dict[str, Any]] = []
    damage_taken: Counter[str] = Counter()
    damage_dealt: Counter[str] = Counter()
    opp_hits_on_me: list[dict[str, Any]] = []
    my_hits: list[dict[str, Any]] = []
    my_in_range_launches = 0
    hp_at_launch_low = 0
    for e in events:
        ev = e["ev"]
        if ev == "state":
            for p in e["p"]:
                last_state[p["id"]] = {**p, "t": e["t"]}
        elif ev == "hook_launched":
            launches[e["hookId"]] = e
            if e["id"] == me:
                tgt = e.get("target") or {}
                b = bucket(tgt.get("dist", 999))
                throws[b] += 1
                if tgt.get("dist", 999) <= e["rangeTiles"]:
                    my_in_range_launches += 1
                if tgt.get("hp", 9999) and last_state.get(me, {}).get("hp", 9999) < 480:
                    hp_at_launch_low += 1
        elif ev == "hook_landed":
            launch = launches.get(e["hookId"], {})
            if e["id"] == me and e["victim"] in opp_ids:
                tgt = launch.get("target") or {}
                hits[bucket(tgt.get("dist", 999))] += 1
                my_hits.append({"t": e["t"], "dist": e["dist"], "flight": e["flightTicks"], "victim_hp_after": e["victimHpAfter"]})
            elif e["victim"] == me:
                st = last_state.get(me, {})
                opp_hits_on_me.append({"t": e["t"], "dist": e["dist"], "flight": e["flightTicks"], "my_layer": st.get("lay"),
                                       "my_hp_before": st.get("hp"), "my_speed": round((st.get("vx", 0) ** 2 + st.get("vy", 0) ** 2) ** 0.5, 1),
                                       "my_x": st.get("x"), "my_y": st.get("y"), "my_cd": st.get("cd")})
        elif ev == "hook_missed" and e["id"] == me:
            c = e.get("closest") or {}
            if c.get("id") in opp_ids:
                misses.append(c["dist"])
                if c["dist"] <= 6:
                    near_misses += 1
        elif ev == "damage":
            if e["victim"] == me:
                damage_taken[e["cause"]] += e["amount"]
            elif e.get("by") == me:
                damage_dealt[e["cause"]] += e["amount"]
        elif ev == "kill":
            st = last_state.get(e["victim"], {})
            rec = {"t": e["t"], "cause": e["cause"], "at": e["at"], "layer": st.get("lay"), "killer_hp": e.get("killerHp"),
                   "victim_last_hp": st.get("hp")}
            if e["victim"] == me:
                deaths.append(rec)
            elif e["killer"] == me:
                kills.append(rec)
    summary = json.loads((latest / "summary.json").read_text())
    mine = next(p for p in summary["players"] if p["id"] == me)
    theirs = [p for p in summary["players"] if p["id"] != me]
    return {
        "episode_id": row["episode_id"], "team": row["team"], "score": row["score"], "opponents": row["opponents"],
        "outcome": summary["reason"], "ticks": summary["ticks"],
        "my_kills": mine["kills"], "my_deaths": mine["deaths"], "my_thrown": mine["hooksThrown"], "my_landed": mine["hooksLanded"],
        "my_denies": mine["denies"], "my_runes": mine["runes"], "my_river_sec": mine["timeInRiverSec"],
        "opp_thrown": sum(p["hooksThrown"] for p in theirs), "opp_landed": sum(p["hooksLanded"] for p in theirs),
        "opp_denies": sum(p["denies"] for p in theirs), "opp_runes": sum(p["runes"] for p in theirs),
        "opp_river_sec": sum(p["timeInRiverSec"] for p in theirs),
        "my_dodge": mine["dodge"], "opp_dodge": [p["dodge"] for p in theirs],
        "my_hit_by_dist": mine["hitRateByDist"], "opp_hit_by_dist": [p["hitRateByDist"] for p in theirs],
        "throws_by_target_dist": dict(throws), "hits_by_target_dist": dict(hits),
        "in_range_launches": my_in_range_launches, "near_misses_le6": near_misses,
        "miss_closest": sorted(misses),
        "damage_taken": dict(damage_taken), "damage_dealt": dict(damage_dealt),
        "deaths": deaths, "kills": kills, "opp_hits_on_me": opp_hits_on_me, "my_hits": my_hits,
    }


def aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    n = len(rows)
    if not n:
        return {"n": 0}
    death_cause: Counter[str] = Counter()
    death_layer: Counter[str] = Counter()
    kill_cause: Counter[str] = Counter()
    kill_layer: Counter[str] = Counter()
    hit_layer: Counter[str] = Counter()
    hit_moving = 0
    hit_total = 0
    hit_dist = []
    throws: Counter[str] = Counter()
    hits: Counter[str] = Counter()
    dmg_t: Counter[str] = Counter()
    dmg_d: Counter[str] = Counter()
    misses: list[float] = []
    for r in rows:
        for d in r["deaths"]:
            death_cause[d["cause"]] += 1
            death_layer[str(d["layer"])] += 1
        for k in r["kills"]:
            kill_cause[k["cause"]] += 1
            kill_layer[str(k["layer"])] += 1
        for h in r["opp_hits_on_me"]:
            hit_layer[str(h["my_layer"])] += 1
            hit_total += 1
            hit_moving += h["my_speed"] > 2
            hit_dist.append(h["dist"])
        throws.update(r["throws_by_target_dist"])
        hits.update(r["hits_by_target_dist"])
        dmg_t.update(r["damage_taken"])
        dmg_d.update(r["damage_dealt"])
        misses.extend(r["miss_closest"])
    misses.sort()

    def q(xs: list[float], f: float) -> float | None:
        return xs[min(len(xs) - 1, int(f * len(xs)))] if xs else None

    return {
        "n": n, "win_rate": sum(r["score"] for r in rows) / n,
        "kills": sum(r["my_kills"] for r in rows) / n, "deaths": sum(r["my_deaths"] for r in rows) / n,
        "my_acc": sum(r["my_landed"] for r in rows) / max(1, sum(r["my_thrown"] for r in rows)),
        "opp_acc": sum(r["opp_landed"] for r in rows) / max(1, sum(r["opp_thrown"] for r in rows)),
        "my_denies": sum(r["my_denies"] for r in rows) / n, "opp_denies": sum(r["opp_denies"] for r in rows) / n,
        "my_runes": sum(r["my_runes"] for r in rows) / n, "opp_runes": sum(r["opp_runes"] for r in rows) / n,
        "my_river_sec": sum(r["my_river_sec"] for r in rows) / n, "opp_river_sec": sum(r["opp_river_sec"] for r in rows) / n,
        "hooks_aimed_at_me": sum(r["my_dodge"]["hooksAimedAtMe"] for r in rows) / n,
        "my_dodge_rate": 1 - sum(r["my_dodge"]["hit"] for r in rows) / max(1, sum(r["my_dodge"]["hooksAimedAtMe"] for r in rows)),
        "opp_dodge_rate": 1 - sum(d["hit"] for r in rows for d in r["opp_dodge"]) / max(1, sum(d["hooksAimedAtMe"] for r in rows for d in r["opp_dodge"])),
        "my_move_during_flight": sum(r["my_dodge"]["avgMoveDuringFlight"] for r in rows) / n,
        "opp_move_during_flight": sum(d["avgMoveDuringFlight"] for r in rows for d in r["opp_dodge"]) / n,
        "throws_by_target_dist": {k: throws[k] / n for k in sorted(throws)},
        "acc_by_target_dist": {k: hits[k] / throws[k] for k in sorted(throws) if throws[k]},
        "in_range_launches": sum(r["in_range_launches"] for r in rows) / n,
        "near_misses_le6": sum(r["near_misses_le6"] for r in rows) / n,
        "miss_closest_q25_50_75": [q(misses, 0.25), q(misses, 0.5), q(misses, 0.75)],
        "damage_taken_per_game": {k: v / n for k, v in dmg_t.items()},
        "damage_dealt_per_game": {k: v / n for k, v in dmg_d.items()},
        "death_cause": dict(death_cause), "death_layer": dict(death_layer),
        "kill_cause": dict(kill_cause), "kill_layer": dict(kill_layer),
        "hit_on_me_layer": dict(hit_layer), "hit_on_me_while_moving": hit_moving / max(1, hit_total),
        "hit_on_me_dist_q25_50_75": [q(sorted(hit_dist), f) for f in (0.25, 0.5, 0.75)],
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    rows = [r for r in (survey_episode(f) for f in sorted(args.root.iterdir()) if (f / "row.json").exists()) if r]
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for r in rows:
        groups["overall"].append(r)
        groups[f"team={r['team']}"].append(r)
        groups[f"vs={','.join(r['opponents'])}"].append(r)
        groups["win" if r["score"] == 1.0 else "loss"].append(r)
    out = {"groups": {k: aggregate(v) for k, v in groups.items()}, "episodes": rows}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out, indent=2, sort_keys=True, default=str) + "\n")
    for k, g in out["groups"].items():
        print(f"== {k}: " + json.dumps({kk: vv for kk, vv in g.items() if kk not in ("episodes",)}, default=str))


if __name__ == "__main__":
    main()
