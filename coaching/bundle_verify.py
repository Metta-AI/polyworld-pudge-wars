"""Independent reference and multi-step contracts for the complete E06 policy."""
import argparse
from collections import Counter
import copy
import itertools
import json
import math
from pathlib import Path
import sys
import types

from .scrum_verify import disk_hit as quadratic_disk_hit, equivalent, observation
from .session_common import load, unit, existing_state


def disk_hit(start, end):
    # The versioned primitive uses a raw binary64 closest-point inequality.
    # Within 1e-9 of the boundary, reconcile that numerical binding explicitly
    # rather than claiming that exact real-number tangency can be recovered.
    dx,dy=end[0]-start[0],end[1]-start[1]
    norm=dx*dx+dy*dy
    t=max(0.,min(1.,((64.5-start[0])*dx+(64.5-start[1])*dy)/norm)) if norm else 0.
    stable_gap=math.hypot(64.5-(start[0]+t*dx),64.5-(start[1]+t*dy))
    if abs(stable_gap-3.5)<=1e-9:
        return math.hypot(64.5-start[0]-t*dx,64.5-start[1]-t*dy)<=3.5
    # Include a boundary endpoint directly: a quadratic root at t=1 can round
    # above one even when a rune lies exactly on the fountain's outer lip.
    if (end[0]-64.5)**2+(end[1]-64.5)**2 <= 3.5**2:
        return True
    return quadratic_disk_hit(start,end)


def reference_pairs(me, players, reach):
    pairs=[]
    for ally in players:
        if not ally['alive'] or ally['team']!=me['team'] or ally['id']==me['id'] or ally['shield'] or ally['hooked']:
            continue
        for enemy in players:
            if (not enemy['alive'] or enemy['team']==me['team'] or enemy['shield'] or enemy['hooked']
                    or enemy['layer']!=ally['layer']):continue
            if math.dist((ally['x'],ally['y']),(enemy['x'],enemy['y']))>5.5:continue
            aim=[(ally[k]+enemy[k])*.5 for k in ('x','y')]
            if math.dist((me['x'],me['y']),aim)<=reach:
                pairs.append((ally['hp']/ally['max_hp'],math.dist((me['x'],me['y']),(ally['x'],ally['y'])),ally['id'],enemy['id'],aim))
    return sorted(pairs)


def reference_endpoint(obs, vx, vy):
    me=obs['self'];x,y=me['x'],me['y']
    left,right=(8.,obs['play_west_max']-1.) if me['team']==0 else (obs['play_east_min']+1.,119.)
    if x<left or x>right or y<16 or y>111:return None
    limits=[8.]
    if vx:limits.append(((right if vx>0 else left)-x)/vx)
    if vy:limits.append(((111. if vy>0 else 16.)-y)/vy)
    span=min(limits)
    if span<.25:return None
    return [x+span*vx,y+span*vy],span


def reference_curve(obs, action, state, recovering, hold_until, counts):
    me=obs['self'];now=obs['tick'];visible=obs['visible']
    own=next((h for h in visible['hooks'] if h['owner_id']==me['id']),None)
    if not me['alive'] or me['hooked'] or me['layer']!=me['team'] or recovering or now<hold_until:
        return action,None
    if any(k in action for k in ('blink_to','attack_target')):return action,None
    if own and any(p['alive'] and p['team']==me['team'] and p['id']==own['victim'] for p in visible['pudges']):
        return action,None
    for h in visible['hooks']:
        if h['team']!=me['team'] and h['flying'] and math.hypot(h['x']-me['x'],h['y']-me['y'])<=22:
            return action,None
    for p in visible['pudges']:
        if p['alive'] and p['id']!=me['id'] and p['rot'] and math.hypot(p['x']-me['x'],p['y']-me['y'])<=8:
            return action,None
    if state and not own and (state[3] or now>state[0]+12):state=None
    if state is None:
        if own or 'hook_to' not in action:return action,None
        dx=action['hook_to'][0]-me['x'];dy=action['hook_to'][1]-me['y'];norm=math.hypot(dx,dy)
        if norm<.01:return action,None
        targets=[p for p in visible['pudges'] if p['alive'] and p['team']!=me['team'] and not p['shield']]
        targets.sort(key=lambda p:(math.hypot(p['x']-me['x'],p['y']-me['y']),p['id']))
        guide=(targets[0]['x'],targets[0]['y']) if targets else (me['x'],63.5)
        options=[]
        for sign in [1,-1]:
            vx,vy=(-dy/norm)*sign,(dx/norm)*sign
            point=reference_endpoint(obs,vx,vy)
            if point:options.append((-point[1],math.dist(point[0],guide),-sign,vx,vy))
        if not options:return action,None
        chosen=min(options);state=(now,chosen[3],chosen[4],False);counts['curve_starts']+=1
    born,vx,vy,seen=state
    step=reference_endpoint(obs,vx,vy)
    if step is None:
        vx,vy=-vx,-vy;step=reference_endpoint(obs,vx,vy)
    if step is None:return action,None
    counts['curve_steps']+=1
    if own:counts['curve_flying_steps' if own['flying'] else 'curve_return_steps']+=1
    result=dict(action);result['walk_to']=step[0]
    return result,(born,vx,vy,seen or own is not None)


