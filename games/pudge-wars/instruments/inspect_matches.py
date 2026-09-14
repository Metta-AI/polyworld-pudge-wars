#!/usr/bin/env python3
"""Verify hosted Pudge replays and survey team skills without rerunning policies.

See ../skills/replay-inspection/README.md for artifact and metric contracts.
Only Python's standard library is required. The decoder must match the game.
"""

from __future__ import annotations

import argparse
import ast
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import time


def sha256(path: Path) -> str:
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def healing_metrics(summary: dict, events: Path, decoder_log: str, artifact_folder: Path) -> dict:
    """Exact healing operation totals, with conservative request→launch joins."""
    if 'HEAL_TRACE_V1' not in decoder_log:
        raise ValueError('Decoder must be built with HEAL_TRACE_V1 instrumentation')
    teams = {p['id']: 0 if p['team'] == 'west' else 1 for p in summary['players']}
    requests = []
    log_files = list(artifact_folder.glob('policy-slot-*.log'))
    for path in log_files:
        text = path.read_text()
        # The hosted log endpoint currently wraps bytes in their Python repr.
        # literal_eval decodes that data representation without executing code.
        if text.startswith(("b'", 'b"')):
            value = ast.literal_eval(text)
            if not isinstance(value, bytes):
                raise ValueError(f'Unexpected policy log encoding: {path}')
            text = value.decode('utf-8')
        for line in text.splitlines():
            if 'policy_trace ' in line:
                requests.extend(e for e in json.loads(line.split('policy_trace ', 1)[1]) if e['event'] == 'heal_request')
    requests.sort(key=lambda e: e['tick'])
    matched = set()
    with events.open() as source:
        for line in source:
            event = json.loads(line)
            if event['ev'] != 'hook_launched':
                continue
            for request in reversed(requests):
                age = event['t'] - request['tick']
                if age > 32:
                    break
                if age >= 0 and event['id'] == request['healer'] and math.dist(event['aim'], request['at']) <= 0.03:
                    matched.add((event['hookId'], request['recipient']))
                    break
    counts = [Counter(), Counter()]
    for request in requests:
        counts[teams[request['healer']]]['requests'] += 1
    contacts = []
    for line in decoder_log.splitlines():
        if not line.startswith('HEAL '):
            continue
        tick, owner, recipient, before, after, hook_id = map(int, line.split()[1:])
        restored = after - before
        if teams[owner] != teams[recipient] or not 0 <= restored <= 120:
            raise ValueError('Invalid healing trace operation')
        total = counts[teams[owner]]
        total['contacts'] += 1
        total['restored_hp'] += restored
        total['wasted_hp'] += 120 - restored
        total['zero_hp_contacts'] += restored == 0
        deliberate = (hook_id, recipient) in matched
        if deliberate:
            total['deliberate_contacts'] += 1
            total['deliberate_hp'] += restored
        contacts.append(dict(tick=tick, owner=owner, recipient=recipient, restored_hp=restored, deliberate=deliberate, hook_id=hook_id))
    return dict(teams=[dict(c) for c in counts], policy_log_files=len(log_files), contacts=contacts)


