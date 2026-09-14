#!/usr/bin/env python3
"""Create schema-validated fixed-roster XP requests and harvest their artifacts.

Run with a Python environment containing coworld and jsonschema, outside a
directory that shadows the installed coworld package. --create writes one
10–20 episode request; --watch polls existing requests without creating more.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import time

import httpx
from coworld.api_client import CoworldApiClient
from jsonschema import Draft202012Validator


def save(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


def get(client, path):
    for attempt in range(3):
        try:
            response = client._http_client.get(path, headers=client._headers(), timeout=120)
            response.raise_for_status()
            return response
        except httpx.HTTPStatusError as error:
            if error.response.status_code != 429 and error.response.status_code < 500:
                raise
            if attempt == 2:
                raise
        except httpx.TransportError:
            if attempt == 2:
                raise
        print(f'Retrying read after transient network failure: {path}', flush=True)
        time.sleep(2 ** attempt)


def create(args):
    with CoworldApiClient.from_login(server_url='https://softmax.com/api') as client:
        schema = get(client, '/openapi.json').json()
        body = dict(idempotency_key=args.study.name + '-' + args.label, private=True,
                    coworld_id='cow_8ef8b994-1cd2-4ebb-b452-22ea8a46404e',
                    variant_id='league-3v3' if args.n == 3 else 'duel-1v1',
                    num_episodes=args.episodes,
                    roster=[{'player': {'policy_ref': args.policy if i // args.n == args.side else args.opponent}, 'slot': i} for i in range(args.n * 2)],
                    notes=args.notes or args.label)
        validator = Draft202012Validator({'$ref': '#/components/schemas/V2CreateExperienceRequestRequest', 'components': schema['components']})
        validator.validate(body)
        save(args.study / (args.label + '-request.json'), body)
        if args.dry_run:
            print('Live schema validation passed:', args.label)
            return
        response = client._http_client.post('/v2/experience-requests', headers=client._headers(), json=body, timeout=120)
        response.raise_for_status()
        data = response.json()
        save(args.study / (args.label + '-created.json'), data)
        index = args.study / 'requests.json'
        rows = json.loads(index.read_text()) if index.exists() else []
        row = dict(id=data['id'], label=args.label, n=args.n, candidate_side=args.side,
                   policy=args.policy, opponent=args.opponent, num_episodes=args.episodes)
        rows = [r for r in rows if r['id'] != row['id']] + [row]
        save(index, rows)
        print(json.dumps(row), flush=True)


def harvest(pair):
    row, study = pair
    with CoworldApiClient.from_login(server_url='https://softmax.com/api') as client:
        detail = get(client, '/v2/experience-requests/' + row['id']).json()
        save(study / (row['label'] + '.json'), detail)
        results = []
        for episode in detail['episodes']:
            expected = [row['policy'] if i // row['n'] == row['candidate_side'] else row['opponent'] for i in range(row['n'] * 2)]
            if episode['policy_version_ids'] != expected:
                raise ValueError(f"Unexpected resolved roster in {episode['id']}")
            if episode['coworld_version'] != '0.3.13':
                raise ValueError(f"Unexpected game version in {episode['id']}")
            if episode['status'] != 'completed':
                continue
            folder = study / 'hosted-artifacts' / episode['id']
            folder.mkdir(parents=True, exist_ok=True)
            for kind, name in [('results', 'results.json'), ('replay', 'replay.pwr')]:
                path = folder / name
                if not path.exists():
                    response = get(client, '/v2/episode-requests/' + episode['id'] + '/artifacts/' + kind)
                    tmp = path.with_suffix('.download')
                    tmp.write_bytes(response.content)
                    tmp.replace(path)
            if not row['label'].startswith('baseline-'):
                for slot in range(row['candidate_side'] * row['n'], (row['candidate_side'] + 1) * row['n']):
                    path = folder / f'policy-slot-{slot}.log'
                    if not path.exists():
                        response = get(client, '/v2/episode-requests/' + episode['id'] + '/' + row['policy'] + '/policy-logs/' + str(slot))
                        path.write_bytes(response.content)
            result = json.loads((folder / 'results.json').read_text())
            results.append(dict(label=row['label'], n=row['n'], candidate_side=row['candidate_side'], request_id=row['id'], episode_id=episode['id'], result=result))
        return {**row, 'status': detail['status'], 'counts': dict(Counter(e['status'] for e in detail['episodes'])), 'episodes': detail['episodes']}, results


def poll(args):
    while True:
        rows = json.loads((args.study / 'requests.json').read_text())
        with ThreadPoolExecutor(max_workers=2) as pool:
            measured = list(pool.map(harvest, [(r, args.study) for r in rows]))
        statuses = [m[0] for m in measured]
        save(args.study / 'status.json', statuses)
        save(args.study / 'hosted-results.json', [r for m in measured for r in m[1]])
        for status in statuses:
            print(json.dumps({k: status[k] for k in ['label', 'id', 'status', 'counts']}), flush=True)
        active = any(e['status'] in ['pending', 'running', 'queued', 'created', 'initializing'] for row in statuses for e in row['episodes'])
        # Parent status also covers not-yet-materialized children.
        active = active or any(row['status'] not in ['completed', 'failed', 'canceled', 'cancelled'] for row in statuses)
        if not args.watch or not active:
            break
        time.sleep(30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', required=True, type=Path)
    parser.add_argument('--create', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--label')
    parser.add_argument('--policy')
    parser.add_argument('--opponent')
    parser.add_argument('--side', type=int, choices=[0, 1])
    parser.add_argument('--n', type=int, choices=[1, 3], default=3)
    parser.add_argument('--episodes', type=int, choices=range(10, 21), default=10)
    parser.add_argument('--notes')
    args = parser.parse_args()
    args.study = args.study.resolve()
    args.study.mkdir(parents=True, exist_ok=True)
    if args.create:
        if not all([args.label, args.policy, args.opponent]) or args.side is None:
            parser.error('--create requires label, policy, opponent and side')
        create(args)
    else:
        poll(args)


if __name__ == '__main__':
    main()
