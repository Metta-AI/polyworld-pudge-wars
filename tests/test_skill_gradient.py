from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from evaluate_skill_gradient import summarize


class SeedBlockTests(unittest.TestCase):
    def test_bank_advantage_cancels_within_seed(self):
        rows = [dict(seed=s, candidate_bank=b, margin=10 if b == 0 else -10,
                     end_reason="time_limit") for s in range(3) for b in (0, 1)]
        report = summarize(rows)
        self.assertEqual(report["seed_blocks"], 3)
        self.assertEqual(report["margin_seed_bootstrap_95"], [0, 0])
        self.assertEqual((report["wins"], report["losses"]), (3, 3))

    def test_partial_and_duplicate_blocks_rejected(self):
        row = dict(seed=1, candidate_bank=0, margin=1, end_reason="kill_goal")
        for rows in ([], [row], [row, row]):
            with self.assertRaises(ValueError):
                summarize(rows)


if __name__ == "__main__":
    unittest.main()
