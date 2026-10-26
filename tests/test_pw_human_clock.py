"""Real hosted clock test. Run with PUDGE_HOST_BINARY pointing at coworld_host."""
import asyncio
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import tempfile
import time

from websockets.asyncio.client import connect

ROOT = Path(__file__).resolve().parents[1]


def hello(token):
    protocol = int(re.search(r"NetProtocolVersion\* = (\d+)",
                            (ROOT / "examples/pudge_wars/netproto.nim").read_text())[1])
    replay = (ROOT / "examples/pudge_wars/replays.nim").read_text()
    version = int(re.search(r"ReplayGameVersion\* = (\d+)", replay)[1])
    game = re.search(r'ReplayGame\* = "([^"]+)"', replay)[1]

    def string(value):
        data = value.encode()
        return struct.pack("<q", len(data)) + data

    return (b"\x00" + struct.pack("<H", protocol) + string(game) + string("Clock test")
            + string(token) + struct.pack("<iH", -1, version))


async def measure(viewer, expected_rate):
    # Closing a peer can leave already-received snapshots queued. Measuring
    # dequeue speed would falsely report hundreds of thousands of ticks/s.
    while True:
        try:
            await asyncio.wait_for(viewer.recv(), 0.02)
        except asyncio.TimeoutError:
            break
    # Global frames arrive every four ticks. Use only frames after transition.
    while True:
        state = json.loads(await asyncio.wait_for(viewer.recv(), 3))
        if state["started"] and state["wall_tick_rate"] == expected_rate:
            break
    # Skip a frame to avoid measuring a partial clock interval at transition.
    first = json.loads(await asyncio.wait_for(viewer.recv(), 3))
    start = time.monotonic()
    while True:
        state = json.loads(await asyncio.wait_for(viewer.recv(), 3))
        assert state["wall_tick_rate"] == expected_rate
        if state["tick"] - first["tick"] >= 32:
            break
    actual = (state["tick"] - first["tick"]) / (time.monotonic() - start)
    assert expected_rate * 0.8 < actual < expected_rate * 1.2, (expected_rate, actual)
    print(f"Expected {expected_rate} ticks/s; measured {actual:.2f}", flush=True)


async def check_clock(port):
    base = f"ws://127.0.0.1:{port}"
    # Idle policies intentionally send nothing, but must still accept reads
    # so this test does not introduce socket backpressure or slow close waits.
    options = dict(max_size=None, max_queue=None, close_timeout=0.2)
    async with connect(base + "/global", **options) as viewer:
        async with (
            connect(base + "/player?slot=0&token=seat0", **options),
            connect(base + "/player?slot=1&token=seat1", **options),
            connect(base + "/ws", **options) as spectator,
        ):
            await spectator.send(hello(""))
            # JSON policy seats and a spectator do not enable human pacing.
            await measure(viewer, 32)
            async with connect(base + "/ws", **options) as human:
                await human.send(hello("seat0"))
                await measure(viewer, 28)
                # The existing spectator receives the pace transition too.
                while True:
                    frame = await asyncio.wait_for(spectator.recv(), 3)
                    if isinstance(frame, bytes) and frame[0] == 3 and frame[-1] == 1:
                        break
            # Dropping the only human must not accelerate the match.
            await measure(viewer, 28)
            async with connect(base + "/ws", **options) as human:
                await human.send(hello("seat0"))
                while True:
                    frame = await asyncio.wait_for(human.recv(), 3)
                    if isinstance(frame, bytes) and frame[0] == 5:
                        assert frame[-1] == 1, "reconnect Start lost human pace"
                        break


async def bounded_check(port):
    async with asyncio.timeout(20):
        await check_clock(port)


def main():
    with tempfile.TemporaryDirectory(prefix="pudge-clock-") as directory:
        root = Path(directory)
        config = root / "config.json"
        config.write_text(json.dumps({
            "tokens": ["seat0", "seat1"], "players": [{"name": "A"}, {"name": "B"}],
            "max_ticks": 1000, "tick_rate": 32, "kill_goal": 30, "seed": 7,
            "player_connect_timeout_seconds": 15,
        }))
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        env = {k: v for k, v in os.environ.items() if not k.startswith("COGAME_")}
        env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(port),
                   COGAME_CONFIG_URI=config.as_uri(),
                   COGAME_RESULTS_URI=(root / "results.json").as_uri(),
                   COGAME_SAVE_REPLAY_URI=(root / "replay.pwr").as_uri())
        with (root / "host.log").open("w") as log:
            process = subprocess.Popen([os.environ["PUDGE_HOST_BINARY"]], cwd=ROOT,
                                       env=env, stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    with socket.socket() as probe:
                        if probe.connect_ex(("127.0.0.1", port)) == 0:
                            break
                    assert process.poll() is None, (root / "host.log").read_text()
                    assert time.monotonic() < deadline, "host never listened"
                    time.sleep(0.05)
                asyncio.run(bounded_check(port))
            finally:
                process.terminate()
                process.wait(timeout=5)


if __name__ == "__main__":
    main()
