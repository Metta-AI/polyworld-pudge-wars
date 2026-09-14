"""Paired spatial-coaching evaluation, with optional formation-only ablation."""
import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import replace
import json
from pathlib import Path
import random
import shutil
import statistics

from .evaluate import digest, play_cached, prepare, summarize
from .ir import parse, render


METRICS = ('clustered_fraction', 'contact_fraction', 'occupied_route_fraction',
           'stalled_fraction', 'wall_contact_fraction', 'wall_stalled_fraction', 'mean_nearest_ally_distance')


def paired_interval(differences):
    rng = random.Random(20260910)
    means = sorted(statistics.mean(rng.choices(differences,k=len(differences))) for _ in range(4000))
    return [means[100], means[3899]]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--seeds',type=int,nargs='+',required=True)
    p.add_argument('--candidate',type=Path,default=Path('coaching/policies/executable/spatial.policy.md'))
    p.add_argument('--runner',type=Path,default=Path('tmp/coaching/spatial_match'))
    p.add_argument('--baseline',type=Path,default=Path('coworld/player/base.py'))
    p.add_argument('--ablations',action='store_true')
    p.add_argument('--alternative',type=Path,help='An additional predeclared development IR candidate.')
    p.add_argument('--phase',choices=['development','confirmation'],required=True)
    p.add_argument('--jobs',type=int,default=2)
    args=p.parse_args()
    root=args.out.resolve();root.mkdir(parents=True,exist_ok=False)
    snapshot=root/'source_snapshot';snapshot.mkdir()
    for path in Path(__file__).parent.glob('*.py'):
        shutil.copy2(path,snapshot/path.name)
    shutil.copy2(Path(__file__).with_name('native_match.nim'),snapshot/'native_match.nim')
    parent=parse(Path('coaching/policies/executable/support.policy.md').read_text())
    child=parse(args.candidate.read_text())
    arms={'parent':parent,'candidate':child}
    if args.alternative:
        if args.phase!='development':p.error('Alternatives must be selected before confirmation')
        arms['alternative']=parse(args.alternative.read_text())
    if args.ablations:
        arms['formation_only']=replace(child,name='formation_only',steps=tuple(s for s in child.steps if s.skill!='clear_occupied_route'))
    shutil.copy2(args.runner,root/'native_match')
    shutil.copy2(args.baseline,root/'reference.py')
    artifact={}
    for name,program in arms.items():
        source=root/(name+'.policy.md');source.write_text(render(program))
        artifact[name]=prepare(source,root/'artifacts'/name)
    contract=dict(phase=args.phase,seeds=args.seeds,n=3,ticks=38400,goal=30,
                  arms={name:dict(binding=p.binding_hash,policy=digest(artifact[name][0])) for name,p in arms.items()},
                  runner=digest(root/'native_match'),opponent=digest(root/'reference.py'),
                  hypothesis='One rune owner plus occupied-route detours reduce contact and futile movement without sacrificing game score.',
                  primary=['clustered_fraction','occupied_route_fraction'],
                  score_guardrail='Report paired kill margin and win rate; do not claim stronger play without interval excluding zero.',
                  seed_unit='Average paired bank differences within each seed, then bootstrap independent seeds.',
                  metrics='Spatial samples every 8 ticks; body distance and low progress are proxies, not engine collision events.')
    (root/'contract.json').write_text(json.dumps(contract,indent=2)+'\n')
    jobs=[dict(out=str(root/f'{name}-{seed}-{side}'),phase=args.phase,arm=name,
               seed=seed,side=side,n=3,ticks=38400,goal=30,runner=str(root/'native_match'),
               baseline=str(root/'reference.py'),policy=str(artifact[name][0]),roundtrip=str(artifact[name][1]))
          for seed in args.seeds for side in (0,1) for name in arms]
    rows=[]
    with ProcessPoolExecutor(max_workers=args.jobs) as pool:
        for future in as_completed([pool.submit(play_cached,job) for job in jobs]):
            row=future.result();rows.append(row)
            print(json.dumps({k:row[k] for k in ('arm','seed','side','ours','theirs','wall_seconds')}),flush=True)
    report={'contract':contract,'arms':{}}
    parent_rows={(r['seed'],r['side']):r for r in rows if r['arm']=='parent'}
    for name in arms:
        group=[r for r in rows if r['arm']==name]
        summary=summarize(group)
        summary['spatial']={key:statistics.mean(r['spatial'][key] for r in group if r['spatial'][key] is not None) for key in METRICS}
        ratios=[r['candidate_decisions_per_second']/r['reference_decisions_per_second'] for r in group]
        summary['median_throughput_ratio']=statistics.median(ratios)
        summary['runtime_failure_games']=sum(r<.5 for r in ratios)
        summary['paired']={}
        for key in ('margin',*METRICS):
            diffs=[]
            for seed in args.seeds:
                values=[]
                for row in group:
                    if row['seed']!=seed:continue
                    control=parent_rows[seed,row['side']]
                    a,b=(row[key],control[key]) if key=='margin' else (row['spatial'][key],control['spatial'][key])
                    if a is not None and b is not None:values.append(a-b)
                if values:diffs.append(statistics.mean(values))
            summary['paired'][key]=dict(mean=statistics.mean(diffs),ci95=paired_interval(diffs),independent_seeds=len(diffs))
        report['arms'][name]=summary
    (root/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['arms'],indent=2))
    print('Evidence:',root/'report.json')


if __name__=='__main__':main()
