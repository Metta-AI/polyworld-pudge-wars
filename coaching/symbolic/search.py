"""Bounded semantic experiments, independent behavior checks and paired evidence."""
from __future__ import annotations

from dataclasses import dataclass, replace
import hashlib
import inspect
import json
import random
import statistics

from . import skills
from .ir import PARAMETERS, Program, binding_module, extract, generate, validate


def fingerprint(program):
    """Ignore names, prose and spelling differences that do not change behavior."""
    rows = []
    for step in program.steps:
        defaults = {
            key: inspect.signature(getattr(binding_module(program), step.skill)).parameters[key].default
            for key in PARAMETERS.get(step.skill, {})
        }
        defaults.update(dict(step.arguments))
        values = {k: float(v) if type(v) in (int, float) else v for k, v in defaults.items()}
        rows.append(['TRY' if step.mode == 'STOP IF' else step.mode, step.skill, values])
    return hashlib.sha256(json.dumps([program.binding_hash, rows], sort_keys=True).encode()).hexdigest()


@dataclass(frozen=True)
class Proposal:
    name: str
    program: Program
    layer: str
    hypothesis: str
    prediction: str
    allowed_channels: tuple[str, ...]

    def record(self, parent):
        return dict(name=self.name, fingerprint=fingerprint(self.program), parent=fingerprint(parent),
                    layer=self.layer, hypothesis=self.hypothesis, prediction=self.prediction,
                    allowed_channels=self.allowed_channels, status='proposed')


def change_parameter(parent, skill, key, transform, name):
    matches = [step for step in parent.steps if step.skill == skill]
    if len(matches) != 1:
        return None
    old = dict(matches[0].arguments).get(key, inspect.signature(getattr(binding_module(parent), skill)).parameters[key].default)
    low, high = PARAMETERS[skill][key]
    value = max(low, min(high, transform(old)))
    args = dict(matches[0].arguments) | {key: value}
    step = replace(matches[0], arguments=tuple(sorted(args.items())))
    child = replace(parent, name=name, steps=tuple(step if s is matches[0] else s for s in parent.steps))
    return validate(child) if fingerprint(child) != fingerprint(parent) else None


def propose(parent, attempted, limit=2):
    """One semantic intervention per candidate; previous failures are not retried."""
    movement = 'formation_positioning' if any(s.skill=='formation_positioning' for s in parent.steps) else 'tactical_movement'
    specs = [
        ('shorter_lead', 'aimed_shot', 'lead', lambda x: x * .5, 'belief use',
         'A constant-velocity estimate may overshoot changes in enemy motion.',
         'A moving target receives less lead; stationary-target decisions are unchanged.', ('hook_to',)),
        ('longer_lead', 'aimed_shot', 'lead', lambda x: x * 1.5, 'belief use',
         'Aiming may undercompensate for target motion.',
         'A moving target receives more lead; stationary-target decisions are unchanged.', ('hook_to',)),
        ('wider_lanes', movement, 'lane_spacing', lambda x: x + 8, 'strategy positioning',
         'Separating fishing lanes may reduce teammate interference and concentration of risk.',
         'Idle teammates spread farther from center; defensive and hook choices stay unchanged.', ('walk_to',)),
        ('retreat_earlier', 'observe', 'retreat_percent', lambda x: x + 10, 'situation threshold',
         'Retreat may begin after an exposure is already too costly.',
         'Health between the old and new thresholds requests home; high-health decisions stay unchanged.',
         ('walk_to', 'rot', 'hook_to', 'attack_target')),
        ('closer_bank', movement, 'bank_margin', lambda x: x - 4, 'strategy positioning',
         'A safer-looking distant bank posture may surrender effective range.',
         'Idle bank position advances four tiles; hook and emergency choices stay unchanged.', ('walk_to',)),
    ]
    candidates = []
    for name, skill, key, transform, layer, hypothesis, prediction, channels in specs:
        child = change_parameter(parent, skill, key, transform, name)
        if child is not None:
            candidates.append(Proposal(name, child, layer, hypothesis, prediction, channels))
    # A structural alternative, not another numeric parameter.
    if any(s.skill == 'fog_shot' for s in parent.steps):
        child = replace(parent, name='withhold_fog_shots', steps=tuple(s for s in parent.steps if s.skill != 'fog_shot'))
        candidates.insert(3, Proposal('withhold_fog_shots', child, 'strategy affordance',
            'Speculation consumes hook availability without confirmed target evidence.',
            'No speculative hook is requested when enemies are unobserved; visible-target decisions stay unchanged.', ('hook_to',)))
    found = []
    for candidate in candidates:
        key = (fingerprint(parent), fingerprint(candidate.program))
        if key not in attempted and fingerprint(candidate.program) not in {fingerprint(p.program) for p in found}:
            found.append(candidate)
        if len(found) >= limit:
            break
    return found


