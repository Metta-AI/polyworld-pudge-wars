#!/usr/bin/env python3
"""Offline aim-lead sweep over decoded hosted replays.

For every long hook our seat launched at a visible enemy, replay the target's
actual motion (4 Hz `state` samples, linearly interpolated) against a straight
hook flight from `hook_launched.from` toward a counterfactual aim point, and
count how many throws would have passed within the contact radius.

The model is validated first: the actual aim must reproduce the engine's
landed/missed outcome for most throws (reported as `agreement`). Counterfactual
counts are only indicative: the target's dodge reacts to the real hook, not to
the alternative one, so this cannot replace a hosted A/B.

    lead_sweep.py <replay_root> --out <json>

Aim rule under test (coworld/player/base.py):
    aim = target + v8 * span / (30 + damage_level)      # v8 = tiles per 8 ticks
where span = max(|dx|, |dy|). The sweep rescales the divisor.
"""
from __future__ import annotations

import argparse
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any

DIVISORS = (1e9, 60.0, 30.0, 20.0, 15.0, 12.0, 10.0, 8.0, 6.0, 5.0)
# Engine constants (examples/pudge_wars/content.nim, sim.nim climbHookSpeed):
# the outbound head accelerates by HookAccel every tick up to 3x BaseHookSpeed.
BASE_HOOK_TILES_PER_TICK = 20.16 / 32.0
HOOK_ACCEL_TILES_PER_TICK = BASE_HOOK_TILES_PER_TICK * 1_800 / 36_000
HOOK_MAX_TILES_PER_TICK = BASE_HOOK_TILES_PER_TICK * 3


def flight(speed0: float, reach: float) -> list[float]:
    """Head distance from the owner after each outbound tick."""
    out: list[float] = []
    d, v = 0.0, speed0
    while d < reach:
        d += v
        out.append(min(d, reach))
        v = min(HOOK_MAX_TILES_PER_TICK, v + HOOK_ACCEL_TILES_PER_TICK)
    return out


def interp(samples: list[tuple[int, float, float]], t: float) -> tuple[float, float] | None:
    lo, hi = 0, len(samples) - 1
    if not samples or t < samples[0][0] or t > samples[-1][0]:
        return None
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if samples[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    t0, x0, y0 = samples[lo]
    t1, x1, y1 = samples[hi]
    f = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
    return x0 + (x1 - x0) * f, y0 + (y1 - y0) * f


def closest_approach(start: list[float], aim: list[float], reach: float, speed: float, t0: int,
                     track: list[tuple[int, float, float]]) -> float:
    dx, dy = aim[0] - start[0], aim[1] - start[1]
    length = math.hypot(dx, dy)
    if length < 1e-6:
        return 1e9
    ux, uy = dx / length, dy / length
    best = 1e9
    for k, d in enumerate(flight(speed, reach), start=1):
        hx, hy = start[0] + ux * d, start[1] + uy * d
        pos = interp(track, t0 + k)
        if pos is None:
            break
        best = min(best, math.hypot(hx - pos[0], hy - pos[1]))
    return best


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--min-dist", type=float, default=30.0)
    ap.add_argument("--radius", type=float, default=None, help="contact radius; fitted from actual outcomes when omitted")
    args = ap.parse_args()

    throws: list[dict[str, Any]] = []
    for folder in sorted(args.root.iterdir()):
        if not (folder / "row.json").exists() or not (folder / "decoded" / "latest" / "events.jsonl").exists():
            continue
        row = json.loads((folder / "row.json").read_text())
        events = [json.loads(line) for line in (folder / "decoded" / "latest" / "events.jsonl").open()]
        start = next(e for e in events if e["ev"] == "match_start")
        me = next(p["id"] for p in start["players"] if p["seat"] == row["slot"])
        tracks: dict[int, list[tuple[int, float, float]]] = defaultdict(list)
        for e in events:
            if e["ev"] == "state":
                for p in e["p"]:
                    if p["alive"]:
                        tracks[p["id"]].append((e["t"], p["x"], p["y"]))
        outcome: dict[int, str] = {}
        for e in events:
            if e["ev"] == "hook_landed":
                outcome[e["hookId"]] = "landed"
            elif e["ev"] == "hook_missed":
                outcome[e["hookId"]] = "missed"
            elif e["ev"] == "hook_resolved":
                outcome.setdefault(e["hookId"], e["result"])
        for e in events:
            if e["ev"] != "hook_launched" or e["id"] != me:
                continue
            tgt = e.get("target")
            if not tgt or tgt["dist"] < args.min_dist or tgt["dist"] > e["rangeTiles"] + 4:
                continue
            res = outcome.get(e["hookId"], "unknown")
            if res not in {"landed", "missed"}:
                continue  # denied / cancelled hooks carry no aim information
            throws.append({"opp": row["opponents"][0], "team": row["team"], "t": e["t"], "from": e["from"], "aim": e["aim"],
                           "reach": e["rangeTiles"], "speed": e["speedTilesPerSec"] / 32.0, "target": tgt["pos"],
                           "vel": tgt["vel"], "dist": tgt["dist"], "result": res, "track": tracks[tgt["id"]]})
    print(f"{len(throws)} long throws with landed/missed outcomes")

    # Validate: actual aim vs actual outcome; fit radius if needed.
    actual = [closest_approach(t["from"], t["aim"], t["reach"], t["speed"], t["t"], t["track"]) for t in throws]
    radius = args.radius
    if radius is None:
        best = (0, 0.0)
        for r10 in range(10, 80):
            r = r10 / 10
            agree = sum((a <= r) == (t["result"] == "landed") for a, t in zip(actual, throws))
            if agree > best[0]:
                best = (agree, r)
        radius = best[1]
    agree = sum((a <= radius) == (t["result"] == "landed") for a, t in zip(actual, throws))
    landed = sum(t["result"] == "landed" for t in throws)
    predicted = sum(a <= radius for a in actual)
    print(f"radius={radius} agreement={agree}/{len(throws)} actual_landed={landed} model_landed={predicted}")

    sweep: dict[str, Any] = {}
    for div in DIVISORS:
        hits = 0
        by_opp: dict[str, list[int]] = defaultdict(lambda: [0, 0])
        for t in throws:
            span = max(abs(t["from"][0] - t["target"][0]), abs(t["from"][1] - t["target"][1]))
            v8 = [t["vel"][0] / 4.0, t["vel"][1] / 4.0]  # tiles/s -> tiles per 8 ticks
            aim = [t["target"][0] + v8[0] * span / div, t["target"][1] + v8[1] * span / div]
            hit = closest_approach(t["from"], aim, t["reach"], t["speed"], t["t"], t["track"]) <= radius
            hits += hit
            by_opp[t["opp"]][0] += hit
            by_opp[t["opp"]][1] += 1
        label = "none" if div > 1e8 else f"span/{div:g}"
        sweep[label] = {"hits": hits, "rate": hits / max(1, len(throws)),
                        "by_opp": {k: {"hits": v[0], "n": v[1], "rate": v[0] / v[1]} for k, v in by_opp.items()}}
        print(f"{label:10s} hits={hits:4d} rate={hits / max(1, len(throws)):.3f} " +
              " ".join(f"{k.split(':')[0][-12:]}={v[0] / v[1]:.3f}" for k, v in sorted(by_opp.items())))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps({"throws": len(throws), "radius": radius, "agreement": agree, "actual_landed": landed,
                                    "model_landed_actual_aim": predicted, "sweep": sweep}, indent=2) + "\n")


if __name__ == "__main__":
    main()