def survey(summary: dict, events: Path, candidate_side: int) -> dict:
    teams = {p['id']: 0 if p['team'] == 'west' else 1 for p in summary['players']}
    aggregates = []
    for team in range(2):
        players = [p for p in summary['players'] if teams[p['id']] == team]
        hooks = [h for h in summary['hooks'] if teams[h['owner']] == team]
        catches = Counter()
        for hook in hooks:
            if hook['result'] == 'hit':
                victim_team = teams.get(hook.get('victim'))
                catches['friendly' if victim_team == team else 'enemy' if victim_team is not None else 'unknown'] += 1
        deaths = [k for k in summary['kills'] if teams[k['victim']] == team]
        attribution = Counter()
        for kill in deaths:
            killer = kill['killer']
            relation = 'self' if killer == kill['victim'] else 'teammate' if teams.get(killer) == team else 'enemy' if killer in teams else 'unknown'
            attribution[relation + ':' + kill['cause']] += 1
        aggregates.append({
            'role': 'candidate' if team == candidate_side else 'opponent',
            'score': summary['score']['west' if team == 0 else 'east'],
            'kills': sum(p['kills'] for p in players),
            'deaths': sum(p['deaths'] for p in players),
            'hooks_thrown': sum(p['hooksThrown'] for p in players),
            'reported_hooks_landed': sum(p['hooksLanded'] for p in players),
            'hook_records': len(hooks),
            'hook_resolutions': dict(Counter(h['result'] for h in hooks)),
            'catches': dict(catches),
            'headshots': sum(p['headshots'] for p in players),
            'denies': sum(p['denies'] for p in players),
            'runes': sum(p['runes'] for p in players),
            'death_attribution_estimate': dict(attribution),
            'points_unspent': sum(p['pointsUnspent'] for p in players),
            'damage_taken_estimate': dict(sum((Counter(p['damageTaken']) for p in players), Counter())),
            'damage_dealt_estimate': dict(sum((Counter(p['damageDealt']) for p in players), Counter())),
            'position_samples': Counter(),
            'death_layer_samples': Counter(),
        })
    last_state = None
    with events.open() as source:
        for line in source:
            event = json.loads(line)
            if event['ev'] == 'kill' and last_state is not None:
                victim = next(p for p in last_state['p'] if p['id'] == event['victim'])
                team = teams[victim['id']]
                layer = 'own_bank' if victim['lay'] == team else 'enemy_bank' if victim['lay'] == 1 - team else 'river' if victim['lay'] == 2 else 'other'
                if event['t'] - last_state['t'] > 8:
                    layer = 'unknown'
                aggregates[team]['death_layer_samples'][layer] += 1
            if event['ev'] != 'state':
                continue
            last_state = event
            carried = {h['victim'] for h in event.get('hooks', []) if h['victim']}
            for team, result in enumerate(aggregates):
                alive = [p for p in event['p'] if p['alive'] and teams[p['id']] == team]
                counts = result['position_samples']
                counts['alive_player_samples'] += len(alive)
                counts['enemy_bank_player_samples'] += sum(p['lay'] == 1 - team for p in alive)
                counts['river_player_samples'] += sum(p['lay'] == 2 for p in alive)
                counts['unhooked_ready_player_samples'] += sum(p['cd'] == 0 and p['windup'] == 0 and p['id'] not in carried for p in alive)
                if len(alive) == 3:
                    counts['all_three_alive_samples'] += 1
                    pairs = [math.hypot(a['x'] - b['x'], a['y'] - b['y']) for i, a in enumerate(alive) for b in alive[i + 1:]]
                    counts['all_three_within_12_samples'] += max(pairs) <= 12
                    counts['all_three_within_12_own_bank_samples'] += max(pairs) <= 12 and all(p['lay'] == team for p in alive)
                    counts['all_three_within_12_north_samples'] += max(pairs) <= 12 and all(p['y'] < 32 for p in alive)
    # Score swings locate useful stretches; they do not attribute a mechanism.
    swings = []
    kills = summary['kills']
    for i, kill in enumerate(kills):
        prior = next((k['score'] for k in reversed(kills[:i]) if k['t'] <= kill['t'] - 1920), [0, 0])
        delta = (kill['score'][candidate_side] - prior[candidate_side]
                 - kill['score'][1 - candidate_side] + prior[1 - candidate_side])
        swings.append({'end_tick': kill['t'], 'start_tick': max(0, kill['t'] - 1920), 'candidate_kill_margin_change': delta})
    return {'teams': aggregates, 'worst_60_seconds': min(swings, key=lambda x: x['candidate_kill_margin_change']) if swings else None}


