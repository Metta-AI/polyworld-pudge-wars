#!/usr/bin/env python3
"""Compare completed, fixed-roster XP arms using official results.

Fresh generated seeds are independent, not paired. Report Wilson win-rate
intervals, a Newcombe interval for their difference, and two-sided Fisher's
exact test (wins versus non-wins). Screening and confirmation stay separate.
"""
import argparse
from collections import Counter
import json
import math
from pathlib import Path
import random
from statistics import mean


def wilson(wins, total):
    if not 0 <= wins <= total or total <= 0:
        raise ValueError('Require a positive sample with valid win count')
    z = 1.959963984540054
    p = wins / total
    denominator = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denominator
    radius = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / denominator
    return [max(0, center - radius), min(1, center + radius)]


def fisher_exact(a, b, c, d):
    """Two-sided fixed-margin test for table [[a,b],[c,d]]."""
    if any(x < 0 or int(x) != x for x in [a, b, c, d]):
        raise ValueError('Counts must be nonnegative integers')
    n1, n2, successes = a + b, c + d, a + c
    if not n1 or not n2:
        raise ValueError('Both arms must have observations')
    denominator = math.comb(n1 + n2, successes)
    weight = lambda k: math.comb(n1, k) * math.comb(n2, successes - k)
    observed = weight(a)
    return min(1.0, sum(weight(k) for k in range(max(0, successes - n2), min(n1, successes) + 1)
                        if weight(k) <= observed) / denominator)


def independent_rows(rows, repeated_seeds):
    selected, excluded, seen = [], [], set()
    for row in sorted(rows, key=lambda r: r['episode_id']):
        seed = row['result']['seed']
        if seed in seen:
            if repeated_seeds == 'reject':
                raise ValueError('Repeated seed: independent-sample assumptions require review')
            excluded.append(dict(episode_id=row['episode_id'], seed=seed, candidate_side=row['candidate_side']))
        else:
            selected.append(row)
            seen.add(seed)
    return selected, excluded


def describe(rows):
    outcomes, banks, margins = Counter(), {}, []
    for row in rows:
        result = row['result']
        score = result['scores'][row['candidate_side'] * row['n']]
        outcome = {1: 'wins', 0: 'losses', 0.5: 'draws'}[score]
        outcomes[outcome] += 1
        bank = ['west', 'east'][row['candidate_side']]
        banks.setdefault(bank, Counter())[outcome] += 1
        margin = result['west_kills'] - result['east_kills']
        margins.append(margin if row['candidate_side'] == 0 else -margin)
    return dict(games=len(rows), **{key: outcomes[key] for key in ['wins', 'losses', 'draws']},
                banks=banks, win_rate=outcomes['wins'] / len(rows), mean_kill_margin=mean(margins), kill_margins=margins)


def margin_difference_interval(baseline, candidate):
    """Descriptive independent-episode bootstrap; never pair generated seeds."""
    rng = random.Random(9152026)
    draws = sorted(mean(rng.choices(candidate, k=len(candidate))) -
                   mean(rng.choices(baseline, k=len(baseline))) for _ in range(10000))
    return [draws[249], draws[9749]]


def summarize(study, prefix, repeated_seeds='reject', game_version='0.3.13'):
    requests = [r for r in json.loads((study / 'status.json').read_text()) if r['label'].startswith(prefix)]
    if not requests:
        raise ValueError(f'No requests for {prefix}')
    if len({(r['policy'], r['opponent'], r['n']) for r in requests}) != 1:
        raise ValueError(f'Mixed policies, opponents or variants in {prefix}')
    expected = sum(r['num_episodes'] for r in requests)
    for request in requests:
        if request['status'] != 'completed' or request['counts'] != {'completed': request['num_episodes']}:
            raise ValueError(f"Incomplete or failed request: {request['label']} {request['counts']}")
        if len(request['episodes']) != request['num_episodes']:
            raise ValueError('Episode metadata count mismatch')
        roster = [request['policy'] if i // request['n'] == request['candidate_side'] else request['opponent']
                  for i in range(2 * request['n'])]
        for episode in request['episodes']:
            if episode['policy_version_ids'] != roster or episode['coworld_version'] != game_version:
                raise ValueError('Resolved roster or game mismatch')
    request_ids = {r['id'] for r in requests}
    rows = [r for r in json.loads((study / 'hosted-results.json').read_text()) if r['request_id'] in request_ids]
    if len(rows) != expected or len({r['episode_id'] for r in rows}) != expected:
        raise ValueError('Missing or duplicate harvested episodes')
    if {r['episode_id'] for r in rows} != {e['id'] for r in requests for e in r['episodes']}:
        raise ValueError('Harvested episode identity mismatch')
    selected, excluded = independent_rows(rows, repeated_seeds)
    descriptive = describe(selected)
    return dict(prefix=prefix, policy=requests[0]['policy'], opponent=requests[0]['opponent'], game_version=game_version,
                players_per_team=requests[0]['n'], **descriptive,
                win_rate_95ci=wilson(descriptive['wins'], len(selected)), requests=sorted(request_ids),
                episode_ids=sorted(r['episode_id'] for r in selected),
                seeds=sorted(r['result']['seed'] for r in selected),
                repeated_seed_rule=repeated_seeds, excluded_duplicate_episodes=excluded,
                all_episode_ids=sorted(r['episode_id'] for r in rows), all_games=describe(rows))


