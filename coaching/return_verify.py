"""Independent action-level geometry and priority checks for return steering."""
import argparse
import copy
import itertools
import json
import math
from pathlib import Path
from .session_common import load, unit, existing_state


def endpoint(obs):
    me=obs['self'];units=obs['visible']['pudges']
    if not me['alive'] or me['layer']!=me['team'] or not any(p['alive'] and p['team']==me['team'] and p['id']!=me['id'] for p in units):return None
    heads=[h for h in obs['visible']['hooks'] if h['owner_id']==me['id'] and not h['flying'] and h['victim']==0]
    if not heads:return None
    h=heads[0];span=me['x']-h['x']
    if abs(span)<2 or span*(1 if me['team']==0 else -1)>=0:return None
    choices=[]
    for p in units:
        if not p['alive'] or p['team']==me['team'] or p['shield']:continue
        progress=(p['x']-h['x'])/span
        if .2-1e-9<=progress<=.85+1e-9:
            # Solve collinearity at the owner's x, independently of controller code.
            y=(p['y']*span-h['y']*(me['x']-p['x']))/(p['x']-h['x'])
            if 16<=y<=111 and abs(y-me['y'])<=8+1e-9:choices.append((abs(y-me['y']),p['id'],y))
    return [me['x'],min(choices)[2]] if choices else None


def verify_decision(obs,parent,candidate):
    if parent==candidate:return False
    expected=endpoint(obs);me=obs['self']
    assert expected is not None,'Return change outside declared geometry'
    assert not me['hooked'] and not any(k in parent for k in ('blink_to','attack_target')),'Urgent action masked'
    assert {k:v for k,v in parent.items() if k!='walk_to'}=={k:v for k,v in candidate.items() if k!='walk_to'},'Non-walking action leak'
    assert math.dist(candidate.get('walk_to',[-1000,-1000]),expected)<1e-7,'Wrong intercept destination'
    hold=obs['play_west_max']-16 if me['team']==0 else obs['play_east_min']+16
    assert abs(parent.get('walk_to',[-1000])[0]-hold)<1e-7,'Overrode non-fishing movement'
    return True


def verify(root):
    mods=[load(root/f,'return_probe_'+str(i)) for i,f in enumerate(['baseline.py','candidate.py','candidate-repeat.py'])]
    rows=[];failures=[];repeat_disagreements=0
    cases=itertools.product((0,1),(.19,.2,.5,.85,.86),(-8.1,-8.,0.,8.,8.1),('normal','outbound','carrying','no-ally','recover','shop','ward-trip','threat','rescue'))
    for i,(team,fraction,shift,state) in enumerate(cases):
        me=unit(1,team,36 if team==0 else 92,40);me['hook_ready']=False
        h=dict(owner_id=1,team=team,x=92 if team==0 else 36,y=40,victim=0,flying=False,lightning=False)
        enemy=unit(4,1-team,h['x']+(me['x']-h['x'])*fraction,40+shift*fraction)
        ally=unit(2,team,20 if team==0 else 108,90)
        hooks=[h];units=[me,ally,enemy]
        if state=='outbound':h['flying']=True
        if state=='carrying':h['victim']=4;enemy['hooked']=True
        if state=='no-ally':units.remove(ally)
        if state=='recover':me['hp']=300
        if state=='shop':me['gold']=12
        if state=='ward-trip':me['item_ranks'][4]=1
        if state=='threat':hooks.append(dict(owner_id=4,team=1-team,x=me['x']+4,y=40,victim=0,flying=True,lightning=False))
        obs=dict(tick=100,game_version=37,self=me,play_west_max=52,play_east_min=76,visible=dict(pudges=units,hooks=hooks,runes=[],props=[]),ally_ping=None,rune_next=dict(soon=0,x=-1,y=-1))
        bots=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in mods]
        if state=='rescue':
            for b in bots:b.rescue_until=110
        answers=[b.choose_action(copy.deepcopy(obs)) for b in bots]
        repeat_disagreements+=answers[1]!=answers[2]
        try:
            changed=verify_decision(obs,answers[0],answers[1])
            assert answers[1]==answers[2],'Repeat compile drift'
            assert existing_state(bots[0])==existing_state(bots[1]),'Memory leak'
            if state!='normal':assert answers[0]==answers[1],'Priority or phase leakage'
            if state=='normal' and endpoint(obs) is not None:assert math.dist(answers[1]['walk_to'],endpoint(obs))<1e-7,'Coverage'
        except AssertionError as e:
            failures.append(dict(case=i,state=state,fraction=fraction,shift=shift,error=str(e),actions=answers));changed=answers[0]!=answers[1]
        rows.append(dict(case=i,team=team,fraction=fraction,shift=shift,state=state,parent=answers[0],candidate=answers[1],changed=changed))
    out=root/'verification';out.mkdir(exist_ok=True)
    (out/'decision-table.json').write_text(json.dumps(rows,indent=2)+'\n')
    result=dict(cases=len(rows),changed=sum(r['changed'] for r in rows),failures=failures,
                scoped_lift_agreement=1-len(failures)/len(rows),residual_fraction=len(failures)/len(rows),candidate_agreement=1-repeat_disagreements/len(rows),
                scope='Finite geometric, phase and competing-movement partitions. Contact timing and full-policy semantics are not lifted.')
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    (out/'lifted.ir.md').write_text(f'''# Empirical return-steering lift

## [lift-return-01] Idle return steering

Layer: Strategy.

Observed {result['changed']} changed destinations in {len(rows)} probes.
Changed movement aligns the returning hook and observed enemy with the owner's
new destination. Tested higher-priority movements and non-walking channels
retain the parent's behavior. No claim of successful future contact follows.

Provenance: Executed action table, not compiler comments.

Evidence: Scoped agreement {result['scoped_lift_agreement']}; residual
{result['residual_fraction']}; n={len(rows)} deterministic probes. Unmeasured
continuous cases, belief calibration and other policy layers remain residuals.
''')
    assert not failures,failures[:3]
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('study',type=Path)
    print(json.dumps(verify(p.parse_args().study)))
