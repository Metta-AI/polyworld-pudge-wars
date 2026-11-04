#!/usr/bin/env python3
"""Download and triage the hosted policy logs of a summarized XP eval.

    log_triage.py --label iter3-directional --policy <version-id> [--policy-ref name:vN]

Reads evals/<label>/summary.json (written by `hosted.py xp summarize`), fetches
our agent's stdout/stderr for every clean episode into evals/<label>/logs/, and
writes evals/<label>/log_triage.json with per-episode traceback counts,
connection status and `policy_trace` event tallies (total and per game). A
traceback or a non-connecting episode is a policy bug, not eval noise: fix it
before reading the win rate.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path

from hosted import EVALS, client, save_json

EVENT_RE = re.compile(r'"event":\s*"([a-z_]+)"')
CLS_RE = re.compile(r'"event":\s*"threat_class"[^}]*?"cls":\s*"([a-z]+)"')


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--label", required=True)
    ap.add_argument("--policy", required=True, help="policy version UUID")
    ap.add_argument("--policy-ref", default=None)
    args = ap.parse_args()

    out_dir = EVALS / args.label
    summary = json.loads((out_dir / "summary.json").read_text())
    rows = []
    totals: Counter[str] = Counter()
    cls_totals: Counter[str] = Counter()
    tracebacks = 0
    nonparticipating = []
    with client() as c:
        for r in summary["clean_rows"]:
            agent = r["slot"]
            path = out_dir / "logs" / f"{r['id']}.agent{agent}.txt"
            if path.exists():
                text = path.read_text()
            else:
                text = c.get_text(f"/v2/episode-requests/{r['id']}/{args.policy}/policy-logs/{agent}")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text)
            tb = text.count("Traceback (most recent call last)")
            tracebacks += tb
            connected = "connecting" in text and len(text) > 200
            if not connected:
                nonparticipating.append(r["id"])
            events = Counter(EVENT_RE.findall(text))
            cls = Counter(CLS_RE.findall(text))
            totals.update(events)
            cls_totals.update(cls)
            rows.append({"id": r["id"], "team": r["team"], "score": r["score"], "opponents": r["opponents"],
                         "bytes": len(text), "tracebacks": tb, "connected": connected,
                         "events": dict(events), "threat_class": dict(cls)})
    n = max(1, len(rows))
    out = {"policy": args.policy_ref or args.policy, "xreq": summary.get("xreq_id"), "logs": len(rows),
           "tracebacks": tracebacks, "nonparticipating": nonparticipating,
           "event_totals": dict(totals), "event_per_game": {k: round(v / n, 1) for k, v in totals.items()},
           "threat_class_totals": dict(cls_totals),
           "threat_class_per_game": {k: round(v / n, 1) for k, v in cls_totals.items()},
           "rows": rows}
    save_json(out_dir / "log_triage.json", out)
    print(f"{out['policy']}: logs={len(rows)} tracebacks={tracebacks} nonparticipating={len(nonparticipating)}")
    print("events/game:", out["event_per_game"])
    if cls_totals:
        print("threat_class/game:", out["threat_class_per_game"])


if __name__ == "__main__":
    main()