def compare(baseline, candidate, minimum_unique=0):
    if baseline.get('game_version') != candidate.get('game_version'):
        raise ValueError('Comparisons require the same game version')
    if (baseline['opponent'], baseline['players_per_team']) != (candidate['opponent'], candidate['players_per_team']):
        raise ValueError('Comparisons require the same opponent and variant')
    if set(baseline['episode_ids']) & set(candidate['episode_ids']):
        raise ValueError('Arms overlap')
    if set(baseline['seeds']) & set(candidate['seeds']):
        raise ValueError('Cross-arm repeated seeds: review dependence before testing')
    b, c = baseline['win_rate'], candidate['win_rate']
    bl, bu = baseline['win_rate_95ci']
    cl, cu = candidate['win_rate_95ci']
    p = fisher_exact(candidate['wins'], candidate['games'] - candidate['wins'],
                     baseline['wins'], baseline['games'] - baseline['wins'])
    margin = candidate['mean_kill_margin'] - baseline['mean_kill_margin']
    all_margin = candidate['all_games']['mean_kill_margin'] - baseline['all_games']['mean_kill_margin']
    adequate = min(baseline['games'], candidate['games']) >= minimum_unique
    return dict(baseline=baseline, candidate=candidate, win_rate_difference=c - b,
                win_rate_difference_95ci=[c - b - math.hypot(c - cl, bu - b), c - b + math.hypot(cu - c, b - bl)],
                mean_kill_margin_difference=margin, fisher_exact_two_sided_p=p,
                mean_kill_margin_difference_95ci=margin_difference_interval(baseline['kill_margins'], candidate['kill_margins']),
                all_games_mean_kill_margin_difference=all_margin, minimum_unique=minimum_unique,
                adequate_distinct_seeds=adequate,
                meets_confirmation_outcome_rule=adequate and c > b and p < 0.05 and margin > 0 and all_margin > 0,
                methods='One episode per distinct generated seed; Wilson 95% win-rate intervals; Newcombe difference interval; two-sided Fisher exact wins vs non-wins. Score-margin difference uses 10000 independent-episode bootstrap resamples, RNG seed 9152026. All games also reported descriptively. Mechanism and guardrails assessed separately.')


def support_rates(paths, expected_ids):
    rows = [row for path in paths for row in json.loads(path.read_text())['episodes']]
    if len(rows) != len(expected_ids) or {r['episode_id'] for r in rows} != set(expected_ids):
        raise ValueError('Mechanism surveys must cover exactly the compared episodes')
    minutes = sum(row['result']['end_tick'] / 32 / 60 for row in rows)
    totals, positions, healing = Counter(), Counter(), Counter()
    exposed_games = 0
    for row in rows:
        team = next(t for t in row['teams'] if t['role'] == 'candidate')
        if 'effective_healing' not in team:
            raise ValueError('Effective healing requires an instrumented survey')
        totals.update({k: team[k] for k in ['runes', 'hooks_thrown']})
        totals['enemy_catches'] += team['catches'].get('enemy', 0)
        positions.update(team['position_samples'])
        healing.update(team['effective_healing'])
        exposed_games += team['effective_healing'].get('deliberate_contacts', 0) > 0
    denominator = positions['all_three_alive_samples']
    return dict(games=len(rows), runes_per_minute=totals['runes'] / minutes,
                enemy_catches_per_minute=totals['enemy_catches'] / minutes,
                hooks_per_minute=totals['hooks_thrown'] / minutes,
                all_three_cluster_fraction=positions['all_three_within_12_samples'] / denominator if denominator else None,
                healing_hp_per_alive_player_minute=healing['restored_hp'] * 240 / positions['alive_player_samples'],
                deliberate_healing_games=exposed_games, healing=dict(healing),
                sampling='Clustering and alive time sampled every eight ticks (4 Hz); healing read directly from simulation operations.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--study', required=True, type=Path)
    parser.add_argument('--baseline', required=True, help='Exact distinguishing label prefix')
    parser.add_argument('--candidate', required=True, help='Exact distinguishing label prefix')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--baseline-survey', type=Path, action='append', default=[])
    parser.add_argument('--candidate-survey', type=Path, action='append', default=[])
    parser.add_argument('--repeated-seeds', choices=['reject', 'first-id'], default='reject',
                        help='Pre-record the choice before confirmation. first-id keeps the smallest episode ID for each seed.')
    parser.add_argument('--minimum-unique', type=int, default=0, help='Pre-recorded minimum distinct seeds per arm for a verdict')
    parser.add_argument('--game-version', default='0.3.13', help='Exact expected version in every resolved episode')
    args = parser.parse_args()
    report = compare(summarize(args.study, args.baseline, args.repeated_seeds, args.game_version),
                     summarize(args.study, args.candidate, args.repeated_seeds, args.game_version), args.minimum_unique)
    for name in ['baseline', 'candidate']:
        paths = getattr(args, name + '_survey')
        if paths:
            report[name]['mechanism'] = support_rates(paths, report[name]['all_episode_ids'])
    with args.output.open('x') as stream:
        stream.write(json.dumps(report, indent=2) + '\n')
    print(json.dumps({k: v for k, v in report.items() if k not in ['baseline', 'candidate']}, indent=2))


if __name__ == '__main__':
    main()
