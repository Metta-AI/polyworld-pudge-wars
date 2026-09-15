"""Run with PUDGE_HOST_BINARY pointing at a compiled coworld_host."""

import asyncio
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

from websockets.asyncio.client import connect


async def check_startup(port: int) -> None:
    async with connect(f"ws://127.0.0.1:{port}/global") as viewer:
        waiting = json.loads(await asyncio.wait_for(viewer.recv(), 3))
        assert waiting["started"] is False
        assert waiting["tick"] == 0
        async with (
            connect(f"ws://127.0.0.1:{port}/player?slot=0&token=human") as human,
            connect(f"ws://127.0.0.1:{port}/player?slot=1&token=bot"),
        ):
            await asyncio.wait_for(human.recv(), 3)
            running = json.loads(await asyncio.wait_for(viewer.recv(), 3))
            assert running["started"] is True
            advancing = json.loads(await asyncio.wait_for(viewer.recv(), 3))
            assert advancing["tick"] > running["tick"]
    print("Global viewer is ready before humans join; match advances after both seats connect.")


with tempfile.TemporaryDirectory(prefix="pudge-startup-") as directory:
    root = Path(directory)
    config = root / "config.json"
    config.write_text(json.dumps({
        "tokens": ["human", "bot"],
        "players": [{"name": "Human"}, {"name": "Bot"}],
        "max_ticks": 320,
        "tick_rate": 32,
        "kill_goal": 30,
        "player_connect_timeout_seconds": 180,
    }))
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    env = {
        **os.environ,
        "COGAME_HOST": "127.0.0.1",
        "COGAME_PORT": str(port),
        "COGAME_CONFIG_URI": config.as_uri(),
        "COGAME_RESULTS_URI": (root / "results.json").as_uri(),
        "COGAME_SAVE_REPLAY_URI": (root / "replay.pwr").as_uri(),
    }
    process = subprocess.Popen([os.environ["PUDGE_HOST_BINARY"]], env=env)
    try:
        deadline = time.monotonic() + 10
        while True:
            with socket.socket() as probe:
                if probe.connect_ex(("127.0.0.1", port)) == 0:
                    break
            assert process.poll() is None, "host exited during startup"
            assert time.monotonic() < deadline, "host never listened"
            time.sleep(0.05)
        asyncio.run(check_startup(port))
    finally:
        process.terminate()
        process.wait(timeout=5)
