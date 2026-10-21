"""Independent probes of the rune-priority strategy projection."""
import argparse
import copy
import csv
import itertools
import json
import math
from pathlib import Path
from .v14_verify import load, unit, existing_state


def verify_decision(obs, parent, candidate, parent_policy, owner_only=False):
    """Check allowed action-channel changes; table probes check masked coverage."""
    if parent == candidate:
        return False
    me = obs['self']
    assert me['alive'] and not me['hooked'] and me['hook_ready'] and me['layer'] != 2
    assert {k: v for k, v in parent.items() if k != 'hook_to'} == {
        k: v for k, v in candidate.items() if k != 'hook_to'}
    aim = candidate.get('hook_to')
    assert aim in [[max(8., min(119., r['x'])), max(8., min(119., r['y']))]
                   for r in obs['visible']['runes']
                   if abs(me['x']-r['x']) <= 36 and abs(me['y']-r['y']) <= 36]
    if owner_only:
        visible = obs['visible']['pudges']
        assert any(p['alive'] and p['team']==me['team'] and p['id']!=me['id'] for p in visible)
        eligible = [p for p in visible if p['alive'] and p['team']==me['team']
                    and p['layer']==me['team'] and not p['hooked'] and not p['rot']
                    and p['hp']*100 >= p['max_hp']*40]
        assert min(eligible, key=lambda p: (math.hypot(p['x']-aim[0],p['y']-aim[1]),p['id']))['id']==me['id']
    # Existing active healing/rescue holds cannot be displaced by E04.
    assert not (parent_policy.rescue_until > obs['tick']
                and parent.get('walk_to') == [me['x'], me['y']])
    return True


