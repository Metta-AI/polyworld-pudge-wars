#!/usr/bin/env python3
"""Run local BASIC episodes through the league host, without Docker."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
POLICY_DIR = ROOT / "examples/pudge_wars/players"
POLICIES = ("base", "aggressive", "challenger", "denier", "patient", "sniper", "support", "jev")


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n")


def expand_policies(specifications: list[str]) -> list[Path]:
    policies = []
    for specification in specifications:
        name, count = specification, 1
        if not Path(name).expanduser().is_file() and ":" in name:
            name, count_text = name.rsplit(":", 1)
            try:
                count = int(count_text)
            except ValueError:
                raise ValueError(f"Invalid policy count in {specification!r}") from None
        if not 1 <= count <= 10:
            raise ValueError("Each policy count must be between 1 and 10")
        path = Path(name).expanduser()
        if not path.is_file() and name.removesuffix(".bas") in POLICIES:
            path = POLICY_DIR / (name.removesuffix(".bas") + ".bas")
        if not path.is_file():
            raise ValueError(f"Policy not found: {name}")
        policies.extend([path.resolve()] * count)
    if len(policies) not in (2, 4, 6, 8, 10):
        raise ValueError("Specify exactly 2, 4, 6, 8 or 10 seats; use PATH:COUNT to repeat a policy")
    return policies


def build_host(output: Path, nim: str) -> Path:
    binary = output / "pwleague"
    with tempfile.TemporaryDirectory(prefix="pudge-build-") as cache:
        command = [nim, "c", "--hints:off", "--threads:on", "-d:ssl", "-d:release",
                   "-d:basicLeague", f"--nimcache:{cache}", f"-o:{binary}",
                   "examples/pudge_wars/coworld_host.nim"]
        with (output / "build.log").open("w") as log:
            result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=log)
        if result.returncode:
            raise RuntimeError(f"Host build failed; see {output / 'build.log'}")
    return binary


def run_episode(policies: list[Path], output: Path, binary: Path,
                seed: int, ticks: int, kill_goal: int, timeout: float, llm: bool = False, llm_mode: str = "barrier") -> int:
    seats, provenance, sources = [], [], {}
    for slot, path in enumerate(policies):
        directory = output / "players" / str(slot)
        directory.mkdir(parents=True)
        # Snapshot the exact input bytes, including for repeated policy seats.
        if path not in sources:
            with path.open("rb") as source:
                sources[path] = source.read(16 * 1024 * 1024 + 1)
        data = sources[path]
        if len(data) > 16 * 1024 * 1024:
            raise ValueError(f"Policy exceeds the 16 MiB upload limit: {path}")
        (directory / "file").write_bytes(data)
        digest = "sha256:" + hashlib.sha256(data).hexdigest()
        seats.append({"slot": slot, "file_uri": (directory / "file").as_uri(),
                      "content_hash": digest, "size_bytes": len(data),
                      "log_uri": (directory / "log.txt").as_uri(),
                      "annotations_uri": (directory / "annotations.jsonl").as_uri()})
        provenance.append({"slot": slot, "team": "west" if slot < len(policies) // 2 else "east",
                           "source": str(path), "content_hash": digest})
    config = {"tokens": [f"local-{slot}" for slot in range(len(policies))],
              "players": [{"name": path.stem} for path in policies],
              "seed": seed, "max_ticks": ticks, "kill_goal": kill_goal, "fog": True, "wait_for_llm": llm_mode == "barrier"}
    write_json(output / "config.json", config)
    write_json(output / "player_seats.json", {"schema": "coworld-player-seats/2",
               "seats": seats, "player_status_uri": (output / "player_status.json").as_uri()})
    write_json(output / "episode.json", {"config": config, "policies": provenance,
               "binary": str(binary), "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest()})
    # Clear inherited runner settings so, for example, replay mode cannot leak in.
    env = {key: value for key, value in os.environ.items() if not key.startswith("COGAME_")}
    if llm:
        for key, value in os.environ.items():
            if key.startswith(("COGAME_LLM", "COGAME_ORACLE")):
                env[key] = value
    else:
        env["COGAME_LLM"] = "off"
    env.update({"COGAME_CONFIG_URI": (output / "config.json").as_uri(),
                "COGAME_PLAYER_SEATS_URI": (output / "player_seats.json").as_uri(),
                "COGAME_RESULTS_URI": (output / "results.json").as_uri(),
                "COGAME_SAVE_REPLAY_URI": (output / "replay.pwr").as_uri(),
                "COGAME_PLAYER_FAILURE_URI": (output / "player_failure.json").as_uri(),
                "COGAME_HOST": "127.0.0.1", "COGAME_PORT": "0"})
    with (output / "game.log").open("w") as log:
        process = subprocess.Popen([str(binary)], cwd=ROOT, env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + timeout
            while not (output / "results.json").exists() and not (output / "player_failure.json").exists():
                if process.poll() is not None:
                    raise RuntimeError(f"Host exited with code {process.returncode}; see {output / 'game.log'}")
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"Episode exceeded {timeout:g} seconds; see {output / 'game.log'}")
                time.sleep(0.02)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    if (output / "player_failure.json").exists():
        failure = json.loads((output / "player_failure.json").read_text())
        slot = failure["failed_policy_index"]
        print(f"Policy in slot {slot} failed to load; see {output / 'players' / str(slot) / 'log.txt'}",
              file=sys.stderr)
        return 2
    status = json.loads((output / "player_status.json").read_text())
    results = json.loads((output / "results.json").read_text())
    if len(results["scores"]) != len(policies) or not (output / "replay.pwr").stat().st_size:
        raise RuntimeError("Host produced incomplete episode artifacts")
    print(f"{results['winner_team']}: {results['west_kills']}-{results['east_kills']} "
          f"at tick {results['end_tick']} ({results['end_reason']})")
    failed = [seat["slot"] for seat in status["players"] if seat["exit_code"] != 0]
    if failed:
        print(f"Disabled BASIC seats: {failed}; inspect players/<slot>/log.txt", file=sys.stderr)
        return 3
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, epilog=(
        "Seats are assigned in order: first half West, second half East. "
        "Defaults: base:3 aggressive:3; duel 15,360 ticks/10 kills, other rosters 38,400 ticks/30 kills."))
    parser.add_argument("policies", nargs="*", metavar="POLICY[:COUNT]",
                        help="Bundled name or path to BASIC source or a neural ZIP package; paths resolve from your current directory")
    parser.add_argument("--list-policies", action="store_true")
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--ticks", type=int)
    parser.add_argument("--kill-goal", type=int)
    parser.add_argument("--output", type=Path, help="New or empty artifact directory; defaults to tmp/episodes/<unique>")
    parser.add_argument("--binary", type=Path, help="Use an existing pwleague binary instead of compiling")
    parser.add_argument("--nim", default=os.environ.get("NIM", "nim"), help="Nim compiler (default: NIM or nim on PATH)")
    parser.add_argument("--timeout", type=float, default=120, help="Episode wall-clock timeout in seconds")
    parser.add_argument("--llm", action="store_true", help="Enable host-configured LLM/Jev inference")
    parser.add_argument("--llm-mode", choices=("async", "barrier"), default="barrier",
                        help="Wait for concurrent inference requests between ticks (default: barrier)")
    args = parser.parse_args(argv)
    if args.list_policies:
        print("\n".join(POLICIES))
        return 0
    try:
        policies = expand_policies(args.policies or ["base:3", "aggressive:3"])
        ticks = args.ticks if args.ticks is not None else (15360 if len(policies) == 2 else 38400)
        goal = args.kill_goal if args.kill_goal is not None else (10 if len(policies) == 2 else 30)
        if not -(2**31) <= args.seed < 2**31 or not 1 <= ticks <= 40000 or not 1 <= goal <= 40:
            raise ValueError("Seed must fit int32, ticks must be 1–40,000 and kill goal 1–40")
        if not math.isfinite(args.timeout) or args.timeout <= 0:
            raise ValueError("Timeout must be positive and finite")
        binary = args.binary.expanduser().resolve() if args.binary else None
        if binary is not None and not binary.is_file():
            raise ValueError(f"League binary not found: {binary}")
        if args.output:
            output = args.output.expanduser().resolve()
            output.mkdir(parents=True, exist_ok=True)
            if any(output.iterdir()):
                raise ValueError(f"Output directory must be empty: {output}")
        else:
            parent = ROOT / "tmp/episodes"
            parent.mkdir(parents=True, exist_ok=True)
            output = Path(tempfile.mkdtemp(prefix="episode-", dir=parent))
        print(f"Artifacts: {output}", flush=True)
        nim = str(Path(args.nim).expanduser().resolve()) if "/" in args.nim else args.nim
        binary = binary or build_host(output, nim)
        return run_episode(policies, output, binary, args.seed, ticks, goal, args.timeout, args.llm, args.llm_mode)
    except (OSError, ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Episode interrupted; partial artifacts have been retained.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