def scenario(tick=100, hp=800, enemy=True):
    def player(pid, team, x, y):
        return dict(id=pid, team=team, x=x, y=y, hp=hp if pid == 1 else 800,
                    max_hp=1000, alive=True, shield=0, hooked=False, hook_ready=True,
                    layer=team, in_river=False, home_x=20 if team == 0 else 108, home_y=32,
                    upgrades=[0]*4, item_ranks=[0]*5, rot=False)
    units = [player(1, 0, 40, 32), player(2, 0, 20, 96)]
    if enemy:
        units.append(player(3, 1, 80, 32))
    return dict(tick=tick, self=units[0], play_west_max=52, play_east_min=76,
                visible=dict(pudges=units, hooks=[], runes=[]))


def instance(program):
    namespace = {}
    exec(generate(program), namespace)
    return namespace['Policy']()


def check_proposal(parent, proposal):
    """Test predicted meaning separately from compiler round-trip identity."""
    child = proposal.program
    checks = []
    def require(condition, label):
        if not condition:
            raise ValueError('Semantic contract failed: ' + label)
        checks.append(label)
    require(fingerprint(extract(generate(child))) == fingerprint(child), 'code-derived semantic identity')
    dead = scenario(); dead['self']['alive'] = False
    require(instance(child).choose_action(dead) == {}, 'dead agents emit no actions')
    hurt = scenario(hp=100)
    require(instance(child).choose_action(hurt).get('walk_to') == [20, 32], 'emergency retreat preserved')
    caught = scenario(); caught['self']['hooked'] = True
    require('hook_to' not in instance(child).choose_action(caught), 'hooked agent does not cast')
    blocked = scenario(); blocked['visible']['pudges'][1].update(x=60, y=32)
    require('hook_to' not in instance(child).choose_action(blocked), 'friendly throw corridor preserved')
    # Check immediate non-interference across several contrasting histories.
    for hp in (100, 800):
        for visible in (True, False):
            a, b = instance(parent), instance(child)
            for tick in (0, 8, 16):
                obs = scenario(tick=tick, hp=hp, enemy=visible)
                if visible:
                    obs['visible']['pudges'][-1]['y'] += tick / 2
                before, after = a.choose_action(obs), b.choose_action(obs)
                other_before = {k: v for k, v in before.items() if k not in proposal.allowed_channels}
                other_after = {k: v for k, v in after.items() if k not in proposal.allowed_channels}
                require(other_before == other_after, 'protected channels unchanged')
    name = proposal.name
    if name in ('shorter_lead', 'longer_lead'):
        a, b = instance(parent), instance(child)
        first = scenario(tick=0)
        require(a.choose_action(first) == b.choose_action(first), 'stationary aim unchanged')
        moving = scenario(tick=8); moving['visible']['pudges'][-1]['y'] = 40
        before, after = a.choose_action(moving)['hook_to'][1], b.choose_action(moving)['hook_to'][1]
        require(after < before if name == 'shorter_lead' else after > before, proposal.prediction)
    elif name == 'withhold_fog_shots':
        empty = scenario(enemy=False)
        require('hook_to' in instance(parent).choose_action(empty), 'parent actually speculates in the probe')
        require('hook_to' not in instance(child).choose_action(empty), proposal.prediction)
        require(instance(parent).choose_action(scenario()) == instance(child).choose_action(scenario()), 'visible-target behavior unchanged')
    elif name == 'retreat_earlier':
        def threshold(program):
            return next(dict(s.arguments).get('retreat_percent', 35) for s in program.steps if s.skill == 'observe')
        between = scenario(hp=10 * (threshold(parent) + threshold(child)) / 2)
        require(instance(parent).choose_action(between).get('walk_to') != [20, 32], 'parent does not retreat in the probe')
        require(instance(child).choose_action(between).get('walk_to') == [20, 32], proposal.prediction)
        require(instance(parent).choose_action(scenario()) == instance(child).choose_action(scenario()), 'high-health behavior unchanged')
    else:
        before = instance(parent).choose_action(scenario())['walk_to']
        after = instance(child).choose_action(scenario())['walk_to']
        require(abs(after[1] - 64) > abs(before[1] - 64) if name == 'wider_lanes' else after[0] > before[0], proposal.prediction)
    return dict(passed=True, checks=list(dict.fromkeys(checks)), prediction=proposal.prediction)


