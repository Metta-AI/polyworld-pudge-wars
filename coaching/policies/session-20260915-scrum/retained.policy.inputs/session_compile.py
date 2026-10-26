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
    elif variant == 'alternate-target':
        start = code.index('        if target is not None and distance(me, target) <= reach + radius:\n')
        end = code.index('        if not river:\n            for rune', start)
        primary_skill = code[start:end]
        # The existing skill implementation is the template. This edit adds
        # alternative skill arguments/order, not different aiming internals.
        alternative = primary_skill.replace('target', 'alternative').splitlines()
        alternative = ['    '+line for line in alternative]
        alternative[0] = '                if distance(me, alternative) <= reach + radius:'
        selection = '        if "hook_to" not in action:\n            for alternative in enemies[1:]:\n'
        selection += '\n'.join('    '+line for line in alternative) + '\n'
        # Align the copied if/body with the for-loop and stop at one claim.
        selection = selection.replace('                    if distance(me, alternative)', '                if distance(me, alternative)')
        selection += '                if "hook_to" in action:\n                    break\n'
        code = code[:end] + selection + code[end:]
    elif variant == 'return-sweep':
        anchor = '        # A purchase request may be refused by the live restock timer.\n'
        assert code.count(anchor) == 1
        code = code.replace(anchor, '''        if not busy:
            sweep = coaching_return_sweep(obs)
            if sweep is not None:
                action["walk_to"] = sweep

''' + anchor)
        code += '\n\n' + (ROOT / 'return_sweep_v1.py').read_text()
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
    if variant == 'return-sweep':
        (archive / 'return_sweep_v1.py').write_bytes((ROOT / 'return_sweep_v1.py').read_bytes())
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
