"""End-to-end coverage for the public local BASIC episode command."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/run_episode.py"
POLICIES = ("base", "aggressive", "challenger", "denier", "patient", "sniper", "support")


class LocalEpisodeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = Path(os.environ.get("PUDGE_LEAGUE_BINARY", ROOT / "tmp/pwleague")).resolve()
        if not cls.binary.is_file():
            raise RuntimeError("Build tmp/pwleague first with scripts/test_league.sh")

    def run_local(self, output, *arguments, expected=0, cwd=ROOT):
        result = subprocess.run([sys.executable, str(RUNNER), "--binary", str(self.binary),
                                 "--output", str(output), *arguments], cwd=cwd,
                                capture_output=True, text=True, timeout=120)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_every_bundled_policy_completes_duels_on_both_banks(self):
        with tempfile.TemporaryDirectory(prefix="pudge-policy-matrix-") as directory:
            for policy in POLICIES:
                for reverse in (False, True):
                    with self.subTest(policy=policy, reverse=reverse):
                        output = Path(directory) / f"{policy}-{reverse}"
                        roster = ["base", policy] if reverse else [policy, "base"]
                        self.run_local(output, *roster, "--seed", "29" if reverse else "7")
                        results = json.loads((output / "results.json").read_text())
                        self.assertEqual(len(results["scores"]), 2)
                        self.assertTrue(results["end_tick"] == 15360 or results["end_reason"] == "kill_goal")
                        status = json.loads((output / "player_status.json").read_text())
                        self.assertTrue(all(seat["exit_code"] == 0 for seat in status["players"]))

    def test_mixed_rosters_and_repeated_policy_counts(self):
        with tempfile.TemporaryDirectory(prefix="pudge-mixed-rosters-") as directory:
            rosters = [["support:2", "sniper:2"],
                       ["base", "support", "patient", "aggressive", "denier", "challenger"],
                       ["support:4", "denier:4"],
                       ["base", "support", "patient", "sniper", "denier",
                        "aggressive", "challenger", "sniper", "support", "base"]]
            for number, roster in enumerate(rosters):
                with self.subTest(roster=roster):
                    output = Path(directory) / str(number)
                    self.run_local(output, *roster)
                    episode = json.loads((output / "episode.json").read_text())
                    seats = episode["policies"]
                    self.assertEqual(len(seats), (number + 2) * 2)
                    self.assertEqual([seat["team"] for seat in seats],
                                     ["west"] * (len(seats) // 2) + ["east"] * (len(seats) // 2))
                    self.assertGreater((output / "replay.pwr").stat().st_size, 0)

    def test_custom_relative_path_strings_annotations_and_determinism(self):
        with tempfile.TemporaryDirectory(prefix="pudge custom-") as directory:
            root = Path(directory)
            source = ('counter = counter + 1\nprint "PRIVATE_CUSTOM_"; counter\n'
                      'ANNOTATE(worldTick, "decision", "custom", "{}")\nwalkTo(homeX, homeY)\n')
            (root / "my policy.bas").write_text(source)
            results, replays = [], []
            for name in ("first", "second"):
                output = root / name
                self.run_local(output, "my policy.bas", "aggressive", "--ticks", "128", cwd=root)
                self.assertEqual((output / "players/0/file").read_text(), source)
                self.assertIn("PRIVATE_CUSTOM_128", (output / "players/0/log.txt").read_text())
                self.assertNotIn("PRIVATE_CUSTOM", (output / "game.log").read_text())
                self.assertEqual(len((output / "players/0/annotations.jsonl").read_text().splitlines()), 128)
                results.append((output / "results.json").read_bytes())
                replays.append((output / "replay.pwr").read_bytes())
            self.assertEqual(results[0], results[1])
            self.assertEqual(replays[0], replays[1])

    def test_compile_and_runtime_errors_have_distinct_exit_codes(self):
        with tempfile.TemporaryDirectory(prefix="pudge-policy-errors-") as directory:
            root = Path(directory)
            for name, source, code in [("syntax", "this is not BASIC", 2),
                                       ("budget", "while 1\nwend", 3),
                                       ("fractional", "hookTo(1.5, 2)", 3)]:
                with self.subTest(name=name):
                    path = root / f"{name}.bas"
                    path.write_text(source)
                    output = root / name
                    self.run_local(output, str(path), "base", "--ticks", "16", expected=code)
                    self.assertIn("BASIC", (output / "players/0/log.txt").read_text())
                    self.assertEqual((output / "results.json").exists(), code == 3)

    def test_invalid_rosters_and_existing_outputs_are_rejected(self):
        with tempfile.TemporaryDirectory(prefix="pudge-invalid-roster-") as directory:
            root = Path(directory)
            for roster in [("base",), ("base:0", "aggressive"), ("missing.bas", "base")]:
                self.run_local(root / "absent", *roster, expected=1)
                self.assertFalse((root / "absent").exists())
            output = root / "existing"
            output.mkdir()
            (output / "keep.txt").write_text("keep me")
            self.run_local(output, "base:2", expected=1)
            self.assertEqual((output / "keep.txt").read_text(), "keep me")

    def test_default_roster_and_episode_timeout(self):
        with tempfile.TemporaryDirectory(prefix="pudge-default-episode-") as directory:
            root = Path(directory)
            output = root / "default"
            self.run_local(output, "--ticks", "16")
            self.assertEqual(len(json.loads((output / "results.json").read_text())["scores"]), 6)
            timed_out = root / "timeout"
            result = self.run_local(timed_out, "base:3", "aggressive:3", "--timeout", "0.01", expected=1)
            self.assertIn("exceeded", result.stderr)
            self.assertFalse((timed_out / "results.json").exists())


if __name__ == "__main__":
    unittest.main()
