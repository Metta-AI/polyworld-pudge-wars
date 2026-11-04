#!/usr/bin/env python3
"""How long enemy hooks land on our pudge: its speed and own-cast state at
the moment of the hit, over the replay_survey.py episode rows.

    hit_exposure.py evals/<label>/replay_survey.json [more surveys...] [--long 45]

For each survey (one eval arm) prints per game: long (>= LONG tiles) enemy
hooks landed on us, the share where we were stationary (< 2 tiles/s from the
last 4 Hz state sample), the share where our hook cooldown was >= 48 ticks
(HookCooldownTicks 65 - 17: we cast within the last ~17 ticks, i.e. rooted
by the 9-tick windup or still re-accelerating from it), deaths, throws.
The engine sample precedes the hit by <= 8 ticks, so speed and cooldown are
approximate. Writes <survey>.hit_exposure.json next to each input.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

CAST_CD = 48


def exposure(rows: list[dict[str, Any]], long: float) -> dict[str, Any]:
    n = len(rows)
    hits = [h for r in rows for h in r["opp_hits_on_me"] if h["dist"] >= long and h.get("my_layer") in (0, 1)]
    stationary = [h for h in hits if (h.get("my_speed") or 0) < 2]
    casting = [h for h in hits if (h.get("my_cd") or 0) >= CAST_CD]
    slow = [h for h in hits if 2 <= (h.get("my_speed") or 0) < 10]
    all_hits = [h for r in rows for h in r["opp_hits_on_me"]]
    return {
        "n": n,
        "long_hits_on_me_per_game": round(len(hits) / n, 2),
        "all_hits_on_me_per_game": round(len(all_hits) / n, 2),
        "stationary_share": round(len(stationary) / max(1, len(hits)), 3),
        "slow_share": round(len(slow) / max(1, len(hits)), 3),
        "casting_share": round(len(casting) / max(1, len(hits)), 3),
        "casting_and_stationary_share": round(sum((h.get("my_speed") or 0) < 2 for h in casting) / max(1, len(hits)), 3),
        "casting_hits_per_game": round(len(casting) / n, 2),
        "deaths_per_game": round(sum(r["my_deaths"] for r in rows) / n, 2),
        "kills_per_game": round(sum(r["my_kills"] for r in rows) / n, 2),
        "my_thrown_per_game": round(sum(r["my_thrown"] for r in rows) / n, 1),
        "my_landed_per_game": round(sum(r["my_landed"] for r in rows) / n, 1),
        "opp_thrown_per_game": round(sum(r["opp_thrown"] for r in rows) / n, 1),
        "my_river_sec": round(sum(r["my_river_sec"] for r in rows) / n, 1),
        "my_runes": round(sum(r["my_runes"] for r in rows) / n, 1),
        "win_rate": round(sum(r["score"] for r in rows) / n, 3),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("surveys", nargs="+", type=Path)
    ap.add_argument("--long", type=float, default=45)
    a = ap.parse_args()
    for path in a.surveys:
        rows = json.loads(path.read_text())["episodes"]
        out = {"overall": exposure(rows, a.long),
               "by_team": {t: exposure([r for r in rows if r["team"] == t], a.long) for t in ("west", "east")
                           if any(r["team"] == t for r in rows)},
               "by_opponent": {k: exposure([r for r in rows if ",".join(r["opponents"]) == k], a.long)
                               for k in sorted({",".join(r["opponents"]) for r in rows})}}
        path.with_suffix(".hit_exposure.json").write_text(json.dumps(out, indent=1) + "\n")
        print(path)
        print(json.dumps(out["overall"], indent=1))


if __name__ == "__main__":
    main()
