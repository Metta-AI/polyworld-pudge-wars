"""Native wall/blocker regression scenes for the occupied-route IR skill."""
import argparse
from dataclasses import replace
import json
import math
from pathlib import Path
import subprocess

from .evaluate import load, prepare
from .ir import Program, Step, binding_hash, render
from .spatial import SpatialMetrics


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--runner',type=Path,default=Path('tmp/coaching/spatial_match'))
    args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=False)
    parent=Program('blocked_route_control',binding_hash(),(
        Step('STOP UNLESS','alive'),Step('DO','observe'),Step('DO','simple_movement')))
    candidate=replace(parent,name='blocked_route_detour',binding_version='pudge-skills-v2',
                      binding_hash=binding_hash('pudge-skills-v2'),steps=parent.steps+(Step('DO','clear_occupied_route'),))
    programs={}
    for name,program in [('parent',parent),('candidate',candidate)]:
        path=args.out/(name+'.policy.md');path.write_text(render(program))
        first,second=prepare(path,args.out/name)
        programs[name]=(load(first,name).Policy,load(second,name+'_regenerated').Policy)
    rows=[]
    for side in (0,1):
        slot=side*3
        positions=[(18,40),(24,43),(18,46),(110,40),(104,43),(110,46)]
        fixture=args.out/f'wall-{side}.json'
        fixture.write_text(json.dumps({'players':[dict(slot=i,x=x,y=y) for i,(x,y) in enumerate(positions)]}))
        for name,classes in programs.items():
            first,shadow=classes[0](),classes[1]()
            metrics=SpatialMetrics();trajectory=[];first_arrival=None
            goal=[47 if side==0 else 81,51]
            process=subprocess.Popen([str(args.runner.resolve()),'2026','3','384','30',str(fixture)],
                                     stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
            try:
                for line in process.stdout:
                    observations=json.loads(line)
                    if isinstance(observations,dict):break
                    obs=observations[slot]
                    action=first.choose_action(obs)
                    assert action==shadow.choose_action(obs) and first.state.__dict__==shadow.state.__dict__
                    actions=[{} for _ in observations];actions[slot]=action
                    metrics.observe(obs,action)
                    if obs['tick']%8==0:trajectory.append([obs['tick'],obs['self']['x'],obs['self']['y'],action.get('walk_to')])
                    if first_arrival is None and math.dist([obs['self']['x'],obs['self']['y']],goal)<3:
                        first_arrival=obs['tick']
                    process.stdin.write(json.dumps(actions)+'\n');process.stdin.flush()
                process.wait(timeout=10)
                assert process.returncode==0,process.stderr.read()
            finally:
                if process.poll() is None:process.kill();process.wait()
                process.stdin.close();process.stdout.close();process.stderr.close()
            row=dict(arm=name,side=side,first_arrival_tick=first_arrival,
                     distance_to_goal=math.dist(trajectory[-1][1:3],goal),
                     roundtrip_decisions=384,spatial=metrics.report(),trajectory=trajectory)
            rows.append(row)
    (args.out/'report.json').write_text(json.dumps(rows,indent=2)+'\n')
    print(json.dumps([{k:v for k,v in r.items() if k!='trajectory'} for r in rows],indent=2))


if __name__=='__main__':main()
