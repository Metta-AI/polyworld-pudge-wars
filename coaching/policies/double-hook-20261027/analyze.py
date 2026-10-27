"""Summarize paired-bank matches and verified replay events for this experiment."""
import argparse
from collections import Counter, defaultdict
import gzip
import json
from pathlib import Path
import random


def summarize(root):
    rows = [json.loads(line) for line in (root / "games.jsonl").read_text().splitlines()]
    if not rows:
        raise ValueError("No completed games")
    banks = defaultdict(set)
    counts = {role: Counter() for role in ("candidate", "opponent")}
    pairs = defaultdict(list)
    headshot_pairs = defaultdict(list)
    for row in rows:
        if not row["replayVerified"]:
            raise ValueError("Unverified replay")
        if row["side"] not in ("west", "east") or row["side"] in banks[row["seed"]]:
            raise ValueError("Invalid or repeated bank for a map")
        banks[row["seed"]].add(row["side"])
        pairs[row["seed"]].append(row["ours"] - row["theirs"])
        path = Path(row["summary"])
        summary = json.loads(path.read_text())
        teams = {player["id"]: player["team"] for player in summary["players"]}
        headshot_pairs[row["seed"]].append(sum(
            player["headshots"] * (1 if player["team"] == row["side"] else -1)
            for player in summary["players"]))
        for player in summary["players"]:
            role = "candidate" if player["team"] == row["side"] else "opponent"
            for key in ("headshots", "hooksThrown", "hooksLanded", "kills"):
                counts[role][key] += player[key]
        events = path.with_name("events.jsonl")
        stream = events.open() if events.exists() else gzip.open(str(events) + ".gz", "rt")
        with stream:
            for line in stream:
                event = json.loads(line)
                if event["ev"] == "hook_landed" and event["victim"] in teams:
                    if teams[event["id"]] != teams[event["victim"]]:
                        role = "candidate" if teams[event["id"]] == row["side"] else "opponent"
                        counts[role]["enemyCatches"] += 1
    if any(len(pair) != 2 for pair in pairs.values()):
        raise ValueError("Each map must have both banks")
    margins = [sum(pair) / 2 for pair in pairs.values()]
    rng = random.Random(102727)
    samples = sorted(sum(rng.choices(margins, k=len(margins))) / len(margins) for _ in range(10000))
    headshot_margins = [sum(pair) / 2 for pair in headshot_pairs.values()]
    headshot_rng = random.Random(102727)
    headshot_samples = sorted(
        sum(headshot_rng.choices(headshot_margins, k=len(headshot_margins))) / len(headshot_margins)
        for _ in range(10000))
    return {
        "games": len(rows), "wins": sum(row["win"] for row in rows),
        "timeLimits": sum(row["timeLimit"] for row in rows),
        "meanKillMargin": sum(margins) / len(margins),
        "pairedMapBootstrap95": [samples[250], samples[9750]],
        "meanHeadshotDifference": sum(headshot_margins) / len(headshot_margins),
        "pairedMapHeadshotBootstrap95": [headshot_samples[250], headshot_samples[9750]],
        "banks": {side: {"games": sum(row["side"] == side for row in rows),
                         "wins": sum(row["win"] for row in rows if row["side"] == side)}
                  for side in ("west", "east")},
        "counts": {role: dict(count) for role, count in counts.items()},
        "headshotsPerEnemyCatch": {role: count["headshots"] / max(1, count["enemyCatches"])
                                   for role, count in counts.items()},
        "allReplaysVerified": True,
        "note": "Ratios are descriptive totals, not independent causal estimates; friendly heals are excluded from enemy catches. Intervals are per variant and unadjusted for multiple experiments.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("matches", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    report = summarize(args.matches)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
