"""A bounded textual semantic IR with generation and code-derived extraction.

Extraction reads executable calls/branches, then validates the entire AST against
its supported grammar. It never recovers behavior from comments or an embedded IR.
"""
from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
import hashlib
from pathlib import Path
import re

from . import skills, skills_v2

BINDINGS = {skills.VERSION: skills, skills_v2.VERSION: skills_v2}


def binding_module(program):
    return BINDINGS[program.binding_version]

# Definitions expose skill boundaries and limitations, not just implementation names.
CONTRACTS = {
 'alive': ('Participation', 'Whether self is alive. A false result can end selection without actions.'),
 'observe': ('Situation and belief update', 'Classify low health at retreat_percent; estimate visible velocity from samples at least eight ticks apart; retain last-seen target and dodge side. Estimates are uncalibrated, not probabilities.'),
 'economy': ('Long-term capacity', 'Spend skill points on distance, speed, damage, then radius; buy available free wards, a low-health flask, repeated reach/boots ranks and an unoccupied hook buff. Decisions use confirmed inventory for later ward trips.'),
 'simple_movement': ('Support and survival', 'River or low health requests home; otherwise take a lane five tiles inside the bank, eight tiles vertically offset from the lowest-ID living teammate. Recomputed every decision.'),
 'reserve_when_hurt': ('Survival', 'Low health claims the hook channel without emitting a new hook request. Does not cancel an existing flight.'),
 'rescue': ('Teammate availability', 'Try the nearest living teammate on an enemy hook or below/equal 60% health in the river. Coordinated mode elects one eligible rescuer by distance then ID; success holds position and starts a ten-tick rescue commitment. Returns true only when a hook request is emitted.'),
 'sustain_rescue': ('Teammate availability', 'While safely on our bank, hold position during our friendly rescue flight or its ten-tick commitment. Higher danger/low health interrupts. Returns true while holding.'),
 'blink_defense': ('Survival', 'If blink is ready, escape the river toward our bank or move away from an incoming hook within the actual twenty-tile blink disk. Never chase offensively.'),
 'hooked': ('Control availability', 'Whether an enemy hook currently restricts our control; a true result may end selection after defensive actions.'),
 'follow_up': ('Team conversion', 'Try a visible enemy carried by a friendly hook, aiming between victim and reeler. Claims hook only if the throw primitive accepts its checks. End after one request.'),
 'close_shot': ('Immediate pressure', 'Try the nearest visible enemy within twenty tiles while outside the river.'),
 'intercept_hook': ('Defense', 'Try a hostile flying hook within fourteen tiles. This attempts an interception; it does not guarantee one.'),
 'swimming_shot': ('Team conversion', 'Try the nearest eligible enemy in the river.'),
 'aimed_shot': ('Pressure under motion uncertainty', 'Try the nearest eligible enemy within current reach plus five. Lead its sampled velocity by lead times Chebyshev distance divided by thirty plus speed rank. Exclude an aim segment within five tiles of the center.'),
 'nearest_shot': ('Independent pressure', 'Try the nearest visible eligible enemy at its current position, within a conservative fifty-five-tile envelope and five-tile ally clearance. Do not try a farther target when blocked.'),
 'rune_shot': ('Resource acquisition', 'Outside the river, try an observed rune within a thirty-six-tile square, in observation order. First feasible throw wins.'),
 'fog_shot': ('Exploration under partial observation', 'When no eligible enemy is visible, project the last-seen position using velocity; after ninety-six ticks use a bank-edge horizontal prior. Clamp to the enemy bank and arena. This is an uncertain speculative shot, not an observed enemy.'),
 'combat': ('Survival and local combat', 'Enable rot only for favorable close combat away from river/low health. Compare own health plus forty against nearest target, target <=120 health, or being stranded on enemy land. Attack within 5.5 tiles when favorable; mark hostile/ally rot exposure for movement.'),
 'tactical_movement': ('Survival, conversion and positioning', 'Priority: flee foreign rot; dodge hook threat; leave river; retain melee; approach caught target when healthy; retreat when low/unfavorable close combat; visit shop with spendable gold; otherwise fish in ID-ranked lanes with deterministic juke. bank_margin sets distance behind the play boundary; lane_spacing separates teammates symmetrically about y=64. A soon rune redirects the lane. Existing blink suppresses walking.'),
 'ward': ('Information gathering', 'With confirmed modern ward inventory on our bank, place across the river within thirty-two tiles; otherwise approach placement range only when not busy. Does not infer inventory from a purchase request.'),
}
PARAMETERS = {
 'observe': {'retreat_percent':(10,80)},
 'rescue': {'coordinated':bool},
 'aimed_shot': {'lead':(0,3)},
 'tactical_movement': {'bank_margin':(5,24),'lane_spacing':(8,40)},
 'spread_formation': {'lane_spacing':(8,32), 'rune_window':(0,256)},
 'formation_positioning': {'bank_margin':(5,24), 'lane_spacing':(8,32), 'rune_window':(0,256)},
 'clear_occupied_route': {'clearance':(6,9), 'lookahead':(8,16)},
}
CONTRACTS.update(skills_v2.CONTRACTS)
MODES = ('DO','TRY','STOP IF','STOP UNLESS')


