"""Paired, complete native games with source-derived round-trip shadow checks."""
from __future__ import annotations

from collections import Counter
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import shutil
import sys
import time
import threading
import uuid
import platform

from .ir import extract, generate, render, parse, binding_hash
from .spatial import SpatialMetrics


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def job_signature(job):
    """A completed match is reusable only with identical executable inputs."""
    fields = ('seed', 'side', 'n', 'ticks', 'goal', 'execution', 'baseline_class', 'baseline_options')
    payload = {key: job.get(key) for key in fields}
    payload['files'] = {key: digest(job[key]) for key in ('policy', 'roundtrip', 'baseline', 'runner')}
    payload['bindings'] = binding_hash()
    payload['evaluator'] = digest(__file__)
    payload['compiler'] = digest(Path(__file__).with_name('ir.py'))
    payload['spatial'] = digest(Path(__file__).with_name('spatial.py'))
    payload['bindings_v2'] = binding_hash('pudge-skills-v2')
    payload['python'] = sys.version
    payload['platform'] = platform.platform()
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def play_cached(job):
    directory = Path(job['out'])
    result_path = directory / 'result.json'
    if result_path.exists():
        result = json.loads(result_path.read_text())
        if result.get('job_signature') != job_signature(job):
            raise ValueError('Completed match inputs changed; use a new campaign: ' + str(directory))
        if result['roundtrip_mismatches'] or result['roundtrip_state_mismatches']:
            raise ValueError('Cannot reuse a failed round trip')
        return result
    if directory.exists():
        # Preserve evidence from an interrupted/failed attempt before retrying.
        directory.rename(directory.with_name(directory.name + '.attempt-' + uuid.uuid4().hex[:8]))
    try:
        return play(job)
    except Exception as error:
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'failure.json').write_text(json.dumps({'type': type(error).__name__, 'message': str(error)}))
        raise


def load(path,name):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec);sys.modules[name]=module
    spec.loader.exec_module(module)
    return module


def prepare(text_path,directory):
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    source_text=Path(text_path).read_text();program=parse(source_text)
    source=generate(program)
    recovered=extract(source)
    recovered_text=render(recovered)
    second=generate(parse(recovered_text))
    assert extract(second)==recovered
    (directory/'input.policy.md').write_text(source_text)
    (directory/'policy.py').write_text(source)
    (directory/'recovered.policy.md').write_text(recovered_text)
    (directory/'regenerated.py').write_text(second)
    (directory/'identity.json').write_text(json.dumps({'input':digest(directory/'input.policy.md'),'symbolic':digest(directory/'policy.py'),'recovered':digest(directory/'recovered.policy.md'),'regenerated':digest(directory/'regenerated.py'),'binding':program.binding_hash},indent=2))
    return directory/'policy.py',directory/'regenerated.py'


