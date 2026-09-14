#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["websockets==15.0.1"]
# ///
"""Play P1 beside the Coworld Python policy using the local native game."""

import argparse
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "duels" / "local-policy"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", default="Aaron")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--seconds", type=int, default=1200)
    parser.add_argument("--kill-goal", type=int, default=30)
    parser.add_argument("--opponent", choices=["baseline", "combined"], default="baseline")
    parser.add_argument("--quickcast", action="store_true", help="Cast at the cursor on Q press")
    parser.add_argument("--headless", action="store_true", help="Run all six seats as bots without a window")
    args = parser.parse_args()
    if args.seconds <= 0 or args.kill_goal <= 0:
        parser.error("--seconds and --kill-goal must be positive")

    BUILD.mkdir(parents=True, exist_ok=True)
    print("Building the local game (Nim reuses its compile cache)…", flush=True)
    subprocess.run([
        "nim", "c", "--threads:on", "-d:ssl", "-d:release", "--hints:off",
        f"-o:{BUILD / 'pwcoworld'}", "examples/pudge_wars/coworld_host.nim",
    ], cwd=ROOT, check=True)
    if not args.headless:
        subprocess.run([
            "nim", "c", "-d:release", "--hints:off", f"-o:{BUILD / 'pw'}",
            "examples/pudge_wars/pw.nim",
        ], cwd=ROOT, check=True)

    match = Path(tempfile.mkdtemp(prefix="match-", dir=BUILD))
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    tokens = [secrets.token_urlsafe(24) for _ in range(6)]
    ally_name = "Base v13"
    enemy_name = "Base v10" if args.opponent == "baseline" else ally_name
    names = [ally_name if args.headless else args.name, ally_name, ally_name] + [enemy_name] * 3
    config = match / "config.json"
    config.write_text(json.dumps({
        "tokens": tokens, "players": [{"name": name} for name in names],
        "seed": args.seed, "max_ticks": args.seconds * 32, "kill_goal": args.kill_goal,
        "fog": True, "player_connect_timeout_seconds": 180,
    }))
    # Local games never inherit remote artifact destinations or log shippers.
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("COGAME_", "COWORLD_PLAYER_"))}
    env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(port),
               COGAME_CONFIG_URI=config.as_uri(),
               COGAME_RESULTS_URI=(match / "results.json").as_uri(),
               COGAME_SAVE_REPLAY_URI=(match / "replay.pwr").as_uri())
    children = []

    def launch(command, child_env, label):
        with (match / f"{label}.log").open("w") as log:
            child = subprocess.Popen(command, cwd=ROOT, env=child_env,
                                     stdout=log, stderr=subprocess.STDOUT)
        children.append((label, child))
        return child

    print(f"Match logs and completed replay: {match}", flush=True)
    try:
        host = launch([str(BUILD / "pwcoworld")], env, "host")
        deadline = time.monotonic() + 20
        while True:
            if host.poll() is not None:
                raise RuntimeError(f"Host exited; see {match / 'host.log'}")
            try:
                with urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1):
                    break
            except (URLError, TimeoutError):
                if time.monotonic() >= deadline:
                    raise RuntimeError("Local host did not become ready within 20 seconds")
                time.sleep(0.1)

        bots = []
        for slot in range(0 if args.headless else 1, 6):
            player_env = env | {
                "PUDGE_PERSONALITY": "rusher",
                "PUDGE_POLICY_ARM": "combined" if slot < 3 else args.opponent,
                "COWORLD_PLAYER_WS_URL": f"ws://127.0.0.1:{port}/player?slot={slot}&token={tokens[slot]}",
            }
            bots.append(launch([sys.executable, "-m", "coworld.player.player"],
                               player_env, f"policy-P{slot + 1}"))

        client = None
        if not args.headless:
            command = [str(BUILD / "pw"), "--join", f"ws://127.0.0.1:{port}/ws",
                       "--token", tokens[0], "--name", args.name,
                       "--windowSize", "1280x1000"]
            if args.quickcast:
                command.append("--quickcast")
            client = launch(command, env, "client")
            print(f"You are P1 ({args.name}); P2–P3 are Base v13. P4–P6 are {enemy_name}.", flush=True)
            print("WASD/right-click move · Q then click hooks · E grapple · F blink · G ping", flush=True)
            print("Close the game window or press Ctrl-C to stop. Rerun this command for a new match.", flush=True)

        while host.poll() is None:
            if client is not None and client.poll() is not None:
                if client.returncode:
                    raise RuntimeError(f"Game window exited with {client.returncode}; see {match / 'client.log'}")
                return
            for bot in bots:
                if bot.poll() is not None and not (match / "results.json").exists():
                    raise RuntimeError(f"A policy stopped before the match finished; see {match}")
            time.sleep(0.1)
        if host.returncode:
            raise RuntimeError(f"Host exited with {host.returncode}; see {match / 'host.log'}")
        print(f"Match complete. Recording: {match / 'replay.pwr'}", flush=True)
    finally:
        # Only stop processes started by this invocation.
        for _, child in reversed(children):
            if child.poll() is None:
                child.terminate()
        for _, child in children:
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == "__main__":
    def stop_match(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, stop_match)
    if hasattr(signal, "SIGHUP"):
        signal.signal(signal.SIGHUP, stop_match)
    try:
        main()
    except KeyboardInterrupt:
        print("Local match stopped.")
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Local play failed: {error}", file=sys.stderr)
        sys.exit(1)
