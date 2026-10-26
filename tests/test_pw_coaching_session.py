# /// script
# requires-python = ">=3.12"
# dependencies = ["websockets==15.0.1"]
# ///
"""Real six-seat host: pause, resume, restart, stale replies and round archives.

Usage: uv run tests/test_pw_coaching_session.py PATH_TO_HOST OUTPUT_DIRECTORY
The recorded native frames can also be checked with test_pw_coaching_stream.nim.
"""
import asyncio
import json
import os
from pathlib import Path
import re
import socket
import struct
import sys

import websockets

ROOT = Path(__file__).resolve().parents[1]


def string(value):
    data = value.encode()
    return struct.pack("<q", len(data)) + data


def hello(token):
    protocol = int(re.search(r"NetProtocolVersion\* = (\d+)",
                            (ROOT / "examples/pudge_wars/netproto.nim").read_text())[1])
    source = (ROOT / "examples/pudge_wars/replays.nim").read_text()
    version = int(re.search(r"ReplayGameVersion\* = (\d+)", source)[1])
    game = re.search(r'ReplayGame\* = "([^"]+)"', source)[1]
    return (b"\x00" + struct.pack("<H", protocol) + string(game) + string("Coach")
            + string(token) + struct.pack("<iH", -1, version))


def control(command, round_id):
    return b"\x0b" + struct.pack("<qI", command, round_id)


def rot_intent(round_id):
    # Native IntentRot, deliberately claiming another slot: host must bind P1.
    return b"\x0d" + struct.pack("<iqiiII", 5, 15, 0, 0, 0, round_id)


async def until(predicate, timeout=8):
    async with asyncio.timeout(timeout):
        while not predicate():
            await asyncio.sleep(0.01)


