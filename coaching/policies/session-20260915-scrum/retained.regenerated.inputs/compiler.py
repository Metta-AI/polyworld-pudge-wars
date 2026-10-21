"""Bounded v14 prose -> symbolic source -> prose for session E04/E05.

Follows session_compile's frozen-oracle workflow. Only reviewed, registered
documents compile. Extraction checks the entire executable AST against each
registered lowering; metadata/comments cannot conceal unrecognized behavior.
This is not a general natural-language compiler or a proof of goal fidelity.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path

from .session_compile import semantic

ROOT = Path(__file__).parent / "policies/session-20260915-scrum"
ORACLE = "b848fa26c978ff1553ef91a00ddc1f85af32b5b2bfd4c67bd983f74cf66232b6"
VARIANTS = ("parent", "engagement", "fountain")
ENGAGEMENT = '''        if free and not foreign_rot and "hook_to" not in action:
            for _, _, recipient_id, _, aim in coaching_engagements(me, allies, enemies, reach):
                if throw(aim, recipient_id):
                    break
'''
FOUNTAIN = '''            if rescue_id == 0 and segment_distance(start, end, [64.5, 64.5]) <= 3.5:
                return False
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def lower(variant):
    data = (ROOT / "oracle.py").read_bytes()
    if digest(data) != ORACLE:
        raise ValueError("Frozen v14 oracle changed")
    code = data.decode()
    if variant == "engagement":
        anchor = "        if target is not None and distance(me, target) <= reach + radius:\n"
        if code.count(anchor) != 1:
            raise ValueError("Hook priority anchor changed")
        code = code.replace(anchor, ENGAGEMENT + anchor)
        code += "\n\n" + (ROOT / "engagement_v1.py").read_text()
    elif variant == "fountain":
        anchor = "            for ally in allies:\n"
        if code.count(anchor) != 1:
            raise ValueError("Throw guard anchor changed")
        code = code.replace(anchor, FOUNTAIN + anchor)
    elif variant != "parent":
        raise ValueError("Unregistered variant")
    return code


def identify_ir(text):
    contract = json.loads((ROOT / "compiler-contract.json").read_text())
    key = digest(semantic(text).encode())
    if key not in contract:
        raise ValueError("Unregistered semantic edit; add grounding and verification first")
    return contract[key]


def generate(source, output):
    text = source.read_text()
    variant = identify_ir(text)
    code = lower(variant)
    compile(code, str(output), "exec")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as f:
        f.write(code)
    archive = output.with_suffix(".inputs")
    archive.mkdir()
    (archive / "input.ir.md").write_text(text)
    for name in ("oracle.py", "compiler-contract.json", "engagement_v1.py"):
        (archive / name).write_bytes((ROOT / name).read_bytes())
    for name in VARIANTS:
        (archive / (name + ".ir.md")).write_bytes((ROOT / (name + ".ir.md")).read_bytes())
    (archive / "compiler.py").write_bytes(Path(__file__).read_bytes())
    (archive / "session_compile.py").write_bytes(Path(__file__).with_name("session_compile.py").read_bytes())
    report = dict(variant=variant, ir_sha256=digest(text.encode()),
                  policy_sha256=digest(code.encode()), oracle_sha256=ORACLE,
                  archive_hashes={p.name: digest(p.read_bytes()) for p in sorted(archive.iterdir())})
    output.with_suffix(".compile.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def extract(source, output):
    tree = ast.dump(ast.parse(source.read_text()), include_attributes=False)
    matches = [v for v in VARIANTS if tree == ast.dump(ast.parse(lower(v)), include_attributes=False)]
    if len(matches) != 1:
        raise ValueError("Symbolic behavior is outside the registered projection; cannot lift")
    variant = matches[0]
    text = (ROOT / (variant + ".ir.md")).read_text()
    # Extraction may enrich evidence, but must preserve registered semantics.
    text += "\nEvidence: Full executable AST matches the registered " + variant + " lowering. "
    text += "This recovers declared decisions; goal rationale is retained source provenance, not inferred from actions.\n"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as f:
        f.write(text)
    return dict(variant=variant, symbolic_sha256=digest(source.read_bytes()), ir_sha256=digest(text.encode()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("generate", "extract"))
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(json.dumps((generate if args.operation == "generate" else extract)(args.source, args.output)))