def play(job):
    directory=Path(job['out']);directory.mkdir(parents=True,exist_ok=False)
    candidate_path=Path(job['policy']);roundtrip_path=Path(job['roundtrip']);baseline_path=Path(job['baseline']);runner=Path(job['runner'])
    identities={str(p):digest(p) for p in [candidate_path,roundtrip_path,baseline_path,runner]}
    signature = job_signature(job)
    extract(candidate_path.read_text());extract(roundtrip_path.read_text())
    generated=load(candidate_path,'generated_candidate');regenerated=load(roundtrip_path,'regenerated_candidate');baseline=load(baseline_path,'frozen_reference')
    n,side,seed=job['n'],job['side'],job['seed']
    executed = regenerated if job.get('execution') == 'regenerated' else generated
    reference_class = getattr(baseline, job.get('baseline_class', 'BasePolicy'))
    players=[executed.Policy() if i//n==side else reference_class(**job.get('baseline_options', {})) for i in range(2*n)]
    shadow = generated if executed is regenerated else regenerated
    copies=[shadow.Policy() for _ in range(n)]
    roundtrip_actions=0;skill_counts=Counter();successes=Counter();acceptances=Counter();decisions=0;policy_seconds=0.;baseline_seconds=0.
    timed_decisions = 0
    spatial = SpatialMetrics()
    trajectory_hash=hashlib.sha256();start=time.monotonic();result=None
    with (directory/'engine.log').open('w') as log,(directory/'decisions.jsonl').open('w') as trace:
        p=subprocess.Popen([str(runner.resolve()),str(seed),str(n),str(job['ticks']),str(job['goal'])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,text=True)
        expired = threading.Event()
        def stop_engine():
            expired.set()
            try:p.kill()
            except ProcessLookupError:pass
        watchdog = threading.Timer(job.get('wall_limit', 240), stop_engine)
        watchdog.daemon = True
        watchdog.start()
        try:
            for line in p.stdout:
                observations=json.loads(line)
                if isinstance(observations,dict) and observations.get('final'):
                    result=observations;break
                if len(observations)!=2*n:raise RuntimeError('Missing player observations')
                actions=[]
                for i,obs in enumerate(observations):
                    then=time.perf_counter();action=players[i].choose_action(obs);elapsed=time.perf_counter()-then
                    if i//n==side:
                        spatial.observe(obs, action)
                        copy = copies[i % n]
                        other = copy.choose_action(obs)
                        if action != other or players[i].state.__dict__ != copy.state.__dict__:
                            (directory/'roundtrip-failure.json').write_text(json.dumps({'slot':i,'observation':obs,'before':action,'after':other}))
                            raise RuntimeError('Round trip changed behavior or internal state')
                        roundtrip_actions += 1
                        decisions+=1
                        if obs['tick'] >= 128:
                            policy_seconds+=elapsed;timed_decisions+=1
                        for event in players[i].trace:
                            skill_counts[event['skill']]+=1
                            if event['result']:successes[event['skill']]+=1
                        for key,value in obs.get('accepted',{}).items():
                            if value is True:acceptances[key]+=1
                        if obs['tick']%128==0:
                            trace.write(json.dumps({'slot':i,'observation':obs,'action':action,'skills':players[i].trace})+'\n')
                    elif obs['tick'] >= 128:baseline_seconds+=elapsed
                    actions.append(action)
                encoded=json.dumps(actions,separators=(',',':'))+'\n'
                trajectory_hash.update(encoded.encode());p.stdin.write(encoded);p.stdin.flush()
            if expired.is_set():raise TimeoutError('Native game exceeded its wall-time budget')
            if result is None:raise RuntimeError('Native engine stopped without a complete game')
            p.wait(timeout=10)
            if p.returncode:raise RuntimeError('Native engine failed')
        finally:
            watchdog.cancel()
            if p.poll() is None:p.kill();p.wait()
            p.stdin.close()
            p.stdout.close()
    for path,expected in identities.items():
        if digest(path)!=expected:raise RuntimeError('Evaluation input changed: '+path)
    extract(candidate_path.read_text())
    if job_signature(job) != signature:raise RuntimeError('Evaluation implementation changed during a match')
    ours,theirs=result['score'][side],result['score'][1-side]
    # Both terminal outcome and kill-goal attainment are reported; timeouts are explicit.
    row={**job,'score':result['score'],'ours':ours,'theirs':theirs,'margin':ours-theirs,
         'outcome':'win' if ours>theirs else 'loss' if ours<theirs else 'draw',
         'goal_reached':max(ours,theirs)>=job['goal'],'terminal_tick':result['tick'],
         'roundtrip_actions':roundtrip_actions,'roundtrip_mismatches':0,'roundtrip_state_mismatches':0,
         'roundtrip_scope':'Every executed candidate decision and memory state; opponent seats are not shadowed.',
         'job_signature':signature,
         'skill_calls':dict(skill_counts),'skill_successes':dict(successes),'accepted_commands':dict(acceptances),
         'spatial':spatial.report(),
         'trajectory_sha256':trajectory_hash.hexdigest(),'wall_seconds':time.monotonic()-start,
         'timed_decisions':timed_decisions,'timing_warmup_ticks':128,
         'candidate_decisions_per_second':timed_decisions/max(policy_seconds,1e-9) if timed_decisions else None,
         'reference_decisions_per_second':timed_decisions/max(baseline_seconds,1e-9) if timed_decisions else None,'identities':identities}
    result_path = directory / 'result.json'
    temporary = directory / 'result.json.tmp'
    temporary.write_text(json.dumps(row,indent=2)+'\n')
    temporary.replace(result_path)
    return row


def summarize(rows):
    return {'games':len(rows),'wins':sum(r['outcome']=='win' for r in rows),'losses':sum(r['outcome']=='loss' for r in rows),
            'draws':sum(r['outcome']=='draw' for r in rows),'timeouts':sum(not r['goal_reached'] for r in rows),
            'mean_margin':sum(r['margin'] for r in rows)/len(rows),
            'mean_kills':sum(r['ours'] for r in rows)/len(rows),'mean_opponent_kills':sum(r['theirs'] for r in rows)/len(rows),
            'roundtrip_actions':sum(r['roundtrip_actions'] for r in rows),'roundtrip_mismatches':sum(r['roundtrip_mismatches'] for r in rows)}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('policy',type=Path,help='Textual .policy.md input')
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--runner',type=Path,default=Path('tmp/coaching/symbolic_match'))
    parser.add_argument('--baseline',type=Path,default=Path('coworld/player/base.py'))
    parser.add_argument('--seed',type=int,default=7101)
    parser.add_argument('--side',type=int,choices=[0,1],default=0)
    parser.add_argument('--n',type=int,default=2)
    parser.add_argument('--ticks',type=int,default=38400)
    parser.add_argument('--goal',type=int,default=30)
    parser.add_argument('--regenerated',action='store_true')
    args=parser.parse_args()
    if min(args.n,args.ticks,args.goal)<1:parser.error('Nonpositive game setting')
    directory=args.out.resolve();directory.mkdir(parents=True,exist_ok=False)
    shutil.copy2(args.baseline,directory/'reference.py')
    shutil.copy2(args.runner,directory/'native_match')
    policy,roundtrip=prepare(args.policy,directory/'artifacts')
    result=play(dict(out=str(directory/'game'),phase='single',arm=parse(args.policy.read_text()).name,
        seed=args.seed,side=args.side,n=args.n,ticks=args.ticks,goal=args.goal,
        runner=str(directory/'native_match'),baseline=str(directory/'reference.py'),
        policy=str(policy),roundtrip=str(roundtrip),execution='regenerated' if args.regenerated else 'generated'))
    print(json.dumps({k:result[k] for k in ('ours','theirs','outcome','terminal_tick','roundtrip_actions','roundtrip_mismatches','wall_seconds')},indent=2))
    print('Evidence:',directory/'game'/'result.json')


if __name__=='__main__':main()
