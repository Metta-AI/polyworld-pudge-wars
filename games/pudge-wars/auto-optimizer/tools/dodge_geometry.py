#!/usr/bin/env python3
"""Dodge geometry of long enemy hooks over decoded hosted replays: which side
of the hook's flight line we were on, which way we ran, and whether it hit.

    dodge_geometry.py <replay_root> --out <json> [--long 30]

Same replay root layout as replay_survey.py. For every enemy `hook_launched`
whose logger `target` is our pudge at >= LONG tiles, the flight line is
from -> aim (extended). `off0` is our signed perpendicular offset from that
line at the last 4 Hz state sample before launch, `off1` at the last sample
before the hook lands or is reported missed, `run` is our lateral speed
along the line normal at that last sample (positive = away from the line).
The engine samples are <= 8 ticks stale, so treat the numbers as
approximate. Outcome per hook: hit (landed on us) or miss.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any


def normal(frm: list[float], aim: list[float]) -> tuple[float, float]:
    dx, dy = aim[0] - frm[0], aim[1] - frm[1]
    n = math.hypot(dx, dy) or 1.0
    return -dy / n, dx / n


def episode(folder: Path, long: float) -> list[dict[str, Any]] | None:
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
    my_state: dict[str, Any] = {}
    launches: dict[int, dict[str, Any]] = {}
    out: list[dict[str, Any]] = []
    for e in events:
        ev = e["ev"]
        if ev == "state":
            for p in e["p"]:
                if p["id"] == me:
                    my_state = {**p, "t": e["t"]}
        elif ev == "hook_launched" and e["id"] != me:
            tgt = e.get("target") or {}
            if tgt.get("id") == me and tgt.get("dist", 0) >= long and my_state:
                nx, ny = normal(e["from"], e["aim"])
                off0 = (my_state["x"] - e["from"][0]) * nx + (my_state["y"] - e["from"][1]) * ny
                run0 = (my_state.get("vx", 0) * nx + my_state.get("vy", 0) * ny) * (1 if off0 >= 0 else -1)
                launches[e["hookId"]] = {"t": e["t"], "dist": tgt["dist"], "n": (nx, ny), "from": e["from"],
                                         "off0": round(off0, 2), "run0": round(run0, 2), "hp": tgt.get("hp"),
                                         "opponents": row["opponents"], "team": row["team"], "score": row["score"]}
        elif ev in ("hook_landed", "hook_missed") and e["hookId"] in launches:
            L = launches.pop(e["hookId"])
            nx, ny = L["n"]
            off1 = (my_state["x"] - L["from"][0]) * nx + (my_state["y"] - L["from"][1]) * ny
            run1 = (my_state.get("vx", 0) * nx + my_state.get("vy", 0) * ny) * (1 if L["off0"] >= 0 else -1)
            hit = ev == "hook_landed" and e.get("victim") == me
            out.append({**{k: v for k, v in L.items() if k not in ("n", "from")}, "off1": round(off1, 2),
                        "run1": round(run1, 2), "flight": e["t"] - L["t"], "hit": hit,
                        "speed1": round(math.hypot(my_state.get("vx", 0), my_state.get("vy", 0)), 1),
                        "cd1": my_state.get("cd")})
    return out


def agg(rows: list[dict[str, Any]]) -> dict[str, Any]:
    n = len(rows)
    if not n:
        return {"n": 0}
    hits = [r for r in rows if r["hit"]]

    def rate(sel: list[dict[str, Any]]) -> dict[str, Any]:
        return {"n": len(sel), "hit_rate": round(sum(r["hit"] for r in sel) / len(sel), 3) if sel else None}

    away = [r for r in rows if r["run1"] > 2]
    toward = [r for r in rows if r["run1"] < -2]
    still = [r for r in rows if -2 <= r["run1"] <= 2]
    return {
        "n": n, "hits": len(hits), "hit_rate": round(len(hits) / n, 3),
        "by_lateral_run_at_end": {"away_from_line": rate(away), "toward_line": rate(toward), "still": rate(still)},
        "by_offset_at_launch": {f"|off0| {lo}-{hi}": rate([r for r in rows if lo <= abs(r["off0"]) < hi])
                                for lo, hi in ((0, 2), (2, 5), (5, 10), (10, 1000))},
        "hits_by_lateral_run_at_end": dict(Counter("away" if r["run1"] > 2 else "toward" if r["run1"] < -2 else "still"
                                                   for r in hits)),
        "hits_casting_share": round(sum((r["cd1"] or 0) >= 48 for r in hits) / max(1, len(hits)), 3),
        "hits_off1_q25_50_75": [round(sorted(abs(r["off1"]) for r in hits)[int(q * (len(hits) - 1))], 2)
                                for q in (0.25, 0.5, 0.75)] if hits else [],
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--long", type=float, default=30)
    a = ap.parse_args()
    rows: list[dict[str, Any]] = []
    games = 0
    for folder in sorted(p for p in a.root.iterdir() if p.is_dir()):
        got = episode(folder, a.long)
        if got is not None:
            games += 1
            rows.extend(got)
    result = {"games": games, "hooks_per_game": round(len(rows) / max(1, games), 1), "overall": agg(rows),
              "by_opponent": {k: agg([r for r in rows if ",".join(r["opponents"]) == k])
                              for k in sorted({",".join(r["opponents"]) for r in rows})},
              "by_team": {t: agg([r for r in rows if r["team"] == t]) for t in ("west", "east")}}
    a.out.write_text(json.dumps(result, indent=1) + "\n")
    print(json.dumps({k: result[k] for k in ("games", "hooks_per_game", "overall")}, indent=1))


if __name__ == "__main__":
    main()
