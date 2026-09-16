"""Compile the registered coaching prose amendment into a candidate policy.

This bounded dialect preserves the complete frozen parent. Unsupported prose
fails rather than silently leaving behavior unchanged. Verification is separate.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).parent / 'policies/session-20260915'
ORACLE = 'b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def semantic(text):
    return '\n\n'.join(p.strip() for p in text.split('\n\n')
                       if not p.strip().startswith(('Evidence:', 'Provenance:')))


def compile_ir(source, output):
    contract = json.loads((ROOT / 'compiler-contract.json').read_text())
    ir = source.read_text()
    variant = contract[digest(semantic(ir).encode())]
    oracle = (ROOT / 'oracle.py').read_bytes()
    assert digest(oracle) == ORACLE, 'Immutable oracle changed'
    code = oracle.decode()
    if variant == 'followup':
        anchor = '        if target is not None and distance(me, target) <= 20 and not river:\n'
        assert code.count(anchor) == 1
        selection = '''        if caught is not None:
            followup = carried.get(caught["id"])
            if followup is not None and followup["team"] == team and followup["owner_id"] != me["id"]:
                owner = next((p for p in units if p["id"] == followup["owner_id"]), caught)
                throw([(caught["x"] + owner["x"]) / 2, (caught["y"] + owner["y"]) / 2])
'''
        code = code.replace(anchor, selection + anchor)
    else:
        assert variant == 'parent'
    compile(code, str(output), 'exec')
    output.parent.mkdir(parents=True, exist_ok=True)
    assert not output.exists(), 'Keep prior candidates immutable'
    output.write_text(code)
    archive = output.with_suffix('.inputs')
    archive.mkdir()
    (archive / 'input.ir.md').write_text(ir)
    (archive / 'oracle.py').write_bytes(oracle)
    (archive / 'compiler.py').write_bytes(Path(__file__).read_bytes())
    (archive / 'compiler-contract.json').write_bytes((ROOT / 'compiler-contract.json').read_bytes())
    report = dict(variant=variant, ir_sha256=digest(ir.encode()),
                  semantic_sha256=digest(semantic(ir).encode()), oracle_sha256=ORACLE,
                  policy_sha256=digest(code.encode()), compiler_sha256=digest(Path(__file__).read_bytes()),
                  status='candidate; not accepted until empirical verification and evaluation')
    output.with_suffix('.compile.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('ir', type=Path); p.add_argument('output', type=Path)
    args = p.parse_args()
    print(json.dumps(compile_ir(args.ir, args.output)))
