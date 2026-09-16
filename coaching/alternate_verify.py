"""Action probes for selecting another visible enemy after a blocked shot."""
import argparse
import copy
import itertools
import json
import math
from pathlib import Path
from .session_common import load, unit, existing_state


def verify_decision(obs,parent,candidate,policy):
    if parent==candidate:return False
    me=obs['self']
    assert me['alive'] and me['hook_ready'] and not me['hooked']
    assert {k:v for k,v in parent.items() if k!='hook_to'}=={k:v for k,v in candidate.items() if k!='hook_to'},'Non-hook channel leak'
    assert 'hook_to' not in parent or parent['hook_to'] in [[r['x'],r['y']] for r in obs['visible']['runes']], 'Earlier combat/support hook overridden'
    enemies=sorted((p for p in obs['visible']['pudges'] if p['alive'] and p['team']!=me['team'] and not p['shield']),key=lambda p:math.hypot(p['x']-me['x'],p['y']-me['y']))
    levels=me['upgrades'].copy()
    for kind in parent.get('buy_upgrade',[]):levels[kind]+=1
    options=[]
    for target in enemies[1:]:
        vx,vy=policy.velocity(target);scale=max(abs(me['x']-target['x']),abs(me['y']-target['y']))/(30+levels[2])
        options.append([max(8.,min(119.,target['x']+vx*scale)),max(8.,min(119.,target['y']+vy*scale))])
    assert any(math.dist(candidate.get('hook_to',[-1000,-1000]),aim)<1e-7 for aim in options), 'Changed hook not from an alternate enemy skill'
    return True


def verify(root):
    mods=[load(root/f,'alternate_probe_'+str(i)) for i,f in enumerate(['baseline.py','candidate.py','candidate-repeat.py'])]
    rows=[];failures=[];disagreements=0
    cases=itertools.product((0,1),(50,70,84),('normal','dead','hooked','no-hook','heal','rescue','counter','primary-shield'),(False,True),('alive','shield','dead','blocked'),(False,True))
    for i,(team,gap,state,blocked,secondary_state,rune) in enumerate(cases):
        direction=1 if team==0 else -1;me=unit(1,team,36 if team==0 else 92,32);me['blink_ready']=False;me['upgrades'][1]=5
        ally=unit(2,team,me['x']+direction*16,32 if blocked else 96)
        primary=unit(4,1-team,me['x']+direction*44,32)
        second=unit(5,1-team,me['x']+direction*gap,68)
        units=[me,ally,primary,second];hooks=[]
        if secondary_state=='shield':second['shield']=20
        if secondary_state=='dead':second['alive']=False
        if secondary_state=='blocked':units.append(unit(3,team,me['x']+direction*12,32+432/gap))
        if state=='dead':me['alive']=False
        if state=='hooked':me['hooked']=True
        if state=='no-hook':me['hook_ready']=False
        if state=='heal':ally['hp']=900
        if state=='primary-shield':primary['shield']=20
        if state=='counter':hooks.append(dict(owner_id=6,team=1-team,x=me['x']+direction*4,y=36,victim=0,flying=True,lightning=False))
        obs=dict(tick=100,game_version=37,self=me,play_west_max=52,play_east_min=76,
                 visible=dict(pudges=units,hooks=hooks,runes=[dict(x=64,y=20)] if rune else [],props=[]),ally_ping=None,rune_next=dict(soon=0,x=-1,y=-1))
        bots=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in mods]
        if state=='rescue':
            for b in bots:b.rescue_until=110
        answers=[b.choose_action(copy.deepcopy(obs)) for b in bots]
        disagreements+=answers[1]!=answers[2]
        try:
            changed=verify_decision(obs,answers[0],answers[1],bots[0])
            assert answers[1]==answers[2],'Candidate disagreement'
            assert existing_state(bots[0])==existing_state(bots[1]),'Memory leak'
            if state in ('dead','hooked','no-hook','rescue','counter','primary-shield') or not blocked or secondary_state!='alive' or gap==84:
                assert answers[0]==answers[1],'Isolation'
            if state=='normal' and blocked and secondary_state=='alive' and gap<84:
                assert answers[1].get('hook_to')==[second['x'],second['y']],'Coverage'
        except AssertionError as e:
            failures.append(dict(case=i,team=team,gap=gap,state=state,blocked=blocked,secondary=secondary_state,error=str(e),answers=answers));changed=answers[0]!=answers[1]
        rows.append(dict(case=i,team=team,gap=gap,state=state,blocked=blocked,secondary=secondary_state,rune=rune,parent=answers[0],candidate=answers[1],changed=changed))
    fixture=Path(__file__).parent/'policies/session-20260915/probes/alternate-rounding.json'
    if fixture.exists():
        r=json.loads(fixture.read_text());policy=mods[0].BasePolicy()
        policy.samples={int(k):tuple(v) for k,v in r['state']['samples'].items()}
        assert verify_decision(r['observation'],r['parent'],r['candidate'],policy)
        wrong=copy.deepcopy(r['candidate']);wrong['hook_to'][0]+=.01
        try:verify_decision(r['observation'],r['parent'],wrong,policy)
        except AssertionError:pass
        else:raise AssertionError('Tolerance admitted a materially different aim')
        rows.append(dict(case='recorded-rounding',parent=r['parent'],candidate=r['candidate'],changed=True))
    out=root/'verification';out.mkdir(exist_ok=True)
    (out/'decision-table.json').write_text(json.dumps(rows,indent=2)+'\n')
    result=dict(cases=len(rows),changed=sum(r['changed'] for r in rows),failures=failures,scoped_lift_agreement=1-len(failures)/len(rows),residual_fraction=len(failures)/len(rows),candidate_agreement=1-disagreements/len(rows),scope='Finite enemy visibility, availability, range, ally obstruction and priority partitions. Full-policy semantic residual remains unmeasured.')
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    (out/'lifted.ir.md').write_text(f'''# Empirical alternate-target lift

## [lift-alternate-01] Another enemy before a rune

Layer: Strategy.

In {len(rows)} probes, {result['changed']} decisions changed. The candidate
selected a second eligible enemy when the nearest path was blocked, including
when a rune was available. Tested earlier support/combat, cooldown, dead,
shielded and out-of-range cases preserved the parent's action channels.

Provenance: Executed decisions in decision-table.json.

Evidence: Scoped agreement {result['scoped_lift_agreement']}; residual
{result['residual_fraction']}; n={len(rows)} deterministic probes. This does
not establish contact success, future safety or unprobed policy semantics.
''')
    assert not failures,failures[:3]
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('study',type=Path)
    print(json.dumps(verify(p.parse_args().study)))
