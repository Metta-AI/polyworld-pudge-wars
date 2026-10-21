"""Seeded full-game comparison with per-decision isolation and state checks."""
import argparse
from concurrent.futures import ProcessPoolExecutor
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import random
import subprocess
import time
from .v14_verify import load, existing_state


def clear_corridor(obs, history):
    me=obs['self'];found=False
    for hook in obs['visible']['hooks']:
        dx=me['x']-hook['x'];dy=me['y']-hook['y']
        if hook['team']==me['team'] or not hook['flying'] or math.hypot(dx,dy)>22:continue
        found=True;old=history.get(hook['owner_id'])
        if old is None or old[0]!=obs['tick']-1:return False
        vx=hook['x']-old[1];vy=hook['y']-old[2];speed=math.hypot(vx,vy)
        if not .01<speed<8:return False
        if dx*vx+dy*vy>0 and abs(dx*vy-dy*vx)/speed<=10+1e-9:return False
    return found


def play(job):
    root=Path(job['study']);directory=root/job['stage']/f"{job['seed']}-{job['side']}";directory.mkdir(parents=True,exist_ok=False)
    mods=[load(root/'baseline.py','eval_oracle'),load(root/'candidate.py','eval_candidate')]
    side=job['side'];n=job.get('n',3)
    players=[mods[int(i//n==side)].BasePolicy(heal_allies=True,spread_fishing=True) for i in range(n*2)]
    shadows=[mods[0].BasePolicy(heal_allies=True,spread_fishing=True) for _ in range(n)]
    counts=Counter();start=time.monotonic();examples=[]
    with (directory/'engine.log').open('w') as err:
        proc=subprocess.Popen([str(root/'json_match'),str(job['seed']),str(n),'38400','30'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,text=True)
        try:
            for line in proc.stdout:
                observations=json.loads(line)
                if isinstance(observations,dict) and observations.get('final'):
                    result=observations;break
                actions=[]
                for slot,(bot,obs) in enumerate(zip(players,observations)):
                    if slot//n!=side:
                        actions.append(bot.choose_action(obs));continue
                    me=obs['self'];eligible=job['variant']=='blink' and me['alive'] and not me['hooked'] and me['layer']!=2 and me['blink_ready'] and clear_corridor(obs,bot._hook_history)
                    baseline=shadows[slot%n].choose_action(obs);action=bot.choose_action(obs)
                    assert existing_state(bot)==existing_state(shadows[slot%n]),('existing state leak',job,obs['tick'])
                    allowed=eligible and 'blink_to' in baseline and 'blink_to' not in action
                    if job['variant'] in ('rune', 'rune-owner'):
                        from .v14_rune_verify import verify_decision
                        allowed = verify_decision(obs, baseline, action, shadows[slot%n], job['variant']=='rune-owner')
                    # A clear hook cannot suppress an earlier fountain escape.
                    if action!=baseline and not allowed:
                        (directory/'leak.json').write_text(json.dumps({'obs':obs,'parent':baseline,'candidate':action},indent=2));raise AssertionError(('isolation',job,obs['tick']))
                    counts['checked_decisions']+=1;counts['changed_decisions']+=action!=baseline
                    counts['parent_blink_requests']+='blink_to' in baseline;counts['candidate_blink_requests']+='blink_to' in action
                    counts['clear_blink_withheld' if job['variant']=='blink' else 'rune_priority_changes']+=allowed and action!=baseline
                    if action!=baseline and len(examples)<4:examples.append({'tick':obs['tick'],'player':me['id'],'parent':baseline,'candidate':action})
                    for key,value in obs.get('accepted',{}).items():
                        if value is True:counts['accepted_'+key]+=1
                    actions.append(action)
                proc.stdin.write(json.dumps(actions,separators=(',',':'))+'\n');proc.stdin.flush()
            else:raise RuntimeError('No final result')
            proc.wait(timeout=10);assert proc.returncode==0
        finally:
            if proc.poll() is None:proc.kill();proc.wait()
    ours,theirs=result['score'][side],result['score'][1-side]
    row=job|dict(ours=ours,theirs=theirs,margin=ours-theirs,win=ours>theirs,draw=ours==theirs,seconds=round(time.monotonic()-start,2),counts=dict(counts),examples=examples,final=result)
    (directory/'result.json').write_text(json.dumps(row,indent=2)+'\n');print(json.dumps({k:row[k] for k in ('seed','side','ours','theirs','seconds')}),flush=True);return row


def summary(rows):
    groups={}
    for row in rows:groups.setdefault(row['seed'],[]).append(row)
    blocks=[sum(r['margin'] for r in group)/len(group) for group in groups.values()]
    rng=random.Random(9152026);draws=sorted(sum(rng.choices(blocks,k=len(blocks)))/len(blocks) for _ in range(10000))
    n=len(rows);wins=sum(r['win'] for r in rows);phat=wins/n;z=1.95996398454;den=1+z*z/n;center=(phat+z*z/(2*n))/den;span=z*math.sqrt(phat*(1-phat)/n+z*z/(4*n*n))/den
    counts=Counter()
    for row in rows:counts.update(row['counts'])
    return dict(games=n,seed_blocks=len(blocks),wins=wins,draws=sum(r['draw'] for r in rows),win_rate=phat,win_rate_wilson_95=[center-span,center+span],mean_paired_bank_margin=sum(blocks)/len(blocks),margin_seed_bootstrap_95=[draws[249],draws[9749]],counts=dict(counts),interpretation='Local deterministic engine comparison. Win interval is descriptive across games; the primary margin interval resamples seed blocks. No claim of a hosted leaderboard improvement.')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path);p.add_argument('--stage',default='screen');p.add_argument('--first',type=int,default=915101);p.add_argument('--last',type=int,default=915112);p.add_argument('--jobs',type=int,default=4);p.add_argument('--variant',choices=['blink','rune','rune-owner'],default='blink');a=p.parse_args();root=a.study.resolve()
    identities={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('baseline.py','candidate.py','json_match')}
    jobs=[dict(study=str(root),stage=a.stage,seed=seed,side=side,variant=a.variant) for seed in range(a.first,a.last+1) for side in (0,1)]
    with ProcessPoolExecutor(max_workers=a.jobs) as pool:rows=list(pool.map(play,jobs))
    for name,digest in identities.items():assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest
    report=summary(rows)|{'identities':identities};(root/(a.stage+'-summary.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)

if __name__=='__main__':main()