async def run(host_path, output):
    output.mkdir(parents=True, exist_ok=False)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    config = output / "config.json"
    tokens = [f"coaching-test-{seat}" for seat in range(6)]
    config.write_text(json.dumps({
        "tokens": tokens, "players": [{"name": f"P{i + 1}"} for i in range(6)],
        "seed": 2026, "max_ticks": 96, "kill_goal": 30, "fog": True,
        "player_connect_timeout_seconds": 10, "coaching_seat": 0,
    }))
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("COGAME_", "COWORLD_PLAYER_"))}
    env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(port),
               COGAME_CONFIG_URI=config.as_uri(),
               COGAME_RESULTS_URI=(output / "results.json").as_uri(),
               COGAME_SAVE_REPLAY_URI=(output / "replay.pwr").as_uri(),
               PYTHONPATH=str(ROOT))
    processes, tasks, sockets, logs = [], [], [], []
    states, frames, observations = [], [], []
    try:
        log = (output / "host.log").open("w")
        logs.append(log)
        host = await asyncio.create_subprocess_exec(str(host_path), env=env, cwd=ROOT,
                                                   stdout=log, stderr=log)
        processes.append(host)
        async with asyncio.timeout(10):
            while True:
                try:
                    global_ws = await websockets.connect(f"ws://127.0.0.1:{port}/global")
                    break
                except OSError:
                    await asyncio.sleep(0.1)
        sockets.append(global_ws)

        async def collect(ws, target):
            async for raw in ws:
                target.append(raw if isinstance(raw, bytes) else json.loads(raw))

        tasks.append(asyncio.create_task(collect(global_ws, states)))
        native = await websockets.connect(f"ws://127.0.0.1:{port}/ws")
        sockets.append(native)
        tasks.append(asyncio.create_task(collect(native, frames)))
        await native.send(hello(tokens[0]))
        # P2 is a controllable JSON test seat; P3–P6 use the real coaching wrapper.
        ally = await websockets.connect(f"ws://127.0.0.1:{port}/player?token={tokens[1]}&slot=1")
        sockets.append(ally)
        tasks.append(asyncio.create_task(collect(ally, observations)))
        for seat in range(2, 6):
            log = (output / f"policy-{seat}.log").open("w")
            logs.append(log)
            bot = await asyncio.create_subprocess_exec(
                sys.executable, str(ROOT / "scripts/coaching_player.py"), cwd=ROOT,
                env=env | {"COWORLD_PLAYER_WS_URL": f"ws://127.0.0.1:{port}/player?token={tokens[seat]}&slot={seat}",
                           "PUDGE_POLICY_ARM": "combined", "PUDGE_PERSONALITY": "rusher"},
                stdout=log, stderr=log)
            processes.append(bot)
        await until(lambda: states and states[-1]["tick"] >= 8)
        assert any(frame[0] == 12 and struct.unpack("<??I", frame[1:]) == (True, False, 1)
                   for frame in frames), "coach capability missing"

        # A non-coach seat cannot stop the match, even if it sends binary control.
        await ally.send(control(0, 1))
        tick_before = states[-1]["tick"]
        await until(lambda: states[-1]["tick"] >= tick_before + 4)
        assert not states[-1]["paused"]
        await native.send(rot_intent(1))
        await until(lambda: states[-1]["pudges"][0]["rot"])
        await native.send(control(0, 1))
        await until(lambda: states[-1]["paused"])
        paused_tick = states[-1]["tick"]
        await asyncio.sleep(0.25)
        assert states[-1]["tick"] == paused_tick, "host advanced while paused"
        await native.send(control(1, 1))
        await until(lambda: states[-1]["tick"] >= paused_tick + 4)

        # Restart a paused round, keeping every socket and real policy alive.
        await native.send(control(0, 1))
        await until(lambda: states[-1]["paused"])
        await native.send(control(2, 1))
        await until(lambda: any(s["coaching_round"] == 2 and s["tick"] == 0 for s in states))
        fresh = next(s for s in states if s["coaching_round"] == 2 and s["tick"] == 0)
        assert fresh["score"] == {"west": 0, "east": 0}
        assert all(p["hp"] == 1200 and not p["rot"] for p in fresh["pudges"])
        first = json.loads((output / "rounds/round-001.json").read_text())
        assert first["end_reason"] == "restart" and first["coaching_round"] == 1
        await native.send(control(0, 1))  # delayed control from old round
        await native.send(rot_intent(1))  # delayed human intent from old round
        await ally.send(json.dumps({"rot": True, "coaching_round": 1}))
        await until(lambda: states[-1]["coaching_round"] == 2 and states[-1]["tick"] >= 8)
        assert not states[-1]["paused"]
        assert not states[-1]["pudges"][0]["rot"]
        assert not states[-1]["pudges"][1]["rot"]
        await ally.send(json.dumps({"rot": True, "coaching_round": 2}))
        await until(lambda: states[-1]["pudges"][1]["rot"])
        await until(lambda: states[-1]["done"] and states[-1]["coaching_round"] == 2)
        assert host.returncode is None, "coaching host exited at round end"
        assert all(p.returncode is None for p in processes[1:]), "policy exited between rounds"
        second = json.loads((output / "rounds/round-002.json").read_text())
        assert second["end_reason"] == "time_limit" and second["end_tick"] == 96
        assert (output / "rounds/round-001.pwr").read_bytes() != (output / "rounds/round-002.pwr").read_bytes()
        await native.send(control(2, 2))
        await until(lambda: states[-1]["coaching_round"] == 3 and states[-1]["tick"] >= 8)
        assert sum(frame[0] == 5 for frame in frames) == 3, "each round must rebuild the native follower"
        assert {o.get("coaching_round") for o in observations} >= {1, 2, 3}
        print("PASS: host pause/resume, seat authorization, live/end-of-round restart, stale replies, bot persistence, archives")
    finally:
        for ws in sockets:
            await ws.close()
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        for process in processes:
            if process.returncode is None:
                process.terminate()
        await asyncio.gather(*(process.wait() for process in processes))
        for log in logs:
            log.close()
        (output / "frames.hex").write_text("\n".join(frame.hex() for frame in frames) + "\n")
        (output / "states.json").write_text(json.dumps(states))


if __name__ == "__main__":
    asyncio.run(run(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()))
