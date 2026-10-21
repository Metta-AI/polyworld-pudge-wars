"""Checked compiler for the initial v14 prose dialect and registered hypotheses.

Unsupported semantic changes fail closed. This is a bounded compiler, not a
claim that arbitrary prose has been implemented or behaviorally verified.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent / 'policies/v14'
ORACLE_HASH = 'b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def semantics(text):
    return '\n\n'.join(p.strip() for p in text.split('\n\n')
                        if not p.strip().startswith(('Evidence:', 'Provenance:')))


def compile_policy(source, output):
    oracle = (ROOT / 'oracle.py').read_bytes()
    if digest(oracle) != ORACLE_HASH:
        raise ValueError('Original oracle changed')
    text = source.read_text()
    contract = json.loads((ROOT / 'compiler_contract.json').read_text())
    key = digest(semantics(text).encode())
    if key not in contract:
        raise ValueError('Unrecognized IR edit: extend and verify the compiler before executing it')
    variant = contract[key]
    code = oracle.decode()
    if variant == 'blink-v2':
        code = code.replace('    recovering: bool = False\n',
                            '    recovering: bool = False\n    _hook_history: dict = field(default_factory=dict)\n', 1)
        code = code.replace('        self.recovering = False\n',
                            '        self._hook_history.clear()\n        self.recovering = False\n', 1)
        code = code.replace('        self.tick = tick\n',
                            '        self.tick = tick\n        blink_threat_is_live = measured_blink_threat(obs, self._hook_history)\n', 1)
        old = '            elif threat is not None:\n                # Keep the requested hop'
        assert code.count(old) == 1
        code = code.replace(old, '            elif threat is not None and blink_threat_is_live:\n                # Keep the requested hop')
        code += '\n\n' + (ROOT / 'skills/blink_v2.py').read_text()
    elif variant in ('rune-priority-v1', 'rune-owner-v1'):
        # E04 only reorders two existing skill selections. Hook execution and
        # every urgent/support skill retain the frozen library implementation.
        rune = '''        if not river:
            for rune in obs["visible"]["runes"]:
                if abs(me["x"] - rune["x"]) <= 36 and abs(me["y"] - rune["y"]) <= 36:
                    if throw([rune["x"], rune["y"]]):
                        break
'''
        lead = '        if target is not None and distance(me, target) <= reach + radius:\n'
        assert code.count(rune) == code.count(lead) == 1
        if variant == 'rune-priority-v1':
            code = code.replace(rune, '')
            code = code.replace(lead, rune + lead)
        else:
            owned = rune.replace('obs["visible"]["runes"]', 'owned_visible_runes(me, allies, obs["visible"]["runes"])')
            code = code.replace(lead, owned + lead)
            code += '\n\n' + (ROOT / 'skills/rune_owner_v1.py').read_text()
    elif variant != 'oracle':
        raise ValueError('Unknown compiler contract')
    compile(code, str(output), 'exec')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(code)
    report = {'variant': variant, 'ir_sha256': digest(text.encode()),
              'oracle_sha256': ORACLE_HASH, 'candidate_sha256': digest(code.encode()),
              'compiler_sha256': digest(Path(__file__).read_bytes()),
              'library_sha256': digest((ROOT / 'skills/blink_v2.py').read_bytes()),
              'status': 'candidate; behavioral verification required'}
    # Preserve the interpretive compiler's exact inputs with each artifact.
    # A hash alone would not recover a compiler that was subsequently edited.
    archive = output.with_suffix('.inputs')
    archive.mkdir(parents=True, exist_ok=True)
    (archive / 'compiler.py').write_bytes(Path(__file__).read_bytes())
    (archive / 'input.ir.md').write_text(text)
    (archive / 'compiler_contract.json').write_bytes((ROOT / 'compiler_contract.json').read_bytes())
    (archive / 'oracle.py').write_bytes(oracle)
    (archive / 'blink_v2.py').write_bytes((ROOT / 'skills/blink_v2.py').read_bytes())
    (archive / 'rune_owner_v1.py').write_bytes((ROOT / 'skills/rune_owner_v1.py').read_bytes())
    report['libraries'] = {p.name: digest(p.read_bytes()) for p in (ROOT / 'skills').glob('*.py')}
    output.with_suffix('.compile.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(compile_policy(args.source, args.output)))
