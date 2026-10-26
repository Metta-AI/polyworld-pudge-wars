"""Independent semantic reference and boundary probes for E04/E05.

The oracle supplies unchanged behavior. Only the declared decision regions are
independently implemented here, using quadratic disk intersection and explicit
pair ordering. Full-reference agreement is scoped to these edits, not inferred
agreement of every inherited prose block with v14.
"""
import argparse
import copy
import itertools
import json
import math
from pathlib import Path
import types
import sys

from .v14_verify import load, unit, existing_state


def disk_hit(start, end):
    x, y = start[0] - 64.5, start[1] - 64.5
    dx, dy = end[0] - start[0], end[1] - start[1]
    c = x*x + y*y - 3.5**2
    if c <= 0:
        return True
    a = dx*dx + dy*dy
    if a == 0:
        return False
    b = 2*(x*dx + y*dy)
    discriminant = b*b - 4*a*c
    # Quadratic cancellation at an exact tangent can produce a tiny negative
    # discriminant. This reference-only rounding tolerance is far below the
    # observation's .001-tile precision; it does not change the policy guard.
    if discriminant < 0 and math.isclose(b*b, 4*a*c, rel_tol=1e-14, abs_tol=1e-14):
        discriminant = 0.0
    if discriminant < 0:
        return False
    root = math.sqrt(discriminant)
    return (-b-root)/(2*a) <= 1 and (-b+root)/(2*a) >= 0


def reference_pairs(me, units, reach):
    result = []
    for a in units:
        if (not a['alive'] or a['team'] != me['team'] or a['id'] == me['id']
                or a['shield'] != 0 or a['hooked'] or a['hp'] > a['max_hp']-120):
            continue
        for e in units:
            if (not e['alive'] or e['team'] == me['team'] or e['shield'] != 0
                    or e['hooked'] or e['layer'] != a['layer']):
                continue
            if (a['x']-e['x'])**2+(a['y']-e['y'])**2 > 5.5**2:
                continue
            center = [(a['x']+e['x'])*0.5, (a['y']+e['y'])*0.5]
            if math.hypot(center[0]-me['x'], center[1]-me['y']) > reach:
                continue
            if disk_hit([me['x'], me['y']], center):
                continue
            result.append((a['hp']/a['max_hp'], math.hypot(a['x']-me['x'], a['y']-me['y']),
                           a['id'], e['id'], center))
    return sorted(result)


def reference_module(oracle, variant, name):
    code = oracle.read_text()
    if variant == 'engagement':
        before = '        if target is not None and distance(me, target) <= reach + radius:\n'
        code = code.replace(before, '''        if free and not foreign_rot and "hook_to" not in action:
            options = reference_pairs(me, obs["visible"]["pudges"], reach)
            reference_counts["eligible_pairs"] += len(options)
            for option in options:
                if throw(option[4], option[2]):
                    reference_counts["engagement_requests"] += 1
                    break
''' + before)
    elif variant == 'fountain':
        before = '            for ally in allies:\n'
        code = code.replace(before, '''            if rescue_id == 0 and disk_hit(start, end):
                reference_counts["blocked_fountain_attempts"] += 1
                return False
''' + before)
    else:
        raise ValueError(variant)
    module = types.ModuleType(name)
    sys.modules[name] = module
    from collections import Counter
    module.__dict__.update(disk_hit=disk_hit, reference_pairs=reference_pairs, reference_counts=Counter())
    exec(compile(code, str(oracle) + ':reference', 'exec'), module.__dict__)
    return module