def reference_module(oracle, name):
    code=oracle.read_text()
    anchor='            for ally in allies:\n'
    code=code.replace(anchor,'''            if disk_hit(start, end):
                BUNDLE_COUNTS["fountain_rejections"] += 1
                return False
'''+anchor)
    anchor='        if target is not None and distance(me, target) <= 20 and not river:\n'
    code=code.replace(anchor,'''        if free and not foreign_rot and "hook_to" not in action:
            choices = reference_pairs(me, obs["visible"]["pudges"], reach)
            BUNDLE_COUNTS["engagement_pairs"] += len(choices)
            for choice in choices:
                if throw(choice[4], choice[2]):
                    BUNDLE_COUNTS["engagement_requests"] += 1
                    break
'''+anchor)
    code+='''
Core = BasePolicy
@dataclass
class BasePolicy(Core):
    curve_state: tuple | None = None
    def reset(self):
        super().reset()
        self.curve_state = None
    def choose_action(self, obs):
        action = super().choose_action(obs)
        action, self.curve_state = reference_curve(obs, action, self.curve_state, self.recovering, self.rescue_until, BUNDLE_COUNTS)
        return action
'''
    module=types.ModuleType(name);sys.modules[name]=module
    module.__dict__.update(disk_hit=disk_hit,reference_pairs=reference_pairs,reference_curve=reference_curve,BUNDLE_COUNTS=Counter())
    exec(compile(code,str(oracle)+':bundle-reference','exec'),module.__dict__)
    return module


def check(obs, baseline, candidate, reference, regenerated, variant='bundle'):
    parent=baseline.choose_action(obs)
    action=candidate.choose_action(obs);expected=reference.choose_action(obs);repeated=regenerated.choose_action(obs)
    assert equivalent(action,expected),('semantic action mismatch',obs['tick'],action,expected)
    assert equivalent(existing_state(candidate),existing_state(reference)),('semantic memory mismatch',obs['tick'])
    assert action==repeated and vars(candidate)==vars(regenerated),'round-trip mismatch'
    return parent,action


