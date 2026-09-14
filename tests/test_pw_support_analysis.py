"""Protect experiment conclusions from confusing intent with effective healing."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('support_inspection', Path(__file__).resolve().parents[1] / 'games/pudge-wars/instruments/inspect_matches.py')
inspection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspection)
comparison_spec = importlib.util.spec_from_file_location('campaign_comparison', Path(__file__).resolve().parents[1] / 'games/pudge-wars/instruments/compare_campaign.py')
comparison = importlib.util.module_from_spec(comparison_spec)
comparison_spec.loader.exec_module(comparison)


class EffectiveHealingTest(unittest.TestCase):
    def test_only_matching_launched_hook_can_confirm_a_deliberate_heal(self):
        summary = {'players': [{'id': 22, 'team': 'east'}, {'id': 19, 'team': 'east'}, {'id': 5, 'team': 'west'}, {'id': 11, 'team': 'west'}]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            events = root / 'events.jsonl'
            events.write_text('\n'.join(json.dumps(e) for e in [
                dict(ev='hook_launched', t=64, id=22, hookId=100, aim=[32.5, 56.5]),
                dict(ev='hook_launched', t=65, id=22, hookId=101, aim=[90, 40]),
                dict(ev='hook_launched', t=150, id=22, hookId=102, aim=[32.5, 56.5]),
            ]))
            log_text = 'policy_trace ' + json.dumps([
                dict(event='heal_request', tick=60, healer=22, recipient=19, at=[32.5, 56.5]),
            ])
            (root / 'policy-slot-3.log').write_text(repr(log_text.encode()))
            log = 'HEAL_TRACE_V1\nHEAL 80 22 19 500 620 100\nHEAL 85 22 19 620 620 101\nHEAL 170 22 19 620 740 102\nHEAL 80 11 5 700 800 99\n'
            result = inspection.healing_metrics(summary, events, log, root)
            self.assertEqual(result['teams'][1]['contacts'], 3)
            self.assertEqual(result['teams'][1]['restored_hp'], 240)
            self.assertEqual(result['teams'][1]['deliberate_contacts'], 1)
            self.assertEqual(result['teams'][1]['deliberate_hp'], 120)
            self.assertEqual(result['teams'][1]['zero_hp_contacts'], 1)
            self.assertEqual(result['teams'][0]['restored_hp'], 100)
            self.assertNotIn('deliberate_contacts', result['teams'][0])

    def test_missing_instrumentation_is_not_zero_healing(self):
        with self.assertRaisesRegex(ValueError, 'HEAL_TRACE_V1'):
            inspection.healing_metrics({}, Path('unused'), '', Path('unused'))


class CampaignComparisonTest(unittest.TestCase):
    def test_exact_test_matches_known_table_and_is_symmetric(self):
        expected = 0.0027594561852200836
        self.assertAlmostEqual(comparison.fisher_exact(1, 9, 11, 3), expected)
        self.assertAlmostEqual(comparison.fisher_exact(11, 3, 1, 9), expected)
        self.assertEqual(comparison.fisher_exact(10, 10, 10, 10), 1.0)

    def test_intervals_handle_no_wins_or_no_losses(self):
        low, high = comparison.wilson(0, 20)
        self.assertAlmostEqual(low, 0)
        self.assertGreater(high, 0.15)
        low_full, high_full = comparison.wilson(20, 20)
        self.assertAlmostEqual(low_full, 1 - high)
        self.assertAlmostEqual(high_full, 1)

    def test_incomplete_or_failed_campaign_cannot_produce_a_verdict(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            row = dict(label='candidate-west', policy='a', opponent='b', n=3,
                       num_episodes=10, status='running', counts={'completed': 9, 'running': 1})
            (root / 'status.json').write_text(json.dumps([row]))
            with self.assertRaisesRegex(ValueError, 'Incomplete or failed'):
                comparison.summarize(root, 'candidate-')

    def test_seed_deduplication_is_outcome_independent_and_explicit(self):
        rows = [dict(episode_id='z', candidate_side=0, result=dict(seed=7, scores=[1])),
                dict(episode_id='a', candidate_side=0, result=dict(seed=7, scores=[0])),
                dict(episode_id='b', candidate_side=1, result=dict(seed=8, scores=[1]))]
        with self.assertRaisesRegex(ValueError, 'Repeated seed'):
            comparison.independent_rows(rows, 'reject')
        chosen, excluded = comparison.independent_rows(rows, 'first-id')
        self.assertEqual([r['episode_id'] for r in chosen], ['a', 'b'])
        self.assertEqual(excluded, [dict(episode_id='z', seed=7, candidate_side=0)])
        self.assertEqual(comparison.independent_rows(list(reversed(rows)), 'first-id'), (chosen, excluded))


if __name__ == '__main__':
    unittest.main()
