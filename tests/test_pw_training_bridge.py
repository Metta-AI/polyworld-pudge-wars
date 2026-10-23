"""Keep the upstream training codec usable with the migrated BASIC opponents."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class TrainingBridgeTest(unittest.TestCase):
    def test_reset_codec_teacher_and_terminal_on_both_league_rosters(self):
        binary = Path(os.environ.get("PUDGE_TRAINING_BINARY", ROOT / "tmp/pwtraining"))
        for seats in [2, 6]:
            with self.subTest(seats=seats), subprocess.Popen(
                [sys.executable, str(ROOT / "coworld/player/training_bridge.py"),
                 str(binary), str(seats), "4"], cwd=ROOT, text=True,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            ) as bridge, selectors.DefaultSelector() as selector:
                selector.register(bridge.stdout, selectors.EVENT_READ)

                def exchange(request):
                    bridge.stdin.write(json.dumps(request) + "\n")
                    bridge.stdin.flush()
                    self.assertTrue(selector.select(10), "Training bridge did not respond")
                    line = bridge.stdout.readline()
                    self.assertTrue(line, "Training bridge exited early")
                    return json.loads(line)

                try:
                    initial = exchange({"kind": "reset", "players": 1, "seed": "migration"})
                    for tick in range(4):
                        codec = exchange({"kind": "encode"})
                        self.assertEqual(codec["decision_id"], tick)
                        self.assertEqual(len(codec["values"]), 191)
                        self.assertEqual(len(codec["action_heads"]), 7)
                        teacher = exchange({"kind": "teacher"})
                        action = json.loads(teacher["response"])
                        for head in codec["action_heads"]:
                            self.assertIn(action[head["name"]], head["choices"])
                        result = exchange({"kind": "step", "decision_id": tick,
                                           "response": teacher["response"]})
                        self.assertEqual(result["kind"], "accepted")
                    self.assertEqual(result["observation"]["kind"], "terminal")
                    self.assertEqual(exchange({"kind": "reset", "players": 1,
                                               "seed": "migration"}), initial)
                    bridge.stdin.close()
                    self.assertEqual(bridge.wait(timeout=5), 0)
                finally:
                    if bridge.poll() is None:
                        bridge.terminate()
                        bridge.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