@dataclass(frozen=True)
class Step:
    mode: str
    skill: str
    arguments: tuple[tuple[str,object], ...] = ()


@dataclass(frozen=True)
class Program:
    name: str
    binding_hash: str
    steps: tuple[Step,...]
    binding_version: str = skills.VERSION


def binding_hash(version=skills.VERSION):
    if version == skills.VERSION:
        return hashlib.sha256(Path(skills.__file__).read_bytes()).hexdigest()
    return BINDINGS[version].binding_hash()


def validate(program):
    if not re.fullmatch('[a-z][a-z0-9_]*',program.name):raise ValueError('Invalid policy ID')
    if program.binding_version not in BINDINGS:raise ValueError('Unsupported binding version')
    if program.binding_hash!=binding_hash(program.binding_version):raise ValueError('Skill binding changed; regenerate and re-evaluate explicitly')
    if not 1<=len(program.steps)<=50:raise ValueError('Expected 1–50 strategy steps')
    for step in program.steps:
        if step.mode not in MODES or step.skill not in CONTRACTS:raise ValueError('Unsupported strategy step')
        if not hasattr(binding_module(program), step.skill):raise ValueError('Skill unavailable in this binding version')
        args=dict(step.arguments)
        if len(args)!=len(step.arguments):raise ValueError('Duplicate parameter')
        for key,value in args.items():
            spec=PARAMETERS.get(step.skill,{}).get(key)
            if spec is None:raise ValueError(f'Unknown parameter {step.skill}.{key}')
            if spec is bool:
                if type(value)is not bool:raise ValueError('Expected true or false')
            elif type(value) not in (int,float) or not spec[0]<=value<=spec[1]:raise ValueError('Parameter outside contract')
    # This supported projection is total and initializes derived state first.
    if program.steps[0]!=Step('STOP UNLESS','alive'):raise ValueError('First guard must reject dead agents')
    if len(program.steps)<2 or program.steps[1].skill!='observe' or program.steps[1].mode!='DO':raise ValueError('Initialize observation before action skills')
    if any(s.skill in ('spread_formation','formation_positioning') for s in program.steps):
        if not any(s.skill=='remember_roster' for s in program.steps[2:next(i for i,s in enumerate(program.steps) if s.skill in ('spread_formation','formation_positioning'))]):
            raise ValueError('Remember the roster before allocating formation lanes')
    return program


