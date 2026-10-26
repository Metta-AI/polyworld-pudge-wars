"""Exercise the actual game-hosted process and runner artifact contract."""
import hashlib
import json
import os
import re
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
import zipfile
from urllib.request import urlopen
from urllib.error import HTTPError

ROOT = Path(__file__).resolve().parents[1]


class LeagueHostTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get("PUDGE_LEAGUE_BINARY", ROOT / "tmp/pwleague"))
        if not cls.binary.is_file():
            raise RuntimeError("Build pwleague first (see coworld/GAME_HOSTED_MIGRATION.md)")

    def check_global_socket(self, port):
        with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
            sock.sendall((f"GET /global HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
                          "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                          "Sec-WebSocket-Version: 13\r\n"
                          "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").encode())
            with sock.makefile("rb") as stream:
                self.assertIn(b"101", stream.readline())
                while stream.readline() != b"\r\n":
                    pass

                def frame():
                    first, second = stream.read(2)
                    length = second & 127
                    if length == 126:
                        length = int.from_bytes(stream.read(2), "big")
                    elif length == 127:
                        length = int.from_bytes(stream.read(8), "big")
                    return first & 15, stream.read(length)

                opcode, snapshot = frame()
                self.assertEqual(opcode, 1)
                self.assertIsInstance(json.loads(snapshot), dict)
                self.assertNotIn(b"PRIVATE_SENTINEL", snapshot)
                payload, mask = b"probe", b"abcd"
                masked = bytes(value ^ mask[i % 4] for i, value in enumerate(payload))
                sock.sendall(bytes([0x89, 0x80 | len(payload)]) + mask + masked)
                opcode, reply = frame()
                self.assertEqual((opcode, reply), (10, payload))

    def run_episode(self, sources, ticks=128, failure=False, replay_failure=False,
                    failed_slots=()):
        with tempfile.TemporaryDirectory(prefix="pudge-league-") as directory:
            root = Path(directory)
            seats = []
            for slot, source in enumerate(sources):
                player = root / str(slot)
                player.mkdir()
                data = source.encode()
                (player / "file").write_bytes(data)
                seats.append({"slot": slot, "file_uri": (player / "file").as_uri(),
                              "size_bytes": len(data),
                              "content_hash": "sha256:" + hashlib.sha256(data).hexdigest(),
                              "log_uri": (player / "log").as_uri(),
                              "annotations_uri": (player / "annotations.jsonl").as_uri()})
            config = {"tokens": [f"token-{i}" for i in range(len(sources))],
                      "players": [{"name": f"Seat {i}"} for i in range(len(sources))],
                      "seed": 7, "max_ticks": ticks, "kill_goal": 30, "fog": True}
            (root / "config").write_text(json.dumps(config))
            (root / "seats").write_text(json.dumps({"schema": "coworld-player-seats/2",
                "seats": seats, "player_status_uri": (root / "status").as_uri()}))
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            env = {**os.environ, "COGAME_CONFIG_URI": (root / "config").as_uri(),
                   "COGAME_PLAYER_SEATS_URI": (root / "seats").as_uri(),
                   "COGAME_RESULTS_URI": (root / "results").as_uri(),
                   "COGAME_SAVE_REPLAY_URI": (root / "replay").as_uri(),
                   "COGAME_PLAYER_FAILURE_URI": (root / "failure").as_uri(),
                   "COGAME_HOST": "127.0.0.1", "COGAME_PORT": str(port)}
            if replay_failure:
                (root / "blocked").write_text("not a directory")
                env["COGAME_SAVE_REPLAY_URI"] = (root / "blocked/replay").as_uri()
            with (root / "public.log").open("w") as public:
                process = subprocess.Popen([str(self.binary)], env=env, cwd=ROOT,
                                           stdout=public, stderr=public)
                try:
                    marker = root / ("failure" if failure else "results")
                    deadline = time.monotonic() + 90
                    while not marker.exists() and process.poll() is None:
                        if time.monotonic() >= deadline:
                            self.fail("Host did not complete within 90 seconds")
                        time.sleep(0.02)
                    if replay_failure:
                        self.assertFalse((root / "results").exists())
                        self.assertNotEqual(process.returncode, 0)
                        return
                    self.assertTrue(marker.exists(), (root / "public.log").read_text())
                    self.assertTrue((root / "status").exists())
                    status = json.loads((root / "status").read_text())
                    self.assertEqual([seat["slot"] for seat in status["players"]
                                      if seat["exit_code"] != 0], list(failed_slots))
                    for seat in seats:
                        self.assertTrue((root / str(seat["slot"]) / "log").is_file())
                    if failure:
                        self.assertEqual(json.loads(marker.read_text())["failed_policy_index"], 1)
                        self.assertFalse((root / "results").exists())
                    else:
                        result = json.loads(marker.read_text())
                        self.assertEqual(len(result["scores"]), len(sources))
                        self.assertGreater((root / "replay").stat().st_size, 0)
                        self.assertEqual((root / "replay").read_bytes()[:2], b"PO")
                    # Collection happens before process exit; viewers stay available.
                    for route in ["healthz", "client/global", "client/player"]:
                        with urlopen(f"http://127.0.0.1:{port}/{route}", timeout=5) as response:
                            self.assertEqual(response.status, 200)
                    self.check_global_socket(port)
                    for route in ["player", "ws"]:
                        with self.assertRaises(HTTPError) as error:
                            urlopen(f"http://127.0.0.1:{port}/{route}", timeout=5)
                        self.assertEqual(error.exception.code, 404)
                        error.exception.close()
                    process.terminate()
                    self.assertEqual(process.wait(timeout=5), 0)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()
            self.assertNotIn("PRIVATE_SENTINEL", (root / "public.log").read_text())

    def test_full_six_seat_episode(self):
        self.run_episode([(ROOT / f"coworld/players/{name}.bas").read_text()
                          for name in ["base", "aggressive", "sniper"] * 2], ticks=38400)

    def test_private_logs_and_disabled_runtime(self):
        self.run_episode(['print "PRIVATE_SENTINEL"', "while 1\nwend"], failed_slots=[1])

    def test_compile_failure(self):
        self.run_episode(["x = 1", "PRIVATE_SENTINEL invalid syntax"], failure=True,
                         failed_slots=[1])

    def test_replay_failure_does_not_publish_success(self):
        self.run_episode(["x = 1", "x = 2"], replay_failure=True)

    def test_bundled_players_match_local_sources(self):
        manifest = json.loads((ROOT / "coworld/coworld_manifest_template.json").read_text())
        for player in manifest["player"]:
            if player["id"] == "neural":
                with zipfile.ZipFile(ROOT / "coworld" / player["file"]) as archive:
                    self.assertEqual(archive.read("policy.bas"), (ROOT / "examples/pudge_wars/players/neural.bas").read_bytes())
                continue
            self.assertEqual((ROOT / "coworld" / player["file"]).read_bytes(),
                             (ROOT / "examples/pudge_wars" / player["file"]).read_bytes())

    def test_certified_viewer_matches_simulator_version(self):
        version = re.search(r"ReplayGameVersion\* = (\d+)'u16",
                            (ROOT / "examples/pudge_wars/replays.nim").read_text())
        self.assertEqual(version.group(1), "38",
                         "Rebuild and certify a viewer when the simulator version changes")
        for project in ["coworld", "coworld/platform-hosted"]:
            manifest = json.loads((ROOT / project / "coworld_manifest_template.json").read_text())
            self.assertEqual(manifest["game"]["replay_viewer"]["bundle"],
                             "sha256:5fb1947dbfb26bae7c5ebee8167d1d838ce1ef3e7e8a4c22dc76a50e1848c8c6")


if __name__ == "__main__":
    unittest.main()
