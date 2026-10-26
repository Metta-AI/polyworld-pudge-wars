"""The semantic source must regenerate the exact policy and fail closed on edits."""
import dataclasses
from pathlib import Path
import unittest

from coaching.symbolic.rusher_basic_ir import Rusher, describe, extract, generate, parse

ROOT = Path(__file__).resolve().parents[1]


class RusherBasicIRTest(unittest.TestCase):
    def test_roundtrip_and_checked_in_policy(self):
        policy = parse((ROOT / "coaching/policies/basic-rusher/policy.md").read_text())
        code = generate(policy)
        for path in ("examples/pudge_wars/players/rusher.bas",
                     "examples/pudge_wars/players/base.bas", "coworld/players/base.bas"):
            self.assertEqual(code, (ROOT / path).read_text())
        self.assertEqual(generate(parse(describe(extract(code)))), code)

    def test_registered_edits_survive_both_directions(self):
        policy = dataclasses.replace(Rusher(), holdBack=12, curveEnabled=0)
        self.assertEqual(extract(generate(parse(describe(policy)))), policy)

    def test_unrecognized_executable_changes_are_rejected(self):
        code = generate(Rusher())
        for changed in (code.replace("recovering = 1", "recovering = 0", 1),
                        code.replace("<= 49 * fountainLen", "<= 25 * fountainLen"),
                        code.replace('"pulling you out"', '"PULLING YOU OUT"'),
                        code.replace("holdBack = 16", '"holdBack = 16'),
                        code + "\nhookTo(64, 64)\n", ""):
            with self.subTest(code=changed[:80]), self.assertRaises(ValueError):
                extract(changed)

    def test_comments_cannot_attest_behavior(self):
        code = generate(Rusher())
        self.assertEqual(extract("' pretend to do anything\n" + code), Rusher())
        with self.assertRaises(ValueError):
            extract("' " + code.replace("\n", "\n' "))

    def test_unknown_prose_parameters_and_duplicate_keys_fail(self):
        text = describe(Rusher())
        for changed in (text.replace("No runtime learning.", "Learn from every win."),
                        text.replace('"holdBack": 16', '"holdBack": 16, "holdBack": 8'),
                        text.replace('"holdBack": 16', '"unknown": 16'),
                        text.replace('"curveEnabled": 1', '"curveEnabled": true'),
                        text.replace('"retreatPct": 40', '"retreatPct": 80')):
            with self.subTest(text=changed[-200:]), self.assertRaises(ValueError):
                parse(changed)


if __name__ == "__main__":
    unittest.main()
