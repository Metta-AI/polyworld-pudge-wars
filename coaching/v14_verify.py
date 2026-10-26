"""Independent boundary probes for the v14 Blink initiation projection."""
import argparse
import copy
import csv
import hashlib
import importlib.util
import itertools
import json
import math
from pathlib import Path
import sys


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def unit(pid, team, x, y):
    return dict(id=pid,team=team,x=x,y=y,hp=1200,max_hp=1200,alive=True,hooked=False,
                shield=0,hook_ready=True,blink_ready=True,rot=False,layer=team,gold=0,
                points=0,in_shop=False,home_x=25 if team==0 else 103,home_y=40,
                upgrades=[0,0,0,0],item_ranks=[0,0,0,0,0],ward_restock=100,buff=0)


def existing_state(policy):
    return {k:v for k,v in vars(policy).items() if k not in ('_hook_history','events')}


def verify(oracle, candidate, repeated, output):
    output.mkdir(parents=True,exist_ok=True)
    a=load(oracle,'probe_oracle');b=load(candidate,'probe_candidate');c=load(repeated,'probe_repeat')
    rows=[];changed=0;masked=0;counts={};failures=[]
    # These partitions include both sides of each changed threshold and unknown history.
    cases=itertools.product((0,1),(10.,21.9,22.,22.1),('toward','away','miss-9.9','miss-10','miss-10.1','stationary','teleport','unknown','stale'),(False,True),('normal','dead','hooked','river','enemy','fountain'),(1,3),(False,True))
    for index,(team,gap,motion,ready,condition,n,second_incoming) in enumerate(cases):
        policies=[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in (a,b,c)]
        me=unit(1 if team==0 else 4,team,36 if team==0 else 92,40)
        me['blink_ready']=ready
        if condition=='dead':me['alive']=False
        if condition=='hooked':me['hooked']=True
        if condition=='river':me['layer']=2;me['x']=64
        if condition=='enemy':me['layer']=1-team;me['x']=92 if team==0 else 36
        if condition=='fountain':me['layer']=1-team;me['x']=71 if team==0 else 56;me['y']=64
        direction=1 if team==0 else -1
        dx=direction*gap
        if motion.startswith('miss-'):
            miss=float(motion.split('-')[1]);vx=-direction*math.sqrt(max(0,1-(min(miss/gap,1))**2));vy=min(miss/gap,1)
        else:vx,vy=(-direction,0) if motion=='toward' else (direction,0)
        if motion=='stationary':vx=vy=0
        if motion=='teleport':vx*=10
        hook=dict(owner_id=10,team=1-team,x=me['x']+dx,y=me['y'],victim=0,flying=True,lightning=False)
        other=dict(owner_id=11,team=1-team,x=me['x']+direction*12,y=me['y'],victim=0,flying=True,lightning=False)
        allies=[unit(me['id']+i+1,team,me['x']-direction*12,85+i*12) for i in range(n-1)]
        obs=dict(tick=101,game_version=37,self=me,play_west_max=52,play_east_min=76,
                 visible=dict(pudges=[me,*allies],hooks=[hook]+([other] if second_incoming else []),runes=[],props=[]),ally_ping=None,rune_next=dict(soon=0,x=-1,y=-1))
        first=copy.deepcopy(obs);first['tick']=99 if motion=='stale' else 100
        first['visible']['hooks'][0]['x']-=vx;first['visible']['hooks'][0]['y']-=vy
        if motion=='unknown':first['visible']['hooks']=first['visible']['hooks'][1:]
        if second_incoming:
            # The second projectile must keep defensive Blink enabled.
            for h in first['visible']['hooks']:
                if h['owner_id']==11:h['x']+=direction
        for policy in policies:policy.choose_action(copy.deepcopy(first))
        answers=[policy.choose_action(copy.deepcopy(obs)) for policy in policies]
        # Independent geometry uses cross product distance, not library closest-point code.
        known=motion not in ('unknown','stale','stationary','teleport')
        speed=math.hypot(vx,vy)
        dot=(-dx)*vx
        miss=abs(dx*vy)/speed if speed else 0
        danger=(not known) or (dot>0 and miss<=10+1e-10)
        danger = (gap<=22 and danger) or second_incoming
        eligible=condition in ('normal','enemy') and ready and gap<=22
        suppress=eligible and not danger and 'blink_to' in answers[0]
        same=answers[0]==answers[1]
        if not same and not suppress:failures.append(dict(case=index,kind='isolation',inputs=[team,gap,motion,ready,condition,n,second_incoming],actions=answers[:2]))
        if suppress and 'blink_to' in answers[1]:failures.append(dict(case=index,kind='coverage'))
        if answers[1]!=answers[2]:failures.append(dict(case=index,kind='candidate_disagreement'))
        if existing_state(policies[0])!=existing_state(policies[1]):failures.append(dict(case=index,kind='state_leak'))
        changed+=not same
        masked+=not eligible
        label='unknown' if not known else 'incoming' if danger else 'clear'
        counts[label]=counts.get(label,0)+1
        rows.append(dict(case=index,team=team,gap=gap,motion=motion,ready=ready,condition=condition,n=n,second=second_incoming,parent_blink='blink_to' in answers[0],candidate_blink='blink_to' in answers[1],changed=not same,expected_suppression=suppress))
    with (output/'decision-table.csv').open('w') as f:
        writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    result=dict(cases=len(rows),changed=changed,masked=masked,failures=failures,candidate_agreement=1-sum(f['kind']=='candidate_disagreement' for f in failures)/len(rows),lift_agreement=1-sum(f['kind'] in ('coverage','isolation') for f in failures)/len(rows),residual_fraction=sum(f['kind'] in ('coverage','isolation') for f in failures)/len(rows),residual_scope='Enumerated defensive-Blink initiation partitions only. Other strategy, goals, future opponent behavior and continuous trajectories are not empirically lifted by this projection.',categories=counts)
    (output/'verification.json').write_text(json.dumps(result,indent=2)+'\n')
    (output/'lifted.md').write_text(f'''# Empirically lifted Blink initiation\n\nAcross {len(rows)} enumerated boundary cases, candidate withheld Blink in {changed} cases.\nUnknown motion and any second incoming hook preserve defense. River exit is protected.\n\nAgreement: {result['lift_agreement']:.6f}; unexplained fraction: {result['residual_fraction']:.6f}.\nScope: {result['residual_scope']}\nThe goal rationale cannot be recovered from emitted actions.\n''')
    assert not failures,failures[:3]
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path);args=p.parse_args()
    r=verify(args.study/'baseline.py',args.study/'candidate.py',args.study/'candidate-repeat.py',args.study/'verification')
    print(json.dumps(r))
