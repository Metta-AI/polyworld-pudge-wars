#!/usr/bin/env python3
"""Join a recorded coaching interval to native events using an explicit clock anchor.

python3 games/pudge-wars/instruments/coaching_session.py EVENTS.jsonl \
  --video-zero-tick 1896 --duration-ms 24686 --output NEW.json

The offset must be measured from the captured game clock or a trusted adapter.
Wall-clock start times alone are not sufficient. Logger 'target' is a nearest-
enemy heuristic, not an aim-intent label; damage-cause accounting is approximate.
"""
import argparse
import hashlib
import json
from pathlib import Path


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("events", type=Path)
    p.add_argument("--video-zero-tick", type=int, required=True)
    p.add_argument("--duration-ms", type=int, required=True)
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    if a.output.exists():
        p.error("Choose a new output file")
    raw = a.events.read_bytes()
    events = [json.loads(line) for line in raw.splitlines() if line.strip()]
    match = next(e for e in events if e["ev"] == "match_start")
    rate = match["tickRate"]
    end = a.video_zero_tick + rate * a.duration_ms / 1000
    actions, timeline, damage, kills = [], [], [], []
    counts = {}
    for e in events:
        if not a.video_zero_tick <= e["t"] <= end:
            continue
        row = {"video_ms_approx": round((e["t"] - a.video_zero_tick) * 1000 / rate), **e}
        counts[e["ev"]] = counts.get(e["ev"], 0) + 1
        if e["ev"] == "action":
            actions.append(row)
        if e["ev"] in ("hook_launched", "hook_landed", "hook_missed", "hook_resolved", "kill", "respawn"):
            timeline.append(row)
        if e["ev"] == "damage":
            damage.append(row)
        if e["ev"] == "kill":
            kills.append(row)
    result = {"source": str(a.events), "source_sha256": hashlib.sha256(raw).hexdigest(),
              "match": match, "video_zero_tick": a.video_zero_tick, "duration_ms": a.duration_ms,
              "counts": counts, "actions": actions, "timeline": timeline,
              "damage_events_approximate_attribution": damage, "kills": kills,
              "limits": ["Clock anchor supplied externally, not inferred by this tool.",
                         "Launch target field is a nearest-enemy heuristic, not intent.",
                         "Simultaneous melee/hook damage may be merged into one logger event."]}
    a.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"counts": counts, "kills": kills}))


if __name__ == "__main__":
    main()
