"""Fixed native full games with independent semantic and regenerated shadows."""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess
import time

from .scrum_verify import check, reference_module
from .session_evaluate import summary
from .v14_verify import load


def play(job):
    root=Path(job['study'])
    folder=root/job['stage']/f"{job['seed']}-{job['side']}"
    folder.mkdir(parents=True)
    base=load(root/'baseline.py','scrum_base')
    cand=load(root/'candidate.py','scrum_cand')
    regen=load(root/'regenerated.py','scrum_regen')
    ref=reference_module(root/'baseline.py',job['variant'],'scrum_reference')
    side=job['side']
    bots=[(cand if i//3==side else base).BasePolicy(heal_allies=True,spread_fishing=True) for i in range(6)]
    shadows=[[m.BasePolicy(heal_allies=True,spread_fishing=True) for m in (base,ref,regen)] for _ in range(3)]
    counts=Counter(); examples=[]; start=time.monotonic(); trajectory=hashlib.sha256()
    with (folder/'engine.log').open('w') as err:
        proc=subprocess.Popen([str(root/'json_match'),str(job['seed']),'3','38400','30'],
                              stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,text=True)
        try:
            for line in proc.stdout:
                observations=json.loads(line)
                if isinstance(observations,dict) and observations.get('final'):
                    result=observations;break
                actions=[]
                for slot,(bot,obs) in enumerate(zip(bots,observations)):
                    if slot//3!=side:
                        actions.append(bot.choose_action(obs));continue
                    b,r,g=shadows[slot%3]
                    try:
                        parent,action=check(obs,b,bot,r,g,job['variant'])
                    except AssertionError as error:
                        (folder/'reconciliation-failure.json').write_text(json.dumps(dict(error=str(error),observation=obs),indent=2)+'\n')
                        raise
                    counts['checked_decisions']+=1
                    counts['changed_decisions']+=parent!=action
                    counts['changed_hook_requests']+=parent.get('hook_to')!=action.get('hook_to')
                    counts['candidate_hook_requests']+='hook_to' in action
                    counts['parent_hook_requests']+='hook_to' in parent
                    for key,value in obs.get('accepted',{}).items():
                        if value is True: counts['accepted_'+key]+=1
                    if parent!=action and len(examples)<6:
                        examples.append(dict(tick=obs['tick'],player=obs['self']['id'],parent=parent,candidate=action))
                    actions.append(action)
                wire=json.dumps(actions,separators=(',',':'))+'\n'
                trajectory.update(wire.encode())
                proc.stdin.write(wire);proc.stdin.flush()
            else:
                raise RuntimeError('No final native result')
            proc.wait(timeout=10)
            if proc.returncode:raise RuntimeError('Native engine failed')
        finally:
            if proc.poll() is None:proc.kill();proc.wait()
    counts.update(ref.reference_counts)
    ours,theirs=result['score'][side],result['score'][1-side]
    row=job|dict(ours=ours,theirs=theirs,margin=ours-theirs,win=ours>theirs,draw=ours==theirs,
                 seconds=round(time.monotonic()-start,2),counts=dict(counts),examples=examples,final=result,
                 action_stream_sha256=trajectory.hexdigest(),semantic_mismatches=0,roundtrip_mismatches=0)
    (folder/'result.json').write_text(json.dumps(row,indent=2)+'\n')
    print(json.dumps({k:row[k] for k in ('seed','side','ours','theirs','seconds')}),flush=True)
    return row


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('study',type=Path)
    p.add_argument('--variant',required=True,choices=('engagement','fountain'))
    p.add_argument('--first',type=int,required=True);p.add_argument('--last',type=int,required=True)
    p.add_argument('--stage',default='screen');p.add_argument('--jobs',type=int,default=4)
    a=p.parse_args();root=a.study.resolve()
    files=('baseline.py','candidate.py','regenerated.py','json_match')
    identities={f:hashlib.sha256((root/f).read_bytes()).hexdigest() for f in files}
    jobs=[dict(study=str(root),stage=a.stage,seed=s,side=side,variant=a.variant) for s in range(a.first,a.last+1) for side in (0,1)]
    with (root/(a.stage+'-manifest.json')).open('x') as f:json.dump(dict(identities=identities,jobs=jobs),f,indent=2)
    with ProcessPoolExecutor(max_workers=a.jobs) as pool:rows=list(pool.map(play,jobs))
    report=summary(rows)|dict(identities=identities,semantic_mismatches=0,roundtrip_mismatches=0,
                             bank_results={str(side):dict(games=sum(r['side']==side for r in rows),
                                                        wins=sum(r['win'] for r in rows if r['side']==side),
                                                        mean_margin=sum(r['margin'] for r in rows if r['side']==side)/(len(rows)/2)) for side in (0,1)})
    report['screen_gate_passed']=(report['mean_paired_bank_margin']>=2 and report['margin_seed_bootstrap_95'][0]>0
                                   and report['counts']['changed_decisions']>0)
    for f,h in identities.items():assert hashlib.sha256((root/f).read_bytes()).hexdigest()==h
    (root/(a.stage+'-summary.json')).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report),flush=True)


if __name__=='__main__':main()