def equivalent(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(equivalent(a[k], b[k]) for k in a)
    if isinstance(a, (tuple, list)) and isinstance(b, (tuple, list)):
        return len(a) == len(b) and all(equivalent(x, y) for x, y in zip(a, b))
    if isinstance(a, float) or isinstance(b, float):
        return isinstance(a, (float, int)) and isinstance(b, (float, int)) and abs(a-b) <= 1e-7
    return a == b


def check(obs, base, candidate, reference, regenerated, variant):
    actions = [b.choose_action(obs) for b in (base, candidate, reference, regenerated)]
    if not equivalent(actions[1], actions[2]):
        raise AssertionError(('semantic reference mismatch', actions))
    if actions[1] != actions[3] or vars(candidate) != vars(regenerated):
        raise AssertionError(('round-trip mismatch', actions))
    if not equivalent(existing_state(candidate), existing_state(reference)):
        raise AssertionError('semantic state mismatch')
    if variant == 'engagement':
        if {k:v for k,v in actions[0].items() if k != 'hook_to'} != {k:v for k,v in actions[1].items() if k != 'hook_to'}:
            raise AssertionError(('non-hook isolation leak', actions))
        if existing_state(base) != existing_state(candidate):
            raise AssertionError('engagement state leak')
    return actions[0], actions[1]


def observation(team=0, y=40., gap=5., state='normal', blocker=False):
    direction = 1 if team == 0 else -1
    me = unit(1, team, 36 if team == 0 else 92, y)
    me['blink_ready'] = False
    ally = unit(2, team, me['x'] + direction*40, y)
    ally['layer'] = 1-team
    ally['hp'] = 600
    enemy = unit(4, 1-team, ally['x'] + direction*gap, y)
    hooks = []
    units = [me, ally, enemy]
    if state == 'dead': me['alive'] = False
    if state == 'hooked': me['hooked'] = True
    if state == 'cooldown': me['hook_ready'] = False
    if state == 'low': me['hp'] = 300
    if state == 'full-ally': ally['hp'] = 1200
    if state == 'missing-119': ally['hp'] = 1081
    if state == 'missing-120': ally['hp'] = 1080
    if state == 'shielded-ally': ally['shield'] = 5
    if state == 'shielded-enemy': enemy['shield'] = 5
    if state == 'wrong-layer': ally['layer'] = team
    if state == 'no-ally': units.remove(ally)
    if state == 'hidden-enemy': units.remove(enemy)
    if state == 'caught':
        enemy['hooked'] = True
        hooks.append(dict(owner_id=2, team=team, x=enemy['x'], y=y, victim=4, flying=False))
    if state == 'rescue':
        ally['hooked'] = True
        hooks.append(dict(owner_id=4, team=1-team, x=ally['x'], y=y, victim=2, flying=False))
    if state == 'threat':
        me['blink_ready'] = True
        hooks.append(dict(owner_id=4, team=1-team, x=me['x']+direction*10, y=y+2, victim=0, flying=True))
    if state == 'close': units.append(unit(5, 1-team, me['x']+direction*12, y-10))
    if blocker: units.append(unit(3, team, me['x']+direction*16, y))
    return dict(tick=100, game_version=37, self=me, play_west_max=52, play_east_min=76,
                visible=dict(pudges=units, hooks=hooks, runes=[], props=[]),
                ally_ping=None, rune_next=dict(soon=0, x=-1, y=-1))


def verify(root, variant):
    base_mod = load(root/'baseline.py', 'scrum_probe_base')
    candidate_mod = load(root/'candidate.py', 'scrum_probe_candidate')
    regen_mod = load(root/'regenerated.py', 'scrum_probe_regen')
    ref_mod = reference_module(root/'baseline.py', variant, 'scrum_probe_ref')
    rows = []
    states = ('normal','dead','hooked','cooldown','low','full-ally','missing-119','missing-120',
              'shielded-ally','shielded-enemy','wrong-layer','no-ally','hidden-enemy',
              'caught','rescue','threat','close')
    for team, y, gap, state, blocker in itertools.product((0,1), (40.,60.99,61.,61.01,64.5,68.,68.01),
                                                         (0.,5.49,5.5,5.51), states, (False,True)):
        bots = [m.BasePolicy(heal_allies=True, spread_fishing=True) for m in (base_mod,candidate_mod,ref_mod,regen_mod)]
        obs = observation(team,y,gap,state,blocker)
        a,b = check(obs,*bots,variant)
        if variant == 'engagement' and state in ('normal','missing-120') and not blocker and y==40 and gap<=5.5:
            expected = reference_pairs(obs['self'], obs['visible']['pudges'],60)[0][4]
            assert equivalent(b.get('hook_to'), expected), 'Unmasked centroid coverage failure'
        if state in ('dead','hooked','cooldown','rescue'):
            assert a == b, ('Protected decision changed', state, a, b)
        rows.append(dict(team=team,y=y,gap=gap,state=state,blocker=blocker,parent=a,candidate=b))
    if variant == 'fountain':
        # Expose callers the parent's ordinary-shot filter does not cover.
        for team,y,kind in itertools.product((0,1),(40.,60.99,61.,61.01,64.5,68.,68.01),
                                             ('blind','rune','swimmer','short-shot')):
            obs=observation(team,y,state='no-ally')
            me=obs['self']; direction=1 if team==0 else -1
            obs['visible']['pudges']=[me]
            aim=[me['x']+direction*42,y]
            if kind=='rune':obs['visible']['runes']=[dict(x=64,y=y)]
            if kind=='swimmer':
                e=unit(4,1-team,64,y);e['layer']=2
                obs['visible']['pudges'].append(e)
            if kind=='short-shot':
                # An attempt ending before the disk must remain eligible.
                e=unit(4,1-team,me['x']+direction*18,y)
                obs['visible']['pudges'].append(e)
            bots=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in (base_mod,candidate_mod,ref_mod,regen_mod)]
            a,b=check(obs,*bots,variant)
            if kind=='blind' and 61.<=y<=68.:
                assert 'hook_to' in a and 'hook_to' not in b, 'Unmasked fountain coverage failure'
            if kind=='short-shot' or y==40.:
                assert a==b, 'Clear finite segment must preserve the parent'
            rows.append(dict(team=team,y=y,state=kind,parent=a,candidate=b))
    # Geometry is measured independently at tangents, endpoints, and finite reach.
    geometry = [([36,64.5],[55,64.5],False),([36,64.5],[61.,64.5],True),([36,61.],[92,61.],True),
                ([36,60.999],[92,60.999],False),([64.5,64.5],[64.5,64.5],True),([20,20],[20,20],False)]
    for start,end,expected in geometry:
        assert disk_hit(start,end) is expected
    assert not equivalent([1.,2.], [1.,2.01]), 'Tolerance must reject material errors'
    out = root/'verification'
    out.mkdir()
    (out/'decision-table.json').write_text(json.dumps(rows,indent=2)+'\n')
    report = dict(cases=len(rows), geometry_cases=len(geometry), changed=sum(r['parent']!=r['candidate'] for r in rows),
                  scoped_agreement=1.0, semantic_mismatches=0, roundtrip_mismatches=0,
                  reference_counts=dict(ref_mod.reference_counts),
                  scope='Finite E04/E05 decision regions and unchanged source context; inherited prose and goal rationale not empirically lifted.')
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('study',type=Path)
    parser.add_argument('--variant',required=True,choices=('engagement','fountain'))
    args=parser.parse_args()
    print(json.dumps(verify(args.study,args.variant)))