def inspect(row: dict, args: argparse.Namespace) -> dict:
    episode = row['episode_id']
    if not re.fullmatch(r'ereq_[A-Za-z0-9-]+', episode):
        raise ValueError(f'Unexpected episode ID: {episode!r}')
    replay = args.replay_root / episode / 'replay.pwr'
    folder = args.output / episode
    folder.mkdir()
    log_path = folder / 'decoder.log'
    with log_path.open('w') as log:
        subprocess.run([str(args.decoder), '--replay', str(replay), '--duellog', str(folder / 'decoded')],
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    log = log_path.read_text()
    if 'replay verified: every tick matched' not in log:
        raise ValueError(f'{episode}: decoder did not verify every tick; see {log_path}')
    action_count = re.search(r'replay: (\d+)/(\d+) actions', log)
    if action_count is None or action_count[1] != action_count[2]:
        raise ValueError(f'{episode}: incomplete action playback')
    summaries = list((folder / 'decoded').glob('match_*/summary.json'))
    if len(summaries) != 1:
        raise ValueError(f'{episode}: expected exactly one decoded summary')
    summary = json.loads(summaries[0].read_text())
    official = row['result']
    checks = {
        'seed': (summary['seed'], official['seed']),
        'end_tick': (summary['ticks'], official['end_tick']),
        'west_kills': (summary['score']['west'], official['west_kills']),
        'east_kills': (summary['score']['east'], official['east_kills']),
        'kill_goal': (summary['killGoal'], official['kill_goal']),
    }
    for field, (actual, expected) in checks.items():
        if actual != expected:
            raise ValueError(f'{episode}: {field} {actual} != official {expected}')
    actual_players = {p['seat']: p for p in summary['players']}
    if set(actual_players) != {p['slot'] for p in official['per_seat']}:
        raise ValueError(f'{episode}: seat mismatch')
    for player in official['per_seat']:
        actual = actual_players[player['slot']]
        for local, remote in [('kills', 'kills'), ('deaths', 'deaths'), ('hooksThrown', 'hooks_thrown'), ('hooksLanded', 'hooks_landed')]:
            if actual[local] != player[remote]:
                raise ValueError(f'{episode}: seat {player["slot"]} {local} mismatch')
    output = {**row, 'replay_sha256': sha256(replay), 'verified_actions': int(action_count[1]),
              'summary': str(summaries[0]), **survey(summary, summaries[0].with_name('events.jsonl'), row['candidate_side'])}
    if args.healing_trace:
        healing = healing_metrics(summary, summaries[0].with_name('events.jsonl'), log, replay.parent)
        for i, team in enumerate(output['teams']):
            team['effective_healing'] = healing['teams'][i]
        output['healing_trace'] = healing
    (folder / 'metrics.json').write_text(json.dumps(output, indent=2) + '\n')
    print(f'{episode}: every tick verified; {summary["score"]}', flush=True)
    return output


def aggregate(rows: list[dict]) -> dict:
    output = {}
    for subset in ['all', 'wins', 'losses']:
        chosen = [r for r in rows if subset == 'all' or (r['result']['scores'][r['candidate_side'] * r['n']] == 1 if subset == 'wins' else r['result']['scores'][r['candidate_side'] * r['n']] == 0)]
        group = {'episodes': len(chosen), 'duration_minutes': sum(r['result']['end_tick'] / 32 / 60 for r in chosen)}
        for role in ['candidate', 'opponent']:
            total = Counter()
            maps = {name: Counter() for name in ['hook_resolutions', 'catches', 'death_attribution_estimate', 'damage_taken_estimate', 'damage_dealt_estimate', 'position_samples', 'death_layer_samples', 'effective_healing']}
            for row in chosen:
                team = next(t for t in row['teams'] if t['role'] == role)
                for key, value in team.items():
                    if key in maps:
                        maps[key].update(value)
                    elif isinstance(value, int):
                        total[key] += value
            group[role] = {**total, **{k: dict(v) for k, v in maps.items()}}
        output[subset] = group
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--results', required=True, type=Path, help='hosted-results.json list with episode IDs, candidate_side, n and official result')
    parser.add_argument('--replay-root', required=True, type=Path, help='Contains EPISODE_ID/replay.pwr')
    parser.add_argument('--decoder', required=True, type=Path, help='Matching headless Pudge binary')
    parser.add_argument('--game-source', required=True, help='Exact game source commit or other immutable identity')
    parser.add_argument('--output', required=True, type=Path, help='Fresh output directory; existing directories are rejected')
    parser.add_argument('--label-prefix', default='')
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--healing-trace', action='store_true', help='Require direct-operation healing instrumentation in the decoder')
    parser.add_argument('--watch', action='store_true', help='Inspect newly harvested games until the complete requested arm is verified')
    parser.add_argument('--expected-episodes', type=int, help='Required final arm size in watch mode')
    args = parser.parse_args()
    if args.workers < 1:
        parser.error('--workers must be positive')
    if args.watch and (not args.expected_episodes or not args.label_prefix):
        parser.error('--watch requires a positive --expected-episodes and distinguishing --label-prefix')
    for key in ['results', 'replay_root', 'decoder', 'output']:
        setattr(args, key, getattr(args, key).resolve())
    args.output.mkdir(parents=True, exist_ok=False)
    manifest = {'game_source': args.game_source, 'instrument_sha256': sha256(Path(__file__)), 'decoder_sha256': sha256(args.decoder), 'label_prefix': args.label_prefix, 'watch': args.watch}
    measured, known = [], set()
    while True:
        source = args.results.read_bytes()
        rows = [r for r in json.loads(source) if r['label'].startswith(args.label_prefix)]
        if len({r['episode_id'] for r in rows}) != len(rows) or (not rows and not args.watch):
            parser.error('Select a nonempty set of unique episodes')
        if not known <= {r['episode_id'] for r in rows}:
            raise ValueError('Previously inspected episodes disappeared from harvested results')
        complete = not args.watch
        if args.watch:
            status_path = args.results.with_name('status.json')
            age = time.time() - status_path.stat().st_mtime
            if age > 180:
                print(f'Harvester status is {age:.0f} seconds old; check the XP watcher/network connection', flush=True)
            statuses = json.loads(status_path.read_text())
            selected = [r for r in statuses if r['label'].startswith(args.label_prefix)]
            if sum(r['num_episodes'] for r in selected) != args.expected_episodes:
                raise ValueError('Requested arm size does not match --expected-episodes')
            if any(any(s in ['failed', 'canceled', 'cancelled'] for s in r['counts']) for r in selected):
                raise ValueError('Arm contains failed/canceled episodes; investigate before drawing conclusions')
            complete = len(rows) == args.expected_episodes and all(r['status'] == 'completed' for r in selected)
        pending = [r for r in rows if r['episode_id'] not in known]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            measured.extend(pool.map(lambda row: inspect(row, args), pending))
        known.update(r['episode_id'] for r in pending)
        manifest.update(results_sha256=hashlib.sha256(source).hexdigest(), episodes=sorted(known))
        (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        if complete:
            break
        (args.output / 'progress.json').write_text(json.dumps(dict(verified=len(known), expected=args.expected_episodes)) + '\n')
        print(f'Verified {len(known)}/{args.expected_episodes}; waiting for remaining episodes', flush=True)
        time.sleep(20)
    report = {'provenance': manifest, 'aggregate': aggregate(measured), 'episodes': measured}
    (args.output / 'survey.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'Wrote {args.output / "survey.json"}', flush=True)


if __name__ == '__main__':
    main()