def compare(rows, candidate, parent='parent'):
    """Require complete pairings; bootstrap independent seeds, not seats/games."""
    index = {}
    for row in rows:
        key = (row['arm'], row['seed'], row.get('opponent', 'base'), row['side'])
        if key in index:
            raise ValueError('Duplicate game in paired comparison')
        index[key] = row
    seeds = sorted({r['seed'] for r in rows})
    opponents = sorted({r.get('opponent', 'base') for r in rows})
    deltas, win_deltas = [], []
    by_opponent = {name: [] for name in opponents}
    by_bank = {str(side): [] for side in (0, 1)}
    for seed in seeds:
        paired = []
        for opponent in opponents:
            for side in (0, 1):
                try:
                    a = index[(candidate, seed, opponent, side)]
                    b = index[(parent, seed, opponent, side)]
                except KeyError as error:
                    raise ValueError('Incomplete seed/opponent/bank comparison') from error
                difference = a['margin'] - b['margin']
                paired.append(difference)
                by_opponent[opponent].append(difference)
                by_bank[str(side)].append(difference)
                win_deltas.append((a['margin'] > 0) + .5 * (a['margin'] == 0) - (b['margin'] > 0) - .5 * (b['margin'] == 0))
        deltas.append(statistics.mean(paired))
    if not deltas:
        raise ValueError('No paired evidence')
    rng = random.Random(0)
    means = sorted(statistics.mean(rng.choices(deltas, k=len(deltas))) for _ in range(4000))
    return dict(seeds=seeds, independent_seeds=len(seeds), seed_margin_differences=deltas,
                mean_margin_difference=statistics.mean(deltas), bootstrap_95_interval=[means[99], means[3899]],
                win_rate_difference=statistics.mean(win_deltas),
                opponent_margin_differences={k: statistics.mean(v) for k, v in by_opponent.items()},
                bank_margin_differences={k: statistics.mean(v) for k, v in by_bank.items()})


def promotion(evidence, minimum_seeds=6, minimum_gain=1.0):
    reasons = []
    if evidence['independent_seeds'] < minimum_seeds:
        reasons.append('insufficient independent confirmation seeds')
    if evidence['mean_margin_difference'] < minimum_gain:
        reasons.append('mean margin gain below the minimum effect')
    if evidence['bootstrap_95_interval'][0] <= 0:
        reasons.append('paired interval includes no improvement')
    if evidence['win_rate_difference'] < 0:
        reasons.append('win rate regressed')
    if min(evidence['opponent_margin_differences'].values()) < -2:
        reasons.append('an opponent matchup regressed by more than two kills')
    return dict(accepted=not reasons, reasons=reasons,
                interpretation='Exploratory seed bootstrap gate; repeated adaptive rounds still require an untouched final audit.')
