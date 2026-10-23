"""Exercise packaged neural policies and the real Jev HTTP boundary locally."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]

TENSOR_POLICY = '''
dim shape(0)
dim obs(1)
if initialized = 0 then
  weights = tensorLoad("weights")
  shape(0) = 2
  inputs = tensorCreate("float32", shape)
  outputs = tensorCreate("float32", shape)
  state = tensorCreate("float32", shape)
  one = tensorScalar("float32", "1")
  initialized = 1
end if
obs(0) = selfTeam
obs(1) = 0.5
tensorImport(inputs, obs)
tensorDense(inputs, weights, 0, outputs)
tensorRelu(outputs, outputs)
tensorAdd(state, one, state)
answer = tensorExport(outputs)
steps = tensorExport(state)
print "NN ", answer(0), " ", answer(1), " ", steps(0)
walkTo(homeX, homeY)
'''

JEV_POLICY = '''
if request > 0 then
  status = oraclePoll(request)
  if status > 0 then
    print "JEV ", oracleAnswer(request, "mode")
    request = 0
  elseif status = -1 then
    print "JEV failed ", llmError$(request)
    request = 0
  end if
end if
if submitted = 0 and oracleReady() = 0 then
  oracleState("self.team", selfTeam)
  oracleQuestion("mode", 2, "Choose a posture.")
  oracleCriterion("mode", "hold", "Hold position.")
  oracleCriterion("mode", "push", "Advance.")
  request = oracleAsk()
  submitted = 1
end if
walkTo(homeX, homeY)
'''


class InferenceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get("PUDGE_LEAGUE_BINARY", ROOT / "tmp/pwleague")).resolve()

    def run_episode(self, directory, policies, *, llm=False, expected=0, env=None):
        output = directory / "episode"
        command = [sys.executable, str(ROOT / "scripts/run_episode.py"),
                   *map(str, policies), "--binary", str(self.binary), "--ticks", "4",
                   "--output", str(output)]
        if llm:
            command.append("--llm")
        with patch.dict(os.environ, env or {}):
            result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return output

    def package(self, path, source=TENSOR_POLICY, shape=(2, 2)):
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("scripts/policy.bas", source)
            archive.writestr("weights.bin", struct.pack("<4f", 2, 0, 0, 3))
            archive.writestr("tensors.json", json.dumps({"tensors": [
                {"name": "weights", "dtype": "float32", "shape": shape,
                 "resource": "weights.bin", "offset": 0}]}))

    def test_extensionless_zip_tensor_inference_and_private_persistent_state(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "extensionless"
            self.package(policy)
            output = self.run_episode(directory, [policy, policy])
            for slot in (0, 1):
                rows = [line.split() for line in (output / f"players/{slot}/log.txt").read_text().splitlines() if line.startswith("NN")]
                self.assertEqual([float(value) for value in rows[-1][1:]], [2 * slot, 1.5, 4])
            self.assertNotIn("NN", (output / "game.log").read_text())
            self.assertTrue((output / "replay.pwr").stat().st_size)

    def test_package_and_tensor_failures_are_attributed(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "bad.zip"
            with zipfile.ZipFile(policy, "w") as archive:
                archive.writestr("../escape.bas", "print 1")
            output = self.run_episode(directory, [policy, "base"], expected=2)
            self.assertEqual(json.loads((output / "player_failure.json").read_text())["failed_policy_index"], 0)
            self.assertFalse((directory.parent / "escape.bas").exists())
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "shape.zip"
            self.package(policy, shape=(1, 4))
            output = self.run_episode(directory, [policy, "base"], expected=3)
            status = json.loads((output / "player_status.json").read_text())["players"]
            self.assertEqual([x["exit_code"] for x in status], [1, 0])

    def test_native_memory_limit(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "large.bas"
            policy.write_text('dim shape(0)\nshape(0) = 4194304\na = tensorCreate("float32", shape)\nb = tensorCreate("float32", shape)\nc = tensorCreate("float32", shape)\n')
            output = self.run_episode(directory, [policy, "base"], expected=3)
            self.assertIn("memory", (output / "players/0/log.txt").read_text().lower())

    def mock_jev(self, *, bad=False, delay=0):
        received = []
        barrier = threading.Barrier(2)

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                slot = int(self.headers["X-Coworld-Player-Slot"])
                received.append((slot, self.path, body, self.headers.get("Authorization")))
                barrier.wait(timeout=5)
                time.sleep(delay)
                response = {} if bad else {"answers": {"mode": {"choice": "push" if slot else "hold"}}}
                data = json.dumps(response).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return {"COWORLD_LLM_ENDPOINT": f"http://127.0.0.1:{server.server_port}",
                "COGAME_LLM_TIMEOUT_MS": "7000"}, received

    def test_jev_parallel_barrier_slot_accounting_and_private_answers(self):
        env, received = self.mock_jev()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "jev.bas"
            policy.write_text(JEV_POLICY)
            output = self.run_episode(directory, [policy, policy], llm=True, env=env)
            self.assertEqual(len(received), 2)
            for slot, path, body, authorization in received:
                self.assertEqual(path, "/v1/systemone")
                self.assertEqual(body["state"]["self"]["team"], slot)
                self.assertEqual(body["model"], "typesafe/jev-1.13")
                self.assertIsNone(authorization)
                self.assertIn(f"JEV {slot}", " ".join((output / f"players/{slot}/log.txt").read_text().split()))
            self.assertNotIn("JEV", (output / "game.log").read_text())

    def test_jev_bad_response_settles_and_local_calls_require_opt_in(self):
        env, received = self.mock_jev(bad=True)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "jev.bas"
            policy.write_text(JEV_POLICY)
            output = self.run_episode(directory, [policy, policy], llm=True, env=env)
            self.assertEqual(len(received), 2)
            self.assertIn("JEV failed", (output / "players/0/log.txt").read_text())
        received.clear()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "disabled.bas"
            policy.write_text('print llmAvailable()\n' + JEV_POLICY)
            output = self.run_episode(directory, [policy, policy], env=env)
            self.assertEqual(received, [])
            self.assertIn("\n0\n", (output / "players/0/log.txt").read_text())

    def test_jev_timeout_releases_barrier(self):
        env, received = self.mock_jev(delay=0.15)
        env["COGAME_LLM_TIMEOUT_MS"] = "50"
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            policy = directory / "timeout.bas"
            policy.write_text(JEV_POLICY)
            output = self.run_episode(directory, [policy, policy], llm=True, env=env)
            self.assertEqual(len(received), 2)
            self.assertIn("timed out", (output / "players/0/log.txt").read_text())


if __name__ == "__main__":
    unittest.main()
