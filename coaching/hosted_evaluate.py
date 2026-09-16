"""Pinned hosted comparisons for a coaching study; no league promotion.

Run with the installed Coworld Python from outside this repository. The study's
saved coworld.json pins the exact game. Requests are idempotent and all rosters,
failures and completed artifacts are retained. Choose 10–20 episodes per batch.
"""
import argparse
import hashlib
import json
from pathlib import Path
import time

from coworld.api_client import CoworldApiClient
from jsonschema import Draft202012Validator


def save(file, data):
    temp=file.with_suffix('.tmp')
    temp.write_text(json.dumps(data,indent=2)+'\n');temp.replace(file)


def request(client, method, url, **kwargs):
    response=client._http_client.request(method,url,headers=client._headers(),timeout=120,**kwargs)
    response.raise_for_status()
    return response


def create(client,args,game):
    current=request(client,'GET','/v2/coworlds/'+game['id']).json()
    assert all(current[key]==game[key] for key in ('version','manifest_hash')), 'Game changed since preregistration; do not launch a mixed-version comparison'
    body=dict(idempotency_key=args.study.name+'-'+args.label,private=True,
              coworld_id=game['id'],variant_id='league-3v3',num_episodes=args.episodes,
              roster=[dict(slot=i,player=dict(policy_ref=args.policy if i//3==args.side else args.opponent)) for i in range(6)],
              notes='Preregistered coaching IR comparison: '+args.label)
    schema=request(client,'GET','/openapi.json').json()
    Draft202012Validator({'$ref':'#/components/schemas/V2CreateExperienceRequestRequest','components':schema['components']}).validate(body)
    target=args.study/(args.label+'-request.json')
    if target.exists():assert json.loads(target.read_text())==body,'Changed body for existing request label'
    save(target,body)
    if args.dry_run:print('Live schema validation passed:',args.label,flush=True);return
    response=request(client,'POST','/v2/experience-requests',json=body).json()
    save(args.study/(args.label+'-created.json'),response)
    row=dict(id=response['id'],label=args.label,n=3,candidate_side=args.side,policy=args.policy,
             opponent=args.opponent,num_episodes=args.episodes,coworld_id=game['id'],coworld_version=game['version'],manifest_hash=game['manifest_hash'])
    index=args.study/'requests.json';rows=json.loads(index.read_text()) if index.exists() else []
    save(index,[r for r in rows if r['id']!=row['id']]+[row]);print(json.dumps(row),flush=True)


def harvest(client,args):
    rows=json.loads((args.study/'requests.json').read_text());statuses=[];results=[]
    for row in rows:
        detail=request(client,'GET','/v2/experience-requests/'+row['id']).json()
        save(args.study/(row['label']+'-status.json'),detail)
        counts={}
        for ep in detail['episodes']:
            counts[ep['status']]=counts.get(ep['status'],0)+1
            assert ep['policy_version_ids']==[row['policy'] if i//3==row['candidate_side'] else row['opponent'] for i in range(6)],'Resolved roster mismatch'
            assert ep['coworld_version']==row['coworld_version'],'Game version mismatch'
            if ep['status']!='completed':continue
            folder=args.study/'hosted-artifacts'/ep['id'];folder.mkdir(parents=True,exist_ok=True)
            for kind,name in [('results','results.json'),('replay','replay.pwr')]:
                file=folder/name
                if not file.exists():
                    data=request(client,'GET','/v2/episode-requests/'+ep['id']+'/artifacts/'+kind).content
                    temp=file.with_suffix('.download');temp.write_bytes(data);temp.replace(file)
            result=json.loads((folder/'results.json').read_text())
            results.append(dict(label=row['label'],n=3,candidate_side=row['candidate_side'],request_id=row['id'],episode_id=ep['id'],result=result))
        statuses.append(row|dict(status=detail['status'],counts=counts,episodes=detail['episodes']))
        print(json.dumps(dict(label=row['label'],id=row['id'],status=detail['status'],counts=counts)),flush=True)
    save(args.study/'status.json',statuses);save(args.study/'hosted-results.json',results)
    files={str(p.relative_to(args.study)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.study/'hosted-artifacts').glob('*/*')}
    save(args.study/'artifact-hashes.json',files)
    return all(r['status'] in ('completed','failed','canceled','cancelled') for r in statuses)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('study',type=Path)
    p.add_argument('--create',action='store_true');p.add_argument('--dry-run',action='store_true');p.add_argument('--watch',action='store_true')
    p.add_argument('--label');p.add_argument('--policy');p.add_argument('--opponent');p.add_argument('--side',type=int,choices=[0,1])
    p.add_argument('--episodes',type=int,choices=range(10,21),default=10);a=p.parse_args();a.study=a.study.resolve()
    with CoworldApiClient.from_login(server_url='https://softmax.com/api') as c:
        if a.create:
            assert all([a.label,a.policy,a.opponent]) and a.side is not None
            create(c,a,json.loads((a.study/'coworld.json').read_text()))
        else:
            while True:
                complete=harvest(c,a)
                if complete or not a.watch:break
                time.sleep(30)


if __name__=='__main__':main()