def parse(text):
    blocks=re.findall(r'```policy-ir\n(.*?)\n```',text,re.S)
    if len(blocks)!=1:raise ValueError('Expected exactly one policy-ir text block')
    lines=[x.strip() for x in blocks[0].splitlines() if x.strip()]
    if len(lines)<4:raise ValueError('Incomplete policy program')
    if not re.fullmatch(r'POLICY [a-z][a-z0-9_]*',lines[0]):raise ValueError('Missing policy ID')
    binding = lines[1].split()
    if len(binding)!=3 or binding[0]!='BINDINGS' or binding[1] not in BINDINGS:raise ValueError('Unsupported binding version')
    steps=[]
    for line in lines[2:]:
        m=re.fullmatch(r'(DO|TRY|STOP IF|STOP UNLESS) ([a-z_]+)(\([^\n]*\))?( THEN FINISH)?',line)
        if not m or ((m[1]=='TRY') != bool(m[4])):raise ValueError('Unsupported strategy syntax: '+line)
        call=ast.parse(m[2]+(m[3] or '()'),mode='eval').body
        if not isinstance(call,ast.Call) or call.args:raise ValueError('Only named literal skill parameters are supported')
        arguments=[]
        for keyword in call.keywords:
            if keyword.arg is None:raise ValueError('Parameter expansion is unsupported')
            arguments.append((keyword.arg,ast.literal_eval(keyword.value)))
        steps.append(Step(m[1],m[2],tuple(sorted(arguments))))
    return validate(Program(lines[0].split()[1],binding[2],tuple(steps),binding[1]))


def render(program, origin='Extracted from supported executable control flow; rationale is a library interpretation.'):
    validate(program)
    names=list(dict.fromkeys(s.skill for s in program.steps))
    text=f'''# {program.name}: orthogonal policy IR

Format: symbolic policy text v1. Binding: {program.binding_version}.
Origin: {origin}

## 1. Situation

Players have team, identity, tile position, health, cooldown and inventory. Hooks have owner, victim, location and flight state. Inputs are each seat's fog-filtered observation. Numeric regions and affordances are defined by the skill contracts below; missing enemies remain unobserved, not absent from the world.

## 2. Belief

The observe skill retains sampled velocity and last-seen enemy position as point estimates, without calibrated confidence. Fog shooting, when selected, consumes that estimate. No hidden simulator state, opponent intentions or fabricated Bayesian probabilities enter selection. Context and memory reset when simulation ticks decrease; each seat owns its own state.

## 3. Goal

Named skill purposes below explain local preferences. Ordered control flow and channel claims resolve their conflicts. These labels are author/library interpretations; source code alone cannot recover a human's original reasons or a unique global reward function.

## 4. Skill

All skills terminate for this decision unless their contract explicitly retains state. Non-stopping steps compose actions; first feasible hook request claims the hook channel. Movement routines set the requested destination; later permitted movement can replace it. A rejected request does not establish a successful game outcome.

'''
    for name in names:
        goal,meaning=CONTRACTS[name]
        text+=f'**skill.{name} — {goal}.** {meaning}\n\n'
    text+='''## 5. Strategy

The block below is normative executable text. DO attempts a skill and continues; TRY finishes the decision only when the skill reports success; STOP IF/UNLESS ends the decision on its condition. FINISH preserves actions already composed. Ordering is an explicit conditional preference over resource use, not a scalar reward. Skill parameters override only their named contracts. Prose supplies the ontology and interpretation; the supported compiler consumes this block and the pinned skill definitions.

```policy-ir
'''
    text+=f'POLICY {program.name}\nBINDINGS {program.binding_version} {program.binding_hash}\n'
    for step in program.steps:
        args=', '.join(f'{k}={v!r}' for k,v in step.arguments)
        text+=f'{step.mode} {step.skill}'+(f'({args})' if args else '')+(' THEN FINISH' if step.mode=='TRY' else '')+'\n'
    text+='''```

## 6. Execution

Generate straight-line Python calls and explicit conditional returns against the pinned skill library. No original complete policy or embedded source is executed. A code-derived extraction must account for the whole supported AST; unknown statements are rejected. Reproducibility requires this policy, binding content hash, engine version, observation history and initial memory. Real-time network scheduling is outside an accelerated simulator comparison.

## 7. Update

Revise a named skill parameter or preference order in this text; generate a candidate; extract its executable behavior back to text; regenerate; compare full action histories and completion scores. Keep held-out seeds separate from candidate selection and preserve failed attempts. Performance evidence may propose a strategy/skill change; it does not recover an author's rationale or authorize unrecorded goal changes. Changes inside a skill require a new binding hash and new behavioral evidence. General ontology induction and unrestricted code extraction remain outside this bounded grammar.
'''
    return text


