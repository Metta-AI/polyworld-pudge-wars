"""Pull-exchange survey over decoded hosted replays: what happens in the 6 s
after one of our long hooks (> 30 tiles) lands and reels the enemy onto us.

Same replay root layout as replay_survey.py (`EPISODE_ID/row.json` plus
`EPISODE_ID/decoded/latest/events.jsonl`). Each landing is bucketed by the HP
edge we hold once the hook damage is in (`me.hp + MARGIN >= victim.hp`, the
policy's `brawl` test) and by victim HP after the hook; per seat and per
opponent. Reads victim HP from `hook_landed.victimHpAfter` and our HP from the
latest `state` row at or before the landing.

    pull_exchange.py <replay_root> --out <json> [--window 192] [--margin 40]
"""
from __future__ import annotations

import argparse
import bisect
import collections
import json
import statistics
from pathlib import Path


def hp_bucket(hp: float) -> str:
    if hp <= 400:
        return "hp<=400"
    if hp <= 800:
        return "hp<=800"
    return "hp>800"


def survey(root: Path, window: int, margin: float) -> dict:
    groups: dict[str, dict[str, list]] = collections.defaultdict(lambda: collections.defaultdict(list))
    episodes = 0
    for row_path in sorted(root.glob("*/row.json")):
        events_path = row_path.parent / "decoded" / "latest" / "events.jsonl"
        if not events_path.exists():
            continue
        row = json.loads(row_path.read_text())
        team = row["team"]
        opponent = row["opponents"][0] if row.get("opponents") else "?"
        events = [json.loads(line) for line in events_path.open()]
        players = {p["id"]: p for p in events[0]["players"]}
        me = next(pid for pid, p in players.items() if p["team"] == team)
        opp = next(pid for pid, p in players.items() if p["team"] != team)
        states = [e for e in events if e["ev"] == "state"]
        state_ticks = [s["t"] for s in states]
        kills = [e for e in events if e["ev"] == "kill"]
        landed = [e for e in events if e["ev"] == "hook_landed"]
        episodes += 1
        for hit in landed:
            if hit["id"] != me or hit["victim"] != opp or hit["dist"] <= 30:
                continue
            index = bisect.bisect_right(state_ticks, hit["t"]) - 1
            if index < 0:
                continue
            my_hp = next(p["hp"] for p in states[index]["p"] if p["id"] == me)
            victim_hp = hit["victimHpAfter"]
            edge = my_hp + margin >= victim_hp or victim_hp <= 120
            after = [k for k in kills if hit["t"] <= k["t"] <= hit["t"] + window]
            victim_dies = any(k["victim"] == opp for k in after)
            me_dies = any(k["victim"] == me for k in after)
            my_death = next((k for k in after if k["victim"] == me), None)
            their_hooks = sum(1 for e in landed if e["id"] == opp and e["victim"] == me and hit["t"] < e["t"] <= hit["t"] + window)
            keys = [
                f"all/{team}", "all/both",
                f"{'edge' if edge else 'no_edge'}/{team}", f"{'edge' if edge else 'no_edge'}/both",
                f"{hp_bucket(victim_hp)}/{team}", f"{hp_bucket(victim_hp)}/both",
                f"opp:{opponent}/{team}",
            ]
            for key in keys:
                g = groups[key]
                g["victim_dies"].append(victim_dies)
                g["me_dies"].append(me_dies)
                g["their_hooks_on_me"].append(their_hooks)
                g["my_hp"].append(my_hp)
                g["victim_hp_after"].append(victim_hp)
                if my_death is not None:
                    g["my_death_cause:" + my_death["cause"]].append(1)
    out = {}
    for key in sorted(groups):
        g = groups[key]
        n = len(g["victim_dies"])
        rec = {"pulls": n, "pulls_per_game": round(n / max(episodes, 1), 2)}
        for field in ("victim_dies", "me_dies", "their_hooks_on_me", "my_hp", "victim_hp_after"):
            rec[field] = round(statistics.mean(g[field]), 3)
        for field in sorted(g):
            if field.startswith("my_death_cause:"):
                rec[field] = round(len(g[field]) / n, 3)
        out[key] = rec
    return {"episodes": episodes, "window_ticks": window, "margin": margin, "groups": out}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("root", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--window", type=int, default=192)
    parser.add_argument("--margin", type=float, default=40.0)
    args = parser.parse_args()
    result = survey(args.root, args.window, args.margin)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    for key, rec in result["groups"].items():
        if key.startswith(("all/", "edge/", "no_edge/")):
            print(f"{key:14s} n={rec['pulls']:4d} victim_dies={rec['victim_dies']:.2f} me_dies={rec['me_dies']:.2f}")


if __name__ == "__main__":
    main()
