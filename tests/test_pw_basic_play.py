"""Run a real mixed human/BASIC match, including reconnect and seat isolation."""
import asyncio
import hashlib
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time

from websockets.asyncio.client import connect

from test_pw_human_clock import hello, measure

ROOT = Path(__file__).resolve().parents[1]


async def receive_kind(peer, kind):
    while True:
        frame = await asyncio.wait_for(peer.recv(), 5)
        if isinstance(frame, bytes) and frame[0] == kind:
            return frame


async def join(peer, slot):
    await peer.send(hello(f"seat{slot}"))
    grant = await receive_kind(peer, 4)
    assert struct.unpack_from("<i", grant, 1)[0] == slot


async def play(port):
    base = f"ws://127.0.0.1:{port}"
    options = dict(max_size=None, max_queue=None, close_timeout=0.2)
    async with connect(base + "/global", **options) as viewer:
        state = json.loads(await viewer.recv())
        assert not state["started"]
        async with connect(base + "/ws", **options) as first:
            await join(first, 0)
            # A token belonging to BASIC can never replace that policy with a human.
            async with connect(base + "/ws", **options) as spectator:
                await spectator.send(hello("seat1"))
                grant = await receive_kind(spectator, 4)
                assert struct.unpack_from("<i", grant, 1)[0] == -1
                lobby = await receive_kind(first, 3)
                assert lobby[-2:] == b"\x00\x01", "must wait for the second human"
                async with connect(base + "/ws", **options) as second:
                    await join(second, 2)
                    start = await receive_kind(first, 5)
                    assert start[-1] == 1
                    # Rot intent carries a spoofed policy slot. The host must
                    # apply and acknowledge it only for this connection's human.
                    await first.send(b"\x02" + struct.pack("<iqiiI", 3, 15, 0, 0, 0))
                    result = await receive_kind(first, 7)
                    assert struct.unpack_from("<iq?", result, 1) == (0, 15, True)
                    await measure(viewer, 28)
                # Disconnecting a human keeps the clock and policy seats intact.
                await measure(viewer, 28)
                async with connect(base + "/ws", **options) as reconnected:
                    await join(reconnected, 2)
                    assert (await receive_kind(reconnected, 5))[-1] == 1
                    assert len(await receive_kind(reconnected, 6)) > 1, "missing replay backlog"
                    await receive_kind(first, 8)  # Clean final Bye after the final ticks.


def main():
    with tempfile.TemporaryDirectory(prefix="pudge-basic-play-") as directory:
        root = Path(directory)
        seats = []
        downloads = []
        for slot in range(6):
            if slot in (0, 2):
                seats.append({"slot": slot, "kind": "human"})
                downloads.append(None)
                continue
            path = root / f"policy-{slot}.bas"
            # Actual league policies, with private output to check log isolation.
            source = (ROOT / "coworld/players/base.bas").read_bytes()
            path.write_bytes(b'print "PRIVATE_PLAY_SENTINEL"\n' + source)
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
            seats.append({"slot": slot, "kind": "policy", "file_uri": path.as_uri(),
                          "size_bytes": path.stat().st_size, "content_hash": "sha256:" + digest,
                          "log_uri": (root / f"log-{slot}").as_uri()})
            downloads.append({"url": path.as_uri(), "size_bytes": path.stat().st_size,
                              "content_hash": digest})
        roster = root / "seats.json"
        status = root / "player_status.json"
        roster.write_text(json.dumps({"schema": "coworld-play-seats/1", "seats": seats,
                                      "player_status_uri": status.as_uri()}))
        # Optional cross-repo proof uses the exact platform staging entrypoint.
        if stager := os.environ.get("PUDGE_PLAY_STAGER"):
            staging = root / "downloads.json"
            valid_hash = downloads[1]["content_hash"]
            downloads[1]["content_hash"] = "0" * 64
            staging.write_text(json.dumps({"seats": downloads}))
            rejected = subprocess.run(
                ["python3", stager, str(staging), str(root / "players"), str(root)],
                capture_output=True,
            )
            assert rejected.returncode != 0
            assert not (root / "players/seats.json").exists(), "published an unverified roster"
            downloads[1]["content_hash"] = valid_hash
            staging.write_text(json.dumps({"seats": downloads}))
            subprocess.run(["python3", stager, str(staging), str(root / "players"), str(root)], check=True)
            roster = root / "players/seats.json"
        config = root / "config.json"
        config.write_text(json.dumps({
            "tokens": [f"seat{i}" for i in range(6)],
            "players": [{"name": f"Seat {i}"} for i in range(6)],
            "seed": 7, "max_ticks": 256, "kill_goal": 30,
            "player_connect_timeout_seconds": 15,
        }))
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        env = {k: v for k, v in os.environ.items() if not k.startswith("COGAME_")}
        env.update(COGAME_HOST="127.0.0.1", COGAME_PORT=str(port),
                   COGAME_PLAY_SESSION_ID="mixed-play-test", COGAME_CONFIG_URI=config.as_uri(),
                   COGAME_PLAYER_SEATS_URI=roster.as_uri(),
                   COGAME_RESULTS_URI=(root / "results.json").as_uri(),
                   COGAME_SAVE_REPLAY_URI=(root / "replay").as_uri(),
                   COGAME_PLAYER_FAILURE_URI=(root / "failure.json").as_uri())
        with (root / "public.log").open("w") as log:
            process = subprocess.Popen([os.environ["PUDGE_LEAGUE_BINARY"]], env=env, cwd=ROOT,
                                       stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while True:
                    with socket.socket() as probe:
                        if probe.connect_ex(("127.0.0.1", port)) == 0:
                            break
                    assert process.poll() is None, (root / "public.log").read_text()
                    assert time.monotonic() < deadline, "host never listened"
                    time.sleep(0.05)
                asyncio.run(play(port))
                assert process.wait(timeout=10) == 0, (root / "public.log").read_text()
                assert len(json.loads((root / "results.json").read_text())["scores"]) == 6
                assert (root / "replay").read_bytes()[:2] == b"PO"
                assert not (root / "failure.json").exists()
                states = json.loads(status.read_text())["players"]
                assert [seat["slot"] for seat in states] == [1, 3, 4, 5]
                assert all(seat["exit_code"] == 0 for seat in states)
                assert "PRIVATE_PLAY_SENTINEL" not in (root / "public.log").read_text()
                print("Mixed BASIC play, human joins, reconnect, seat isolation, pacing and artifacts passed")
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)


if __name__ == "__main__":
    main()
