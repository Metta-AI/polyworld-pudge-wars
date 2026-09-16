"""Run one preregistered hosted phase sequentially, with streaming harvest.

Requires a study with coworld.json and uploaded-policy.json. Never submits to a
league or promotes a champion. Run with the installed Coworld Python.
"""
import argparse
import json
from pathlib import Path
import time
from types import SimpleNamespace

from coworld.api_client import CoworldApiClient
from hosted_evaluate import create, harvest

PARENT = '41212e9a-6383-40f8-b44e-f4ceb64ef9c9'
OPPONENTS = {'directional':'43bf1d57-9ef0-4c86-9e4e-476969fd8f2b',
             'confirmation':'43bf1d57-9ef0-4c86-9e4e-476969fd8f2b',
             'guardrail':'05abab38-0b6e-42ec-a90d-91be5fb17bba'}


def run(study, phase):
    game=json.loads((study/'coworld.json').read_text())
    candidate=json.loads((study/'uploaded-policy.json').read_text())['id']
    size={'directional':10,'confirmation':20,'guardrail':20}[phase]
    batches=2 if phase=='confirmation' else 1
    with CoworldApiClient.from_login(server_url='https://softmax.com/api') as client:
        for role,policy in [('parent',PARENT),('candidate',candidate)]:
            for side,bank in enumerate(('west','east')):
                for batch in range(batches):
                    label=f'{phase}-{role}-{bank}'+(f'-{batch+1}' if batches>1 else '')
                    index=study/'requests.json'
                    rows=json.loads(index.read_text()) if index.exists() else []
                    existing=next((row for row in rows if row['label']==label),None)
                    args=SimpleNamespace(study=study,label=label,policy=policy,opponent=OPPONENTS[phase],side=side,episodes=size,dry_run=True)
                    if existing:
                        assert (existing['policy'],existing['opponent'],existing['candidate_side'],existing['num_episodes'])==(policy,OPPONENTS[phase],side,size)
                    else:
                        if rows:
                            assert harvest(client,args), 'Drain existing requests before launching another'
                            assert all(row['status']=='completed' for row in json.loads((study/'status.json').read_text())), 'A failed request requires diagnosis'
                        create(client,args,game)
                        args.dry_run=False
                        create(client,args,game)
                    while True:
                        complete=harvest(client,args)
                        statuses=json.loads((study/'status.json').read_text())
                        assert not any(row['status'] in ('failed','canceled','cancelled') for row in statuses), 'A failed request requires diagnosis'
                        if complete:break
                        time.sleep(30)
    print('Phase complete:',phase,flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('study',type=Path)
    p.add_argument('--phase',choices=list(OPPONENTS),required=True)
    args=p.parse_args();run(args.study.resolve(),args.phase)
