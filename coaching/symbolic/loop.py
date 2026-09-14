"""Run text -> code -> extracted text -> code, then bounded IR improvement.

Grounding is assistant-authored. Optimization edits one named text parameter;
this is not a claim to learn new ontologies or call an autonomous coding model.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor,as_completed
from dataclasses import replace
import json
from pathlib import Path
import shutil
import statistics

from .evaluate import prepare,play,summarize,digest
from .ir import parse,render,extract,generate,binding_hash
from . import skills


def execute(jobs,count):
    rows=[]
    with ProcessPoolExecutor(max_workers=count) as pool:
        pending={pool.submit(play,job):job for job in jobs}
        for task in as_completed(pending):
            row=task.result();rows.append(row)
            print(json.dumps({k:row[k] for k in ['phase','arm','seed','side','ours','theirs','roundtrip_actions','wall_seconds']}),flush=True)
    return rows


def improvement_gate(selected, differences):
    """An exploratory retention gate, not a statistical significance claim."""
    if selected=='support':return 'support','Development retained the parent.'
    required=(3*len(differences)+3)//4
    if statistics.mean(differences)>0 and sum(value>0 for value in differences)>=required:
        return selected,'Positive mean margin gain and improvement on at least three quarters of held-out seeds.'
    return 'support','Held-out consistency gate failed; keep the parent and preserve the rejected candidate.'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--runner',type=Path,default=Path('tmp/coaching/symbolic_match'))
    p.add_argument('--baseline',type=Path,default=Path('coworld/player/base.py'))
    p.add_argument('--initial',type=Path,default=Path('coaching/policies/executable/loom.policy.md'))
    p.add_argument('--candidate',type=Path,default=Path('coaching/policies/executable/support.policy.md'))
    p.add_argument('--jobs',type=int,default=2)
    p.add_argument('--train-seeds',default='6101,6102')
    p.add_argument('--validation-seeds',default='7101,7102,7103,7104')
    p.add_argument('--ticks',type=int,default=38400)
    p.add_argument('--goal',type=int,default=30)
    p.add_argument('--n',type=int,default=2)
    args=p.parse_args()
    train=[int(x) for x in args.train_seeds.split(',')];held=[int(x) for x in args.validation_seeds.split(',')]
    if set(train)&set(held):p.error('Training and validation seeds must be disjoint')
    if len(set(train))!=len(train) or len(set(held))!=len(held):p.error('Seed sets must not contain duplicates')
    if min(args.jobs,args.ticks,args.goal,args.n)<1:p.error('Nonpositive game setting')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    shutil.copy2(args.baseline,out/'reference.py');shutil.copy2(args.runner,out/'native_match')
    shutil.copy2(skills.__file__,out/'skills.snapshot.py')
    library_hash=binding_hash()
    arms={}
    initial=parse(args.initial.read_text());base=parse(args.candidate.read_text())
    # Propose the next generation from code-derived IR, exercising both directions.
    base=parse(render(extract(generate(base))))
    aiming=[step for step in base.steps if step.skill=='aimed_shot']
    if len(aiming)!=1:p.error('Candidate must contain exactly one aimed_shot skill for this optimizer')
    parent_lead=dict(aiming[0].arguments).get('lead',1.0)
    programs={'loom':initial,'support':base}
    # Three prespecified alternatives, chosen on development games only.
    for label,lead in [('short_lead',parent_lead*.5),('long_lead',min(3.,parent_lead*1.5))]:
        steps=tuple(replace(s,arguments=(('lead',lead),)) if s.skill=='aimed_shot' else s for s in base.steps)
        programs[label]=replace(base,name=label,steps=steps)
    for label,program in programs.items():
        directory=out/'artifacts'/label;directory.mkdir(parents=True)
        text=render(program,origin='Assistant-authored grounding of textual policy; bounded lead parameter candidate.' if label!='loom' else 'Grounded projection of loom-current.md; existing public skill contracts.')
        path=directory/'source.policy.md';path.write_text(text)
        arms[label]=prepare(path,directory)
    contract={'hypothesis':'A grounded text policy can improve on Loom against frozen Base while executable extraction/regeneration preserves decisions and memory.',
              'selection':'Highest development mean kill margin among support/short_lead/long_lead; ties prefer support then short_lead.',
              'held_out':'Initial Loom, unmodified support parent and selected candidate on fresh paired maps and both banks.',
              'promotion':'Retain the parent unless selected-minus-parent mean margin is positive and at least three quarters of held-out seeds improve. Exploratory artifact gate only, no hosted deployment.',
              'train_seeds':train,'validation_seeds':held,'n':args.n,'goal':args.goal,'max_ticks':args.ticks,
              'baseline_sha256':digest(out/'reference.py'),'runner_sha256':digest(out/'native_match'),'skills_sha256':library_hash,
              'model_calls':0,'synthesis':'Assistant-authored skill grounding and symbolic text compiler; AST-based extraction; bounded text-parameter search.'}
    contract['lead_candidates']={'support':parent_lead,'short_lead':parent_lead*.5,'long_lead':min(3.,parent_lead*1.5)}
    (out/'contract.json').write_text(json.dumps(contract,indent=2))
    def jobs(phase,labels,seeds):
        return [dict(out=str(out/'games'/f'{phase}-{arm}-{seed}-{side}'),phase=phase,arm=arm,seed=seed,side=side,
            n=args.n,goal=args.goal,ticks=args.ticks,runner=str(out/'native_match'),baseline=str(out/'reference.py'),
            policy=str(arms[arm][0]),roundtrip=str(arms[arm][1])) for arm in labels for seed in seeds for side in [0,1]]
    training=execute(jobs('development',list(programs),train),args.jobs)
    development={label:summarize([r for r in training if r['arm']==label]) for label in programs}
    eligible=['support','short_lead','long_lead']
    selected=max(eligible,key=lambda label:development[label]['mean_margin'])
    (out/'development.json').write_text(json.dumps({'arms':development,'selected':selected,'games':training},indent=2))
    print('Selected on development only:',selected,flush=True)
    validation_labels=list(dict.fromkeys(['loom','support',selected]))
    validation=execute(jobs('validation',validation_labels,held),args.jobs)
    results={label:summarize([r for r in validation if r['arm']==label]) for label in validation_labels}
    # Banks on one seed are clustered; seeds are the independent comparison units.
    differences=[];parent_differences=[]
    for seed in held:
        means={label:statistics.mean(r['margin'] for r in validation if r['seed']==seed and r['arm']==label) for label in validation_labels}
        differences.append(means[selected]-means['loom'])
        parent_differences.append(means[selected]-means['support'])
    repeats=[]
    for original in validation:
        if original['arm']==selected and original['seed']==held[0]:
            repeat=jobs('regenerated',[selected],[held[0]])[original['side']]
            repeat['execution']='regenerated'
            repeats.append(repeat)
    regenerated_games=execute(repeats,args.jobs)
    for repeat in regenerated_games:
        original=next(r for r in validation if r['arm']==selected and r['seed']==repeat['seed'] and r['side']==repeat['side'])
        if any(repeat[k]!=original[k] for k in ('trajectory_sha256','terminal_tick','score')):
            raise RuntimeError('Running regenerated code changed a complete game trajectory')
    if binding_hash()!=library_hash:raise RuntimeError('Skill library changed during the experiment')
    retained,retention_reason=improvement_gate(selected,parent_differences)
    report={'contract':contract,'development':development,'selected':selected,'validation':results,
            'retained':retained,'retention_reason':retention_reason,
            'seed_paired_margin_differences':differences,'mean_paired_margin_difference':statistics.mean(differences),
            'seed_paired_margin_differences_vs_parent':parent_differences,
            'mean_paired_margin_difference_vs_parent':statistics.mean(parent_differences),
            'validation_games':validation,'regenerated_games':regenerated_games,
            'all_games':len(training)+len(validation)+len(regenerated_games),
            'total_roundtrip_actions':sum(r['roundtrip_actions'] for r in training+validation+regenerated_games),
            'roundtrip_mismatches':0,'limitations':['Bounded compiler/extractor with shared frozen skill contracts, not arbitrary code or unrestricted prose.',
                'Assistant-authored grounding; no independent language-model synthesis runs.',
                'Accelerated native local games omit network latency and do not establish hosted performance.',
                'Small seed sample; development optimization and held-out performance are reported separately.']}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    # Persist both directions at the next iteration boundary; recovered text is executable input.
    shutil.copy2(arms[retained][0].with_name('recovered.policy.md'),out/'next-iteration.policy.md')
    print(json.dumps({'selected':selected,'validation':results,'roundtrip_actions':report['total_roundtrip_actions'],'report':str(out/'report.json')}),flush=True)


if __name__=='__main__':main()
