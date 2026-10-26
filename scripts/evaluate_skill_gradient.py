#!/usr/bin/env python3
"""Bank-balanced local BASIC self-play; seed blocks are the statistical unit."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
import statistics

from run_episode import run_episode, write_json


def summarize(rows: list[dict]) -> dict:
    blocks = {}
    for row in rows:
        key = row["seed"]
        bank = row["candidate_bank"]
        if bank not in (0, 1) or bank in blocks.setdefault(key, {}):
            raise ValueError("Invalid or duplicate seed/bank")
        blocks[key][bank] = row["margin"]
    if not blocks or any(set(banks) != {0, 1} for banks in blocks.values()):
        raise ValueError("Every seed must have both banks")
    means = [statistics.mean(banks.values()) for banks in blocks.values()]
    rng = random.Random(0)
    bootstrap = sorted(statistics.mean(rng.choices(means, k=len(means)))
                       for _ in range(10000))
    return {
        "games": len(rows), "seed_blocks": len(means),
        "wins": sum(r["margin"] > 0 for r in rows),
        "draws": sum(r["margin"] == 0 for r in rows),
        "losses": sum(r["margin"] < 0 for r in rows),
        "mean_margin": statistics.mean(means),
        "margin_seed_bootstrap_95": [bootstrap[249], bootstrap[9749]],
        "end_reasons": dict(Counter(r["end_reason"] for r in rows)),
        "banks": {str(bank): {
            "mean_margin": statistics.mean(r["margin"] for r in rows
                                           if r["candidate_bank"] == bank),
            "wins": sum(r["margin"] > 0 for r in rows if r["candidate_bank"] == bank),
            "draws": sum(r["margin"] == 0 for r in rows if r["candidate_bank"] == bank),
            "losses": sum(r["margin"] < 0 for r in rows if r["candidate_bank"] == bank),
        } for bank in (0, 1)},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--first-seed", type=int, required=True)
    parser.add_argument("--seeds", type=int, default=24)
    parser.add_argument("--team-size", type=int, choices=(1, 3), required=True)
    args = parser.parse_args()
    if args.seeds < 2 or not -(2**31) <= args.first_seed <= 2**31 - args.seeds:
        parser.error("Need at least two distinct int32 seeds")
    output, binary = args.output.resolve(), args.binary.resolve()
    # Snapshot all executable inputs before the first match, not between games.
    sources = [p.resolve().read_bytes() for p in (args.candidate, args.baseline)]
    executable = binary.read_bytes()
    output.mkdir(parents=True, exist_ok=False)
    binary = output / "pwleague"
    binary.write_bytes(executable)
    binary.chmod(0o755)
    policies = []
    for label, data in zip(("candidate", "baseline"), sources):
        path = output / (label + ".bas")
        path.write_bytes(data)
        policies.append(path)
    manifest = {
        "candidate_sha256": hashlib.sha256(sources[0]).hexdigest(),
        "baseline_sha256": hashlib.sha256(sources[1]).hexdigest(),
        "binary_sha256": hashlib.sha256(executable).hexdigest(),
        "team_size": args.team_size,
        "seeds": list(range(args.first_seed, args.first_seed + args.seeds)),
        "ticks": 15360 if args.team_size == 1 else 38400,
        "kill_goal": 10 if args.team_size == 1 else 30,
        "scope": "local self-play; no hosted or human-play inference",
        "interval_method": "10000 percentile bootstrap draws of seed means; RNG seed 0",
    }
    write_json(output / "manifest.json", manifest)
    rows = []
    for seed in manifest["seeds"]:
        for bank in (0, 1):
            episode = output / f"seed-{seed}-bank-{bank}"
            episode.mkdir()
            roster = ([policies[bank]] * args.team_size +
                      [policies[1 - bank]] * args.team_size)
            status = run_episode(roster, episode, binary, seed, manifest["ticks"],
                                 manifest["kill_goal"], 120)
            if status:
                raise RuntimeError(f"Invalid episode {episode}: status {status}")
            result = json.loads((episode / "results.json").read_text())
            if result["seed"] != seed or result["kill_goal"] != manifest["kill_goal"]:
                raise RuntimeError(f"Config mismatch: {episode}")
            expected_winner = ("west" if result["west_kills"] > result["east_kills"] else
                               "east" if result["east_kills"] > result["west_kills"] else "draw")
            if result["winner_team"] != expected_winner:
                raise RuntimeError(f"Winner does not match kill-margin scoring: {episode}")
            margin = (result["west_kills"] - result["east_kills"]) * (1 if bank == 0 else -1)
            rows.append(dict(result, candidate_bank=bank, margin=margin))
            write_json(output / "games.json", rows)
    write_json(output / "summary.json", dict(manifest, **summarize(rows)))
    print((output / "summary.json").read_text())


if __name__ == "__main__":
    main()
