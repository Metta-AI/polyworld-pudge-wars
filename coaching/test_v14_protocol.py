"""Safety checks for the bounded prose compiler and immutable reference."""
import hashlib
import re
import tempfile
import unittest
from pathlib import Path
from .v14_compile import ROOT, ORACLE_HASH, compile_policy


class ProseCompilerTest(unittest.TestCase):
    def test_oracle_identity(self):
        self.assertEqual(hashlib.sha256((ROOT / 'oracle.py').read_bytes()).hexdigest(), ORACLE_HASH)

    def test_semantic_blocks_have_identity_provenance_and_evidence(self):
        for name in ['policy.md', 'blink-candidate.md', 'rune-candidate.md', 'rune-owner-candidate.md']:
            text = (ROOT / name).read_text()
            blocks = text.split('\n## ')[1:]
            ids = [re.match(r'\[([^]]+)\]', block).group(1) for block in blocks]
            self.assertEqual(len(ids), len(set(ids)), name)
            for block in blocks:
                self.assertIn('\nProvenance: ', block)
                self.assertIn('\nEvidence: ', block)

    def test_unknown_semantic_edit_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'input.md'
            source.write_text((ROOT / 'policy.md').read_text().replace('75 percent', '90 percent'))
            with self.assertRaisesRegex(ValueError, 'Unrecognized IR edit'):
                compile_policy(source, Path(tmp) / 'output.py')
            self.assertFalse((Path(tmp) / 'output.py').exists())

    def test_evidence_annotated_candidates_reproduce_evaluated_artifacts(self):
        expected = {
            'blink-candidate.md': 'a7b317e8d43274dc192b6218dbaf8965fbc9b880bd65a31e864e96e398db2cca',
            'rune-candidate.md': '881ace06d2ece134960d65dd65993dffa3594aa17be8fca72c26c30a73a98d18',
            'rune-owner-candidate.md': 'baf1e48988e7772e61e020873247498c487ac5a4d0712c966bb2a214763bcc2e',
        }
        with tempfile.TemporaryDirectory() as tmp:
            for name, sha in expected.items():
                report = compile_policy(ROOT / name, Path(tmp) / (name + '.py'))
                self.assertEqual(report['candidate_sha256'], sha)

    def test_evidence_edit_preserves_oracle_and_archives_inputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'input.md'
            source.write_text((ROOT / 'policy.md').read_text().replace(
                'Evidence: Untested semantic account; no ablation effect or confidence interval established.',
                'Evidence: Untested. A coach proposed a new test.'))
            output = Path(tmp) / 'output.py'
            report = compile_policy(source, output)
            self.assertEqual(output.read_bytes(), (ROOT / 'oracle.py').read_bytes())
            archive = output.with_suffix('.inputs')
            self.assertEqual((archive / 'input.ir.md').read_bytes(), source.read_bytes())
            self.assertEqual(hashlib.sha256((archive / 'compiler.py').read_bytes()).hexdigest(),
                             report['compiler_sha256'])


if __name__ == '__main__':
    unittest.main()
