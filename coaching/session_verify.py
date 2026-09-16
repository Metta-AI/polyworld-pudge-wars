"""Probe and empirically lift the coaching priority projection independently."""
import argparse
import copy
import itertools
import json
import math
from pathlib import Path
from .session_common import load, unit, existing_state


def followup(obs):
    me = obs['self']
    enemies = sorted((p for p in obs['visible']['pudges']
                      if p['alive'] and p['team'] != me['team'] and not p['shield']),
                     key=lambda p: math.dist([p['x'], p['y']], [me['x'], me['y']]))
    held = next((p for p in enemies if p['hooked']), None)
    if held is None:
        return None
    chains = {h['victim']: h for h in obs['visible']['hooks'] if h['victim']}
    chain = chains.get(held['id'])
    if chain is None or chain['team'] != me['team'] or chain['owner_id'] == me['id']:
        return None
    owner = next((p for p in obs['visible']['pudges'] if p['alive'] and p['id'] == chain['owner_id']), held)
    return [max(8., min(119., (held[k] + owner[k])/2)) for k in ('x', 'y')]


def verify_decision(obs, parent, candidate):
    expected = followup(obs)
    if parent == candidate:
        return False
    assert obs['self']['alive'] and obs['self']['hook_ready'] and not obs['self']['hooked']
    assert expected is not None, 'Change outside teammate-held condition'
    assert {k:v for k,v in parent.items() if k != 'hook_to'} == {k:v for k,v in candidate.items() if k != 'hook_to'}, 'Non-hook action leak'
    assert candidate.get('hook_to') == expected, 'Wrong follow-up skill target'
    return True


def verify(root):
    mods = [load(root/f, 'coaching_probe_'+str(i)) for i,f in enumerate(['baseline.py','candidate.py','candidate-repeat.py'])]
    rows=[]; failures=[]
    cases=itertools.product((0,1), ('ally','enemy','self','unknown'),
                            ('normal','dead','hooked','no-hook','rescue','shielded-target'),
                            (12.,20.,20.1,32.), (False,True), (False,True))
    for index,(team,owner_kind,state,gap,blocked,threatened) in enumerate(cases):
        direction=1 if team==0 else -1
        me=unit(1,team,36 if team==0 else 92,40)
        owner=unit(2,team,me['x']+direction*4,80)
        near=unit(4,1-team,me['x']+direction*gap,40)
        held=unit(5,1-team,me['x']+direction*30,68);held['hooked']=True
        hooks=[]
        if owner_kind!='unknown':
            hooks.append(dict(owner_id=1 if owner_kind=='self' else 2 if owner_kind=='ally' else 4,
                              team=team if owner_kind in ('ally','self') else 1-team,
                              x=held['x'],y=held['y'],victim=5,flying=False,lightning=False))
        if threatened:hooks.append(dict(owner_id=6,team=1-team,x=me['x']+direction*12,y=me['y']+2,victim=0,flying=True,lightning=False))
        if state=='dead':me['alive']=False
        if state=='hooked':me['hooked']=True
        if state=='no-hook':me['hook_ready']=False
        if state=='shielded-target':held['shield']=20
        if state=='rescue':
            owner['hooked']=True;hooks.append(dict(owner_id=6,team=1-team,x=owner['x'],y=owner['y'],victim=2,flying=False,lightning=False))
        units=[me,owner,near,held]
        if blocked:units.append(unit(3,team,me['x']+direction*8,56))
        obs=dict(tick=100,game_version=37,self=me,play_west_max=52,play_east_min=76,
                 visible=dict(pudges=units,hooks=hooks,runes=[],props=[]),ally_ping=None,rune_next=dict(soon=0,x=-1,y=-1))
        bots=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in mods]
        answers=[b.choose_action(copy.deepcopy(obs)) for b in bots]
        try:
            changed=verify_decision(obs,answers[0],answers[1])
            assert answers[1]==answers[2], 'Candidate disagreement'
            assert existing_state(bots[0])==existing_state(bots[1]), 'Memory leak'
            # Clear, ordinary competing close shots must yield to the held target.
            if owner_kind=='ally' and state=='normal' and not blocked and not threatened:
                assert answers[1].get('hook_to')==followup(obs), 'Coverage failure'
        except AssertionError as e:
            failures.append(dict(case=index,error=str(e),obs=obs,answers=answers));changed=answers[0]!=answers[1]
        rows.append(dict(case=index,team=team,captor=owner_kind,state=state,gap=gap,blocked=blocked,
                         threat=threatened,parent=answers[0],candidate=answers[1],changed=changed))
    output=root/'verification';output.mkdir(exist_ok=True)
    (output/'decision-table.json').write_text(json.dumps(rows,indent=2)+'\n')
    report=dict(cases=len(rows),changed=sum(r['changed'] for r in rows),failures=failures,
                scoped_lift_agreement=1-len(failures)/len(rows),residual_fraction=len(failures)/len(rows),
                candidate_agreement=1.,scope='Hook selection in declared finite partitions; full-policy semantic residual unmeasured. Identical deterministic compiles do not measure prose ambiguity.')
    (output/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    (output/'lifted.ir.md').write_text(f'''# Empirical lift: coaching follow-up priority

## [lift-followup-01] Observed follow-up priority

Layer: Strategy.

In {len(rows)} probes, {report['changed']} decisions differed from the parent.
Changed decisions selected the midpoint toward the visible allied reeler;
all non-hook action channels and pre-existing memory matched the parent.
Observed changes were confined to a living, available caster and a visible
enemy held by a different teammate. Clear ordinary competition probes selected
the follow-up target before the nearby unheld target.

Provenance: Executed parent/candidate decisions in decision-table.json.

Evidence: Scoped agreement {report['scoped_lift_agreement']}; residual
{report['residual_fraction']}; n={len(rows)} deterministic probes, not independent
match outcomes. Goals and unprobed continuous states are not empirically lifted.
''')
    assert not failures, failures[:2]
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('study',type=Path)
    print(json.dumps(verify(p.parse_args().study)))
