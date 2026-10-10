"""Edge-band exposure over decoded hosted replays: where a pudge stands on its
own bank (y band) and how often long enemy hooks aimed at it land there.

Same replay root layout as replay_survey.py (`EPISODE_ID/row.json` plus
`EPISODE_ID/decoded/latest/events.jsonl`). "Aimed at" uses the engine
logger's `hook_launched.target` (nearest enemy at launch), restricted to
in-range launches from 30+ tiles so short brawl hooks do not dilute the rate.

    edge_exposure.py <replay_root> --out <json> [--edge 24] [--mid 52]

Bands on the 16..112 play height: edge = y < EDGE or y > 128-EDGE,
mid = MID <= y <= 128-MID, lane = the rest.
"""
from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path


def band(y: float, edge: float, mid: float) -> str:
    if y < edge or y > 128 - edge:
        return "edge"
    if mid <= y <= 128 - mid:
        return "mid"
    return "lane"


def survey(root: Path, edge: float, mid: float) -> dict:
    ticks: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    hooks: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    episodes = 0
    for row_path in sorted(root.glob("*/row.json")):
        events_path = row_path.parent / "decoded" / "latest" / "events.jsonl"
        if not events_path.exists():
            continue
        row = json.loads(row_path.read_text())
        opponent = row["opponents"][0] if row.get("opponents") else "?"
        events = [json.loads(line) for line in events_path.open()]
        start = next(e for e in events if e["ev"] == "match_start")
        me = next(p["id"] for p in start["players"] if p["seat"] == row["slot"])
        my_team = 0 if row["team"] == "west" else 1
        episodes += 1
        outcome: dict[int, tuple[str, int | None]] = {}
        for e in events:
            if e["ev"] == "hook_landed":
                outcome[e["hookId"]] = ("landed", e["victim"])
            elif e["ev"] == "hook_missed":
                outcome[e["hookId"]] = ("missed", None)
        for e in events:
            if e["ev"] == "state":
                for p in e["p"]:
                    if not p["alive"]:
                        continue
                    who = "me" if p["id"] == me else f"opp:{opponent}"
                    team = my_team if p["id"] == me else 1 - my_team
                    if p["lay"] == team:
                        ticks[who][band(p["y"], edge, mid)] += 1
            elif e["ev"] == "hook_launched":
                t = e.get("target")
                if not t or t["dist"] < 30 or t["dist"] > e["rangeTiles"]:
                    continue
                res = outcome.get(e["hookId"])
                if res is None:
                    continue
                who = "me" if t["id"] == me else f"opp:{opponent}"
                b = band(t["pos"][1], edge, mid)
                hooks[who][f"{b}_n"] += 1
                hooks[who][f"{b}_landed"] += int(res[0] == "landed" and res[1] == t["id"])
    out: dict = {"episodes": episodes, "bands": {"edge": edge, "mid": mid}, "seats": {}}
    for who in sorted(ticks):
        total = sum(ticks[who].values())
        seat = {"own_bank_samples": total, "bands": {}}
        for b in ("edge", "lane", "mid"):
            n, landed = hooks[who][f"{b}_n"], hooks[who][f"{b}_landed"]
            seat["bands"][b] = {
                "time_share": round(ticks[who][b] / max(1, total), 3),
                "long_hooks_aimed_at": n,
                "landed": landed,
                "landed_rate": round(landed / max(1, n), 3),
                "landed_per_game": round(landed / max(1, episodes), 2),
            }
        out["seats"][who] = seat
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--edge", type=float, default=24)
    ap.add_argument("--mid", type=float, default=52)
    args = ap.parse_args()
    result = survey(args.root, args.edge, args.mid)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    for who, seat in result["seats"].items():
        print(who)
        for b, v in seat["bands"].items():
            print(f"  {b:5} share={v['time_share']:.2f} aimed={v['long_hooks_aimed_at']:5d} landed={v['landed_rate']:.3f} ({v['landed_per_game']}/game)")


if __name__ == "__main__":
    main()