def generate(program):
    validate(program)
    module = binding_module(program).__name__.rsplit('.',1)[-1]
    lines=[f'"""Generated symbolic policy {program.name}."""',f'from coaching.symbolic import {module} as s',f'POLICY_NAME = {program.name!r}',f'BINDING_HASH = {program.binding_hash!r}','',
           'class Policy:','    def __init__(self):','        s.verify_binding(BINDING_HASH)','        self.state = s.State()','        self.trace = []','',
           '    def choose_action(self, observation):','        c = s.Context(observation, self.state)','        self.trace = c.trace']
    for step in program.steps:
        args=''.join(f', {k}={v!r}' for k,v in step.arguments)
        call=f's.invoke(c, {step.skill!r}{args})'
        if step.mode=='DO':lines.append('        '+call)
        else:
            test=('not ' if step.mode=='STOP UNLESS' else '')+call
            lines.extend(['        if '+test+':','            return s.finish(c)'])
    lines.append('        return s.finish(c)')
    return '\n'.join(lines)+'\n'


def _canonical(tree):
    tree=ast.parse(ast.unparse(tree))
    if tree.body and isinstance(tree.body[0],ast.Expr) and isinstance(tree.body[0].value,ast.Constant) and isinstance(tree.body[0].value.value,str):tree.body.pop(0)
    return ast.dump(tree,include_attributes=False)


def extract(source):
    tree=ast.parse(source)
    constants={n.targets[0].id:ast.literal_eval(n.value) for n in tree.body if isinstance(n,ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name)}
    classes=[n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Policy']
    if len(classes)!=1:raise ValueError('Expected one supported Policy class')
    methods=[n for n in classes[0].body if isinstance(n,ast.FunctionDef) and n.name=='choose_action']
    if len(methods)!=1:raise ValueError('Expected one choose_action method')
    steps=[]
    for statement in methods[0].body[2:-1]:
        mode='DO'
        if isinstance(statement,ast.If):
            condition=statement.test
            if isinstance(condition,ast.UnaryOp) and isinstance(condition.op,ast.Not):mode='STOP UNLESS';call=condition.operand
            else:mode='TRY';call=condition
        elif isinstance(statement,ast.Expr):call=statement.value
        else:raise ValueError('Unrecognized executable statement; extraction refused')
        if not isinstance(call,ast.Call) or ast.unparse(call.func)!='s.invoke' or len(call.args)!=2 or ast.unparse(call.args[0])!='c':raise ValueError('Unsupported skill invocation')
        name=ast.literal_eval(call.args[1])
        arguments=tuple(sorted((k.arg,ast.literal_eval(k.value)) for k in call.keywords))
        # STOP IF and TRY have identical operational meaning; extraction uses TRY.
        steps.append(Step(mode,name,arguments))
    imports=[n for n in tree.body if isinstance(n,ast.ImportFrom) and n.module=='coaching.symbolic']
    version = skills_v2.VERSION if any(a.name=='skills_v2' for n in imports for a in n.names) else skills.VERSION
    program=validate(Program(constants.get('POLICY_NAME',''),constants.get('BINDING_HASH',''),tuple(steps),version))
    if _canonical(tree)!=_canonical(ast.parse(generate(program))):raise ValueError('Source contains executable behavior outside the supported extraction grammar')
    return program


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('operation',choices=['generate','extract'])
    p.add_argument('source',type=Path);p.add_argument('output',type=Path)
    args=p.parse_args();source=args.source.read_text()
    result=generate(parse(source)) if args.operation=='generate' else render(extract(source))
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(result)
    print(args.output)


if __name__=='__main__':main()