def verify(root):
    assert disk_hit([34.797,32.259],[64.5,61.0]), 'Boundary endpoint regression'
    assert not disk_hit([36.494,31.243],[64.5,61.0]), 'Raw binary64 boundary convention'
    modules=[load(root/'baseline.py','bundle_probe_parent'),load(root/'candidate.py','bundle_probe_candidate'),
             reference_module(root/'baseline.py','bundle_probe_reference'),load(root/'regenerated.py','bundle_probe_regenerated')]
    def bots():return [m.BasePolicy(heal_allies=True,spread_fishing=True) for m in modules]
    rows=[]
    states=('normal','dead','hooked','cooldown','low','full-ally','missing-120','shielded-ally',
            'shielded-enemy','wrong-layer','no-ally','hidden-enemy','caught','rescue','threat','close')
    for side,y,gap,state,blocked in itertools.product((0,1),(40.,60.99,61.,61.01,64.5,68.,68.01),(5.5,5.51),states,(False,True)):
        obs=observation(side,y,gap,state,blocked);policies=bots()
        a,b=check(obs,*policies)
        if state in ('normal','full-ally') and gap==5.5 and y==40 and not blocked:
            pair=reference_pairs(obs['self'],obs['visible']['pudges'],60)[0]
            assert equivalent(b.get('hook_to'),pair[4]),'Combined centroid rule not exposed'
            assert policies[1].curve_state is not None,'Centroid cast did not start CurveHook'
            dx,dy=b['hook_to'][0]-obs['self']['x'],b['hook_to'][1]-obs['self']['y']
            wx,wy=b['walk_to'][0]-obs['self']['x'],b['walk_to'][1]-obs['self']['y']
            assert abs(dx*wx+dy*wy)<1e-7,'Curve walk must be perpendicular'
        if state in ('dead','hooked','cooldown'):assert a==b
        rows.append(dict(side=side,y=y,gap=gap,state=state,blocked=blocked,parent=a,candidate=b))
    sequence_cases=0
    for side,diagonal,interrupt in itertools.product((0,1),(False,True),('none','danger','ally-victim','death','recovery','rollback','edge')):
        policies=bots();obs=observation(side,40.,5.,'no-ally')
        if diagonal:obs['visible']['pudges'][1]['y']=55
        a,b=check(obs,*policies);assert policies[1].curve_state is not None
        launch=policies[1].curve_state
        for age in (1,2,3):
            frame=copy.deepcopy(obs);frame['tick']+=age;frame['self']['hook_ready']=False
            own=dict(owner_id=1,team=side,x=64,y=45,victim=0,flying=age==1)
            frame['visible']['hooks']=[own] if age<3 else []
            if age==2:
                if interrupt=='danger':frame['visible']['hooks'].append(dict(owner_id=4,team=1-side,x=frame['self']['x']+5,y=40,victim=0,flying=True))
                if interrupt=='ally-victim':
                    frame['visible']['pudges'].append(unit(2,side,40,80));own['victim']=2
                if interrupt=='death':frame['self']['alive']=False
                if interrupt=='recovery':frame['self']['hp']=200
                if interrupt=='rollback':frame['tick']=1
                if interrupt=='edge':frame['self']['y']=111 if launch[2]>0 else 16
            a,b=check(frame,*policies);sequence_cases+=1
            if age==2 and interrupt in ('danger','ally-victim','death','recovery','rollback'):
                assert policies[1].curve_state is None,('Curve interruption failed',interrupt)
            if age==3:assert policies[1].curve_state is None,'Curve did not end with hook'
            rows.append(dict(side=side,state=interrupt,age=age,parent=a,candidate=b))
    # A new blind request through the middle is removed by the all-throw guard.
    for side in (0,1):
        obs=observation(side,64.5,state='no-ally');obs['visible']['pudges']=[obs['self']]
        a,b=check(obs,*bots());assert 'hook_to' in a and 'hook_to' not in b
        rows.append(dict(side=side,state='blind-middle',parent=a,candidate=b))
    # The real engine roots a nine-tick cast windup before any hook is visible.
    for side in (0,1):
        policies=bots();obs=observation(side,40.,state='no-ally')
        check(obs,*policies)
        for age in range(1,12):
            frame=copy.deepcopy(obs);frame['tick']+=age;frame['self']['hook_ready']=False
            if age in (9,10):
                frame['visible']['hooks']=[dict(owner_id=1,team=side,x=64,y=40,victim=0,flying=age==9)]
            a,b=check(frame,*policies);sequence_cases+=1
            assert (policies[1].curve_state is not None)==(age<=10),'Native windup lifecycle failure'
            rows.append(dict(side=side,state='nine-tick-windup',age=age,parent=a,candidate=b))
    output=root/'verification';output.mkdir()
    (output/'decisions.json').write_text(json.dumps(rows,indent=2)+'\n')
    counts=modules[1].BUNDLE_COUNTS
    assert all(counts[k]>0 for k in ('engagement_requests','fountain_rejections','curve_starts','curve_flying_steps','curve_return_steps'))
    report=dict(cases=len(rows),sequence_steps=sequence_cases,changed=sum(x['parent']!=x['candidate'] for x in rows),
                scoped_semantic_mismatches=0,roundtrip_mismatches=0,mechanisms=counts,
                scope='Whole-package actions and memory on authored states and lifecycle sequences; no claim that goals or all inherited prose are empirically recovered.')
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path)
    print(json.dumps(verify(p.parse_args().study)))
