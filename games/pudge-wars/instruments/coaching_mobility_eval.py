#!/usr/bin/env python3
"""Matched, local coaching-policy comparisons with engine-observed movement.

No human seats. Each seed is run on both banks, with frozen opponents. A seed
pair is the sampling unit; individual games are not independent seed samples.
Motion comes from coaching_match.nim's truth trace, not policy move requests.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def measure(directory, candidate_side):
    directory = Path(directory)
    result = json.loads((directory / "result.json").read_text())
    seats = [s for s in result["seats"] if s["team"] == candidate_side]
    ids = {s["id"] for s in seats}
    events = [json.loads(line) for line in (directory / "events.jsonl").read_text().splitlines()]
    motion = [json.loads(line) for line in (directory / "motion.jsonl").read_text().splitlines()]
    eligible = moving = 0
    runs = dict.fromkeys(ids, 0)
    longest = 0
    moving_ticks = {id: [] for id in ids}
    for sample in motion:
        for p in sample["p"]:
            if p["id"] not in ids:
                continue
            id = p["id"]
            if p["eligible"]:
                eligible += 1
                moving += int(p["moving"])
                if p["moving"]:
                    moving_ticks[id].append(sample["t"])
            runs[id] = runs[id] + 8 if p["eligible"] and not p["moving"] else 0
            longest = max(longest, runs[id])
    launches = [e for e in events if e["ev"] == "hook_launched" and e["id"] in ids and e["t"] >= 320]
    active_launches = sum(any(0 < e["t"]-t <= 64 for t in moving_ticks[e["id"]]) for e in launches)
    kills = [e for e in events if e["ev"] == "kill" and e.get("killer") in ids]
    a, b = result["score"][candidate_side], result["score"][1-candidate_side]
    return {"seed": result["seed"], "side": candidate_side, "score": [a, b],
            "win": int(a > b), "loss": int(a < b), "draw": int(a == b),
            "eligible_samples": eligible, "moving_samples": moving,
            "moving_fraction": moving / eligible if eligible else None,
            "longest_stationary_seconds": longest / 32,
            "hook_launches_after_10s": len(launches),
            "hook_launches_after_recent_movement": active_launches,
            "hooks_thrown": sum(s["hooks_thrown"] for s in seats),
            "reported_hooks_landed": sum(s["hooks_landed"] for s in seats),
            "first_kill_seconds": kills[0]["t"] / 32 if kills else None,
            "vm_failures": sum(s["vm_failed"] for s in seats),
            "replay_resimulatable": result["replay_resimulatable"]}


def summarize(rows):
    out = {}
    for name in sorted({r["pairing"] for r in rows}):
        group = [r for r in rows if r["pairing"] == name]
        keys = ("win", "loss", "draw", "eligible_samples", "moving_samples", "hooks_thrown",
                "reported_hooks_landed", "hook_launches_after_10s", "hook_launches_after_recent_movement", "vm_failures")
        d = {key: sum(r[key] for r in group) for key in keys}
        d.update(games=len(group), seeds=sorted({r["seed"] for r in group}),
                 score=[sum(r["score"][i] for r in group) for i in (0, 1)],
                 moving_fraction=d["moving_samples"]/d["eligible_samples"] if d["eligible_samples"] else None,
                 longest_stationary_seconds=max(r["longest_stationary_seconds"] for r in group))
        if name.endswith("-self"):
            d["west_wins"] = d.pop("win")
            d["east_wins"] = d.pop("loss")
            d["perspective"] = "West-team metrics; the identical policy also controls east."
            d["diagnostic_only"] = True
        out[name] = d
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("binary", "candidate", "previous", "blank", "base", "output"):
        p.add_argument("--" + name, type=Path, required=True)
    p.add_argument("--seeds", type=int, nargs="+", required=True)
    p.add_argument("--ticks", type=int, default=3840)
    p.add_argument("--self-play-only", action="store_true", help="Run just the candidate and previous-policy self-play diagnostics.")
    a = p.parse_args()
    a.output.mkdir(exist_ok=False, parents=True)
    files = {name: {"path": str(getattr(a, name).resolve()), "sha256": sha(getattr(a, name))}
             for name in ("binary", "candidate", "previous", "blank", "base")}
    protocol = {"files": files, "seeds": a.seeds, "ticks": a.ticks, "team_size": 3,
                "human_present": False, "bot_every": 1, "aim_noise": 0, "kill_goal": 30,
                "sampling_unit": "One seed with both candidate banks; no tuning after confirmation.",
                "self_play": "Candidate and previous policy each play themselves once per seed; all six seats use identical code. Outcomes describe bank differences, not policy improvement.",
                "movement": "4Hz engine truth samples after 10s, alive on home bank, not pulled or in windup, no living unshielded unpulled enemy within 8 tiles on the same layer; moving means speed >1 tile/s.",
                "recent_movement": "Hook launch after at least one eligible moving sample in the preceding 2s, not simultaneous motion during windup.",
                "limits": ["Movement is a conditional behavior metric, not an independent measure of strength.",
                           "Engine hook counters can include friendly contacts; logger contacts are incomplete.",
                           "Base is a calibration opponent, not a generic-autoresearch control."]}
    (a.output / "protocol.json").write_text(json.dumps(protocol, indent=2) + "\n")
    jobs = []
    pairings = [("previous-blank", a.previous, a.blank), ("candidate-blank", a.candidate, a.blank),
                               ("previous-base", a.previous, a.base), ("candidate-base", a.candidate, a.base),
                               ("candidate-previous", a.candidate, a.previous),
                               ("candidate-self", a.candidate, a.candidate),
                               ("previous-self", a.previous, a.previous)]
    for name, first, other in pairings:
        if a.self_play_only and not name.endswith("-self"):
            continue
        for seed in a.seeds:
            # Reversing identical scripts would duplicate the same rollout.
            for side in ((0,) if name.endswith("-self") else (0, 1)):
                directory = a.output / f"{name}-{seed}-{side}"
                pair = [first, other] if side == 0 else [other, first]
                command = [str(a.binary.resolve()), *map(str, pair), "3", str(seed), str(a.ticks), str(directory), "-", "1", "0"]
                jobs.append((name, side, directory, command))
    def run(job):
        name, side, directory, command = job
        proc = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if proc.returncode:
            raise RuntimeError(f"{directory}: {proc.stderr}")
        row = measure(directory, side)
        row.update(pairing=name, directory=str(directory), command=command)
        return row
    with ThreadPoolExecutor(max_workers=3) as pool:
        rows = list(pool.map(run, jobs))
    for name, info in files.items():
        if sha(info["path"]) != info["sha256"]:
            raise RuntimeError(f"Input changed during evaluation: {name}")
    summary = summarize(rows)
    (a.output / "matches.json").write_text(json.dumps(rows, indent=2) + "\n")
    (a.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
