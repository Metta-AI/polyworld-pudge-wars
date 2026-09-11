import unittest
from coaching.symbolic.basic_coaching_ir import Lesson, parse, block, generate, extract


class CoachingProjectionTests(unittest.TestCase):
    def test_behavioral_roundtrip_across_supported_choices(self):
        for idle in ("hold", "probe_lane"):
            for hooks in (False, True):
                for radius in (6, 8, 12):
                    lesson = Lesson(melee_radius=radius, idle=idle, hook_during_melee=hooks)
                    self.assertEqual(parse(block(lesson)), lesson)
                    self.assertEqual(extract(generate(lesson)), lesson)

    def test_extraction_obeys_code_and_ignores_claims_in_comments(self):
        code = generate(Lesson()).replace("hookDuringMelee = 1", "hookDuringMelee = 0", 1)
        self.assertFalse(extract("' always hook during melee\n" + code).hook_during_melee)

    def test_unrecognized_executable_changes_fail_closed(self):
        code = generate(Lesson())
        for edited in (code.replace("attackTarget(objectId(best))", "halt()"),
                       code.replace("objectTeam(i) <> selfTeam", "objectTeam(i) = selfTeam"),
                       code + "rotToggle()\n"):
            with self.assertRaises(ValueError):
                extract(edited)

    def test_ambiguous_contracts_fail(self):
        for text in (block(Lesson()) * 2,
                     block(Lesson()).replace("idle = hold", "idle = chase_everything"),
                     block(Lesson()).replace("hook_during_melee = true", "hook_during_melee = yes")):
            with self.assertRaises(ValueError):
                parse(text)

    def test_movement_roundtrip_and_legacy_contract(self):
        for radius in (4, 10, 14):
            for timeout in (32, 128, 256):
                lesson = Lesson(idle="probe_lane", ranged_movement="patrol",
                                patrol_radius=radius, waypoint_timeout_ticks=timeout)
                self.assertEqual(extract(generate(parse(block(lesson)))), lesson)
        legacy = "\n".join(line for line in block(Lesson()).splitlines()
                           if not line.startswith(("ranged_movement", "patrol_radius", "waypoint_timeout_ticks", "preserve_pull")))
        self.assertEqual(parse(legacy), Lesson())

    def test_movement_extraction_rejects_semantic_drift(self):
        code = generate(Lesson(idle="probe_lane", ranged_movement="patrol"))
        for changed in (code.replace("walkTo(patrolX, patrolY)", "halt()"),
                        code.replace("if melee = 1 then", "if melee = 0 then"),
                        code.replace("worldTick >= patrolUntil", "worldTick < patrolUntil"),
                        code + "patrolRadius = 10\n"):
            with self.assertRaises(ValueError):
                extract(changed)

    def test_pull_commitment_roundtrip(self):
        lesson = Lesson(idle="probe_lane", ranged_movement="patrol", preserve_pull=True)
        code = generate(lesson)
        self.assertEqual(extract(code), lesson)
        with self.assertRaises(ValueError):
            extract(code.replace("objectHooked(best) = 1", "objectHooked(best) = 0"))


if __name__ == "__main__":
    unittest.main()
