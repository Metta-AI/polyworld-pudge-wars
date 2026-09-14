"""Research validity and recovery checks, including actual native transport."""
from dataclasses import replace
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

from coaching.symbolic.campaign import exclusive, reserve, select_candidate
from coaching.symbolic.evaluate import play_cached, prepare
from coaching.symbolic.ir import parse, render, Step
from coaching.symbolic.search import check_proposal, compare, fingerprint, promotion, propose


ROOT = Path(__file__).resolve().parents[1]


def parent():
    return parse((ROOT / 'coaching/policies/executable/support.policy.md').read_text())


def paired_rows(seeds=6, gains=None):
    gains = gains or {'base': 3}
    return [dict(arm=arm, seed=seed, opponent=opponent, side=side,
                 margin=2 if arm == 'parent' else 2 + gain)
            for seed in range(seeds) for opponent, gain in gains.items()
            for side in (0, 1) for arm in ('parent', 'candidate')]


class ResearchValidity(unittest.TestCase):
    def test_selection_survives_sorted_json_checkpoints_and_keeps_parent_on_ties(self):
        evidence = {'z_change': {'mean_margin_difference': 0}, 'a_change': {'mean_margin_difference': 0}}
        self.assertEqual(select_candidate(json.loads(json.dumps(evidence, sort_keys=True))), 'parent')
        for values in (evidence, dict(reversed(list(evidence.items())))):
            for row in values.values():row['mean_margin_difference'] = 3
            self.assertEqual(select_candidate(values), 'a_change')

    def test_semantic_identity_ignores_names_defaults_and_equivalent_guards(self):
        original = parent()
        changed = replace(original, name='renamed', steps=tuple(
            Step('TRY', s.skill, s.arguments) if s.mode == 'STOP IF' else
            replace(s, arguments=()) if s.skill == 'aimed_shot' else s for s in original.steps))
        self.assertEqual(fingerprint(original), fingerprint(changed))

    def test_history_moves_search_past_both_previously_tried_leads(self):
        original = parent()
        first = propose(original, set(), 2)
        self.assertEqual([p.name for p in first], ['shorter_lead', 'longer_lead'])
        attempted = {(fingerprint(original), fingerprint(p.program)) for p in first}
        next_round = propose(original, attempted, 2)
        self.assertEqual([p.name for p in next_round], ['wider_lanes', 'withhold_fog_shots'])
        # Renaming the controller cannot evade failed-experiment memory.
        renamed = replace(original, name='different_label')
        self.assertEqual([p.name for p in propose(renamed, attempted, 2)], [p.name for p in next_round])

    def test_every_builtin_change_meets_its_independent_semantic_prediction(self):
        original = parent()
        for proposal in propose(original, set(), 10):
            self.assertTrue(check_proposal(original, proposal)['passed'])

    def test_roundtrip_identity_alone_does_not_pass_a_false_semantic_prediction(self):
        original = parent()
        claim = next(p for p in propose(original, set(), 10) if p.name == 'wider_lanes')
        with self.assertRaisesRegex(ValueError, 'spread farther'):
            check_proposal(original, replace(claim, program=original))

    def test_used_and_reserved_seeds_survive_restart_without_reallocation(self):
        state = dict(id='reproducible-test', seed_counter=0, seed_ledger={'6101': 'imported-development'})
        audit = reserve(state, 'audit', 8)
        development = reserve(state, 'development', 2)
        resumed = json.loads(json.dumps(state))
        confirmation = reserve(resumed, 'confirmation', 6)
        self.assertEqual(len(set(audit + development + confirmation)), 16)
        self.assertNotIn(6101, audit + development + confirmation)
        self.assertEqual(reserve(json.loads(json.dumps(state)), 'confirmation', 6), confirmation)

    def test_banks_and_opponents_do_not_inflate_the_independent_sample_count(self):
        rows = paired_rows(seeds=1, gains={'base': 3, 'spread': 4, 'archive': 8})
        evidence = compare(rows, 'candidate')
        self.assertEqual(evidence['independent_seeds'], 1)
        self.assertFalse(promotion(evidence)['accepted'])

    def test_missing_and_duplicate_pairings_cannot_support_promotion(self):
        rows = paired_rows()
        for malformed in (rows[:-1], rows + [rows[0]]):
            with self.assertRaises(ValueError):
                compare(malformed, 'candidate')

    def test_average_gain_cannot_hide_a_regressing_opponent(self):
        evidence = compare(paired_rows(gains={'base': -3, 'weak': 20}), 'candidate')
        self.assertGreater(evidence['bootstrap_95_interval'][0], 0)
        self.assertFalse(promotion(evidence)['accepted'])
        self.assertTrue(promotion(compare(paired_rows(), 'candidate'))['accepted'])

    def test_ownership_prevents_simultaneous_campaign_writers(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            with exclusive(directory):
                with self.assertRaisesRegex(ValueError, 'already running'):
                    with exclusive(directory):
                        pass


@unittest.skipUnless((ROOT / 'tmp/coaching/symbolic_match').exists(), 'Build the native runner for transport checks')
class NativeRecovery(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        policy, roundtrip = prepare(ROOT / 'coaching/policies/executable/support.policy.md', self.directory / 'artifacts')
        baseline = self.directory / 'base.py'
        baseline.write_text((ROOT / 'coworld/player/base.py').read_text())
        self.job = dict(out=str(self.directory / 'match'), phase='test', arm='support', seed=9991, side=0, n=2,
                        ticks=32, goal=30, runner=str(ROOT / 'tmp/coaching/symbolic_match'), baseline=str(baseline),
                        policy=str(policy), roundtrip=str(roundtrip))

    def tearDown(self):
        self.temporary.cleanup()

    def test_resume_reuses_completed_game_but_rejects_changed_input(self):
        first = play_cached(self.job)
        self.assertEqual(first['roundtrip_actions'], 64)
        self.assertIsNone(first['candidate_decisions_per_second'], 'A short smoke cannot measure warmed throughput')
        with patch('coaching.symbolic.evaluate.play', side_effect=AssertionError('unexpected rerun')):
            self.assertEqual(play_cached(self.job), first)
        baseline = Path(self.job['baseline'])
        baseline.write_text(baseline.read_text() + '\n# changed input\n')
        with self.assertRaisesRegex(ValueError, 'inputs changed'):
            play_cached(self.job)

    def test_interrupted_attempt_is_preserved_and_retried(self):
        path = Path(self.job['out']); path.mkdir()
        (path / 'engine.log').write_text('unfinished attempt')
        self.assertEqual(play_cached(self.job)['roundtrip_mismatches'], 0)
        archives = list(self.directory.glob('match.attempt-*'))
        self.assertEqual(len(archives), 1)
        self.assertEqual((archives[0] / 'engine.log').read_text(), 'unfinished attempt')

    def test_silent_native_process_has_a_real_timeout(self):
        runner = self.directory / 'silent-runner'
        runner.write_text('#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n')
        runner.chmod(0o755)
        self.job.update(runner=str(runner), wall_limit=.1)
        with self.assertRaises(TimeoutError):
            play_cached(self.job)
        self.assertEqual(json.loads((Path(self.job['out']) / 'failure.json').read_text())['type'], 'TimeoutError')

    def campaign(self, path, *arguments):
        return subprocess.run([sys.executable, '-m', 'coaching.symbolic.campaign', '--out', str(path), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=30)

    def test_recorded_replication_uses_new_maps_and_audit_seals_tuning(self):
        original = self.directory / 'original'
        made = self.campaign(original, '--rounds', '0', '--ticks', '32', '--audit-seeds', '1', '--confirmation-seeds', '1')
        self.assertEqual(made.returncode, 0, made.stderr)
        state_path = original / 'campaign.json'
        state = json.loads(state_path.read_text())
        proposal = next(p for p in propose(parent(), set(), 10) if p.name == 'wider_lanes')
        state['history'].append(proposal.record(parent()) | {'ir_text': render(proposal.program), 'status': 'inconclusive'})
        state_path.write_text(json.dumps(state))
        replicate = self.directory / 'replication'
        result = self.campaign(replicate, '--import-run', str(original), '--replicate', 'wider_lanes',
                               '--ticks', '32', '--confirmation-seeds', '1', '--audit-seeds', '1')
        self.assertEqual(result.returncode, 0, result.stderr)
        completed = json.loads((replicate / 'campaign.json').read_text())
        report = json.loads((replicate / 'rounds/000/report.json').read_text())
        self.assertFalse(report['gate']['accepted'], 'One seed is insufficient even for an independent replication')
        self.assertEqual(completed['rounds'][0]['development_seeds'], [])
        self.assertTrue(set(completed['rounds'][0]['confirmation_seeds']).isdisjoint(state['audit_seeds']))
        games = list((replicate / 'rounds/000/games').glob('*/result.json'))
        mtimes = {str(p): p.stat().st_mtime_ns for p in games}
        self.assertEqual(self.campaign(replicate).returncode, 0)
        self.assertEqual(mtimes, {str(p): p.stat().st_mtime_ns for p in games})
        self.assertEqual(self.campaign(replicate, '--audit').returncode, 0)
        blocked = self.campaign(replicate)
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn('sealed', blocked.stderr)
        repeated = self.campaign(self.directory / 'again', '--import-run', str(replicate), '--replicate', 'wider_lanes', '--ticks', '32')
        self.assertNotEqual(repeated.returncode, 0)
        self.assertIn('already had its one independent replication', repeated.stderr)


if __name__ == '__main__':
    unittest.main()
