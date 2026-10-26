"""Compile and lift the registered complete coaching intervention E06."""
import argparse
import ast
import hashlib
import json
from pathlib import Path

from .session_compile import semantic

ROOT = Path(__file__).parent / 'policies/session-20260915-bundle'
ORACLE = 'b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def lower(variant):
    code = (ROOT/'oracle.py').read_text()
    if sha(code.encode()) != ORACLE:
        raise ValueError('Frozen baseline changed')
    if variant == 'parent':
        return code
    if variant != 'bundle':
        raise ValueError('Unsupported intervention')
    anchor = '            for ally in allies:\n'
    assert code.count(anchor) == 1
    code = code.replace(anchor, '''            if middle_obstacle_in_hook_path(start, end):
                BUNDLE_COUNTS["fountain_rejections"] += 1
                return False
''' + anchor)
    anchor = '        if target is not None and distance(me, target) <= 20 and not river:\n'
    assert code.count(anchor) == 1
    code = code.replace(anchor, '''        if free and not foreign_rot and "hook_to" not in action:
            for _, _, recipient_id, _, aim in coaching_engagements(me, allies, enemies, reach):
                if throw(aim, recipient_id):
                    BUNDLE_COUNTS["engagement_requests"] += 1
                    break
''' + anchor)
    return code + '\n\n' + (ROOT/'bundle_skills_v2.py').read_text()


def generate(source, output):
    text = source.read_text()
    contract = json.loads((ROOT/'compiler-contract.json').read_text())
    variant = contract.get(sha(semantic(text).encode()))
    if variant is None:
        raise ValueError('Unknown semantic edit: register and validate it before compilation')
    code = lower(variant)
    compile(code, str(output), 'exec')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as f:
        f.write(code)
    archive = output.with_suffix('.inputs')
    archive.mkdir()
    (archive/'input.ir.md').write_text(text)
    for name in ['oracle.py','bundle_skills_v1.py','bundle_skills_v2.py','parent.ir.md','bundle.ir.md','compiler-contract.json']:
        (archive/name).write_bytes((ROOT/name).read_bytes())
    for name in ['bundle_ir.py','session_compile.py']:
        (archive/name).write_bytes(Path(__file__).with_name(name).read_bytes())
    report = dict(variant=variant, policy_sha256=sha(code.encode()), ir_sha256=sha(text.encode()),
                  input_hashes={p.name:sha(p.read_bytes()) for p in archive.iterdir()})
    output.with_suffix('.compile.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


def extract(source, output):
    tree = ast.dump(ast.parse(source.read_text()), include_attributes=False)
    variants = [v for v in ['parent','bundle'] if tree == ast.dump(ast.parse(lower(v)),include_attributes=False)]
    if len(variants) != 1:
        raise ValueError('Unknown symbolic behavior cannot be lifted')
    text = (ROOT/(variants[0]+'.ir.md')).read_text()
    text += '\nEvidence: Extracted by whole-program AST recognition of the registered '+variants[0]+' lowering. Goals retain human provenance; runtime fidelity is scoped by verification results.\n'
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('x') as f:
        f.write(text)
    return dict(variant=variants[0], policy_sha256=sha(source.read_bytes()))


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation',choices=['generate','extract'])
    p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args()
    print(json.dumps((generate if a.operation=='generate' else extract)(a.source,a.output)))
