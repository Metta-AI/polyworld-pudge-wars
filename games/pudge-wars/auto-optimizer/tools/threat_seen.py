#!/usr/bin/env python3
"""Tabulate the `threat_seen` trace events of a triaged XP eval.

    threat_seen.py --label iter8-directional

Reads evals/<label>/logs/*.txt (written by log_triage.py) and prints the
first-sight distance and own-speed distributions of the walking dodge, per
game, so the reaction window the early-dodge hypothesis relies on can be
checked against the decoder survey. Writes evals/<label>/threat_seen.json.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from hosted import EVALS, save_json

TRACE_RE = re.compile(r"policy_trace (\[.*?\])(?=\\n|$)")


def quantiles(xs: list[float]) -> list[float]:
    if not xs:
        return []
    s = sorted(xs)
    return [round(s[int(q * (len(s) - 1))], 1) for q in (0.25, 0.5, 0.75)]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True)
    a = ap.parse_args()
    logs = sorted((EVALS / a.label / "logs").glob("*.txt"))
    dists: list[float] = []
    speeds: list[float] = []
    per_game: list[int] = []
    dist_bins: Counter[str] = Counter()
    for log in logs:
        text = log.read_text()
        n = 0
        for m in TRACE_RE.finditer(text):
            try:
                events = json.loads(m.group(1))
            except json.JSONDecodeError:
                continue
            for e in events:
                if e.get("event") != "threat_seen":
                    continue
                n += 1
                dists.append(e["dist"])
                speeds.append(e["speed"])
                d = e["dist"]
                dist_bins["<22" if d < 22 else "22-30" if d < 30 else "30-38" if d < 38 else "38-40"] += 1
        per_game.append(n)
    games = [g for g in per_game if g]
    out = {
        "logs": len(logs), "games_with_events": len(games),
        "threat_seen_per_game": round(sum(games) / len(games), 1) if games else 0,
        "dist_q25_50_75": quantiles(dists), "dist_bins": dict(dist_bins),
        "speed_q25_50_75": quantiles(speeds),
        "stationary_share": round(sum(s < 2 for s in speeds) / len(speeds), 3) if speeds else None,
    }
    save_json(EVALS / a.label / "threat_seen.json", out)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