def verify(study, owner_only=False):
    modules = [load(study / name, 'rune_' + name.replace('.', '_'))
               for name in ['baseline.py', 'candidate.py', 'candidate-repeat.py']]
    rows = []
    cases = itertools.product((0, 1), ('absent', 'near', 'edge', 'far', 'two'),
                              ('distant', 'close', 'caught', 'swimmer', 'hidden'),
                              ('normal', 'dead', 'hooked', 'unready', 'river', 'healing', 'blocked'))
    for index, (team, rune_case, target_case, mode) in enumerate(cases):
        direction = 1 if team == 0 else -1
        me = unit(1 if team == 0 else 4, team, 36 if team == 0 else 92, 32)
        enemy = unit(20, 1-team, me['x'] + direction*(15 if target_case == 'close' else 42), 32)
        enemy['hooked'] = target_case == 'caught'
        if target_case == 'swimmer':
            enemy['layer'] = 2
        allies = [unit(me['id']+1, team, me['x']-direction*10, 42),
                  unit(me['id']+2, team, me['x']-direction*10, 95)]
        if mode == 'dead': me['alive'] = False
        if mode == 'hooked': me['hooked'] = True
        if mode == 'unready': me['hook_ready'] = False
        if mode == 'river': me['layer'] = 2
        if mode == 'healing': allies[0]['hp'] = 800
        if mode == 'blocked': allies[0]['x'], allies[0]['y'] = me['x']+direction*10, 32
        runes = [] if rune_case == 'absent' else [dict(id=1, kind=4,
            x=me['x'] + direction*{'near': 28, 'edge': 36, 'far': 36.01, 'two': 28}[rune_case], y=32)]
        if rune_case == 'two': runes.append(dict(id=2, kind=1, x=me['x']+direction*24, y=55))
        obs = dict(tick=100, game_version=37, self=me, play_west_max=52, play_east_min=76,
                   visible=dict(pudges=[me, *allies] + ([] if target_case=='hidden' else [enemy]),
                                hooks=[], props=[], runes=runes),
                   ally_ping=None, rune_next=dict(soon=0,x=-1,y=-1))
        bots = [m.BasePolicy(heal_allies=True, spread_fishing=True) for m in modules]
        answers = [p.choose_action(copy.deepcopy(obs)) for p in bots]
        assert answers[1] == answers[2], ('repeat disagreement', index)
        assert existing_state(bots[0]) == existing_state(bots[1]), ('state leak', index)
        changed = verify_decision(obs, answers[0], answers[1], bots[0], owner_only)
        # These authored partitions have a clear first rune and a viable enemy shot.
        expected = (mode == 'normal' and target_case == 'distant'
                    and rune_case in ('near', 'edge', 'two'))
        if expected:
            assert answers[1].get('hook_to') == [runes[0]['x'], runes[0]['y']], ('coverage', index)
        # Urgent targets and unavailable skills mask the preference completely.
        masked = mode in ('dead', 'hooked', 'unready', 'river') or target_case in ('close','caught','swimmer')
        if masked: assert answers[0] == answers[1], ('priority leak', index)
        rows.append(dict(case=index, team=team, rune=rune_case, target=target_case,
                         mode=mode, changed=changed, expected_override=expected, masked=masked))
    output=study/'verification'; output.mkdir(exist_ok=True)
    with (output/'decision-table.csv').open('w') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    report=dict(cases=len(rows),changed=sum(r['changed'] for r in rows),
                explicit_coverage_cases=sum(r['expected_override'] for r in rows),
                masked=sum(r['masked'] for r in rows),isolation_ok=True,coverage_ok=True,
                candidate_agreement=1.,lift_agreement=1.,residual_fraction=0.,
                scope='Enumerated rune-priority partitions only. Full strategy semantics and trajectories remain unlifted.')
    (output/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    (output/'lifted.md').write_text('# Observed rune priority\n\n'+
        f"In {len(rows)} probes, candidate changed {report['changed']} hook choices. "
        'Urgent shots and unavailable skills masked the preference. '
        'All other action channels and existing memory matched the oracle. '
        'Residual 0 within these partitions; full-policy semantic residual is unmeasured.\n')
    return report


def verify_ownership(study):
    """Exercise local election boundaries independently of the helper's code."""
    parent=load(study/'baseline.py','owner_parent');candidate=load(study/'candidate.py','owner_candidate')
    rows=[]
    for team,condition in itertools.product((0,1),('far','near','cooldown','low','threshold','hooked','rot','enemybank','dead','alone','tie-winner','tie-loser')):
        d=1 if team==0 else -1
        me=unit(2,team,36 if team==0 else 92,32)
        ally=unit(3,team,me['x']+d*24,40)
        enemy=unit(20,1-team,me['x']+d*42,32)
        rune=dict(id=1,kind=1,x=me['x']+d*28,y=32)
        if condition=='far':ally['x']=me['x']-d*16
        if condition=='cooldown':ally['hook_ready']=False
        if condition=='low':ally['hp']=479
        if condition=='threshold':ally['hp']=480
        if condition=='hooked':ally['hooked']=True
        if condition=='rot':ally['rot']=True
        if condition=='enemybank':ally['layer']=1-team
        if condition=='dead':ally['alive']=False
        if condition.startswith('tie'):
            rune['y']=52;ally['x']=me['x'];ally['y']=72
            if condition=='tie-loser':ally['id']=1
        obs=dict(tick=100,game_version=37,self=me,play_west_max=52,play_east_min=76,
                 visible=dict(pudges=[me,enemy]+([] if condition=='alone' else [ally]),hooks=[],runes=[rune],props=[]),
                 ally_ping=None,rune_next=dict(soon=0,x=-1,y=-1))
        bots=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in [parent,candidate]]
        answers=[p.choose_action(copy.deepcopy(obs)) for p in bots]
        changed=verify_decision(obs,*answers,bots[0],owner_only=True)
        expected=condition in ('far','low','hooked','rot','enemybank','tie-winner')
        # Dead/absent sole ally disables the override. Cooldown retains ownership.
        assert changed==expected,(team,condition,answers)
        assert existing_state(bots[0])==existing_state(bots[1])
        rows.append(dict(team=team,condition=condition,changed=changed,expected=expected))
    (study/'verification/ownership.json').write_text(json.dumps(rows,indent=2)+'\n')
    return dict(cases=len(rows),failures=0)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path)
    p.add_argument('--owner',action='store_true');a=p.parse_args()
    print(json.dumps(verify(a.study,a.owner)))
    if a.owner:print(json.dumps(verify_ownership(a.study)))
