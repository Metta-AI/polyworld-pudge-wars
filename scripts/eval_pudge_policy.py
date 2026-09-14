#!/usr/bin/env python3
"""Compare BASIC policies on paired banks using a frozen headless runner."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("policy", type=Path)
    parser.add_argument("opponent", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--runner", type=Path, default=Path("pwheadless"))
    parser.add_argument("--first", type=int, default=1)
    parser.add_argument("--last", type=int, default=24)
    parser.add_argument("--team-size", type=int, default=3)
    parser.add_argument("--goal", type=int, default=30)
    parser.add_argument("--minutes", type=int, default=20)
    parser.add_argument("--difficulty", choices=["easy", "fair", "pro"], default="fair")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--record", action="store_true", help="Record and verify every replay")
    args = parser.parse_args()
    if args.first > args.last or min(args.team_size, args.goal, args.minutes, args.jobs) < 1:
        parser.error("invalid seed range or nonpositive match setting")
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=False)
    identities = {}
    for name in ["runner", "policy", "opponent"]:
        source = getattr(args, name).resolve()
        identities[name] = {"path": str(source), "sha256": hashlib.sha256(source.read_bytes()).hexdigest()}
        setattr(args, name, source)
    (args.output / "contract.json").write_text(json.dumps({
        "settings": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "identities": identities,
    }, indent=2) + "\n")

    def play(pair):
        seed, side = pair
        directory = args.output / f"{seed}-{side}"
        directory.mkdir()
        west, east = (args.policy, args.opponent) if side == "west" else (args.opponent, args.policy)
        command = [str(args.runner), "--team-size", str(args.team_size),
                   "--difficulty", args.difficulty, "--seed", str(seed),
                   "--killGoal", str(args.goal), "--minutes", str(args.minutes),
                   "--bot", f"{west}:{args.team_size}", "--bot", f"{east}:{args.team_size}"]
        if args.record:
            command += ["--duellog", str(directory)]
        started = time.monotonic()
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        output = result.stdout + result.stderr
        (directory / "console.log").write_text(output)
        total = args.team_size * 2
        if result.returncode or not re.search(rf"^scripts: {total}/{total} active,", output, re.M):
            raise RuntimeError(f"Match/VM failure: {directory}")
        score = re.search(r"^score: west (\d+) / east (\d+)", output, re.M)
        if not score:
            raise RuntimeError(f"Missing terminal score: {directory}")
        ours, theirs = map(int, score.groups())
        if side == "east":
            ours, theirs = theirs, ours
        row = {"seed": seed, "side": side, "ours": ours, "theirs": theirs,
               "win": ours >= args.goal and ours > theirs,
               "timeLimit": max(ours, theirs) < args.goal,
               "wallSeconds": time.monotonic() - started}
        if args.record:
            summaries = list(directory.glob("match_*/summary.json"))
            if len(summaries) != 1:
                raise RuntimeError(f"Expected one summary: {directory}")
            summary = json.loads(summaries[0].read_text())
            row.update(reason=summary["reason"], outcome=summary["outcome"],
                       summary=str(summaries[0]))
            replay = subprocess.run([str(args.runner), "--replay", str(summaries[0].with_name("replay.pwr"))],
                                    capture_output=True, text=True, timeout=180)
            (directory / "replay-check.log").write_text(replay.stdout + replay.stderr)
            if replay.returncode or "replay verified: every tick matched" not in replay.stdout:
                raise RuntimeError(f"Replay verification failed: {directory}")
            row["replayVerified"] = True
        return row

    pairs = [(seed, side) for seed in range(args.first, args.last + 1) for side in ["west", "east"]]
    rows = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for row in pool.map(play, pairs):
            rows.append(row)
            with (args.output / "games.jsonl").open("a") as stream:
                stream.write(json.dumps(row) + "\n")
    report = {"games": len(rows), "wins": sum(r["win"] for r in rows),
              "timeLimits": sum(r["timeLimit"] for r in rows),
              "meanKills": sum(r["ours"] for r in rows) / len(rows),
              "meanOpponentKills": sum(r["theirs"] for r in rows) / len(rows)}
    for name, identity in identities.items():
        if hashlib.sha256(getattr(args, name).read_bytes()).hexdigest() != identity["sha256"]:
            raise RuntimeError(f"{name} changed during evaluation")
    (args.output / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(args.output.name, json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
