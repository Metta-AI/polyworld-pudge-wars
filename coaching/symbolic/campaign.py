"""Persistent semantic-policy research with fresh maps and recoverable rounds.

Confirmation data may inform retention, so it is not a permanently held-out test.
A final audit freezes the campaign and evaluates only its already-chosen policy.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
from contextlib import contextmanager
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import statistics
import sys
import platform
import uuid

from . import skills
from .evaluate import digest, play_cached, prepare, summarize
from .ir import binding_hash, binding_module, extract, generate, parse, render
from .search import Proposal, check_proposal, compare, fingerprint, promotion, propose


def save(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n')
    temporary.replace(path)


@contextmanager
def exclusive(directory):
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another process is already running this campaign') from error
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def reserve(state, label, count):
    """Allocate once and persist before work; all prior roles remain unavailable."""
    used = state['seed_ledger']
    chosen = []
    while len(chosen) < count:
        index = state['seed_counter']
        state['seed_counter'] += 1
        seed = int.from_bytes(hashlib.sha256(f"{state['id']}:{index}".encode()).digest()[:4], 'big') % (2**31 - 1)
        if str(seed) not in used:
            used[str(seed)] = label
            chosen.append(seed)
    return chosen


def runtime_hashes():
    root = Path(__file__).parent
    return {name: digest(root / name) for name in ('campaign.py', 'search.py', 'evaluate.py', 'ir.py', 'skills.py', 'skills_v2.py', 'spatial.py')} | {'python': sys.version, 'platform': platform.platform()}


def load_program(path):
    return parse(Path(path).read_text())


def import_run(directory, state, old_directory):
    old_directory = Path(old_directory).resolve()
    if (old_directory / 'campaign.json').exists():
        old = json.loads((old_directory / 'campaign.json').read_text())
        state['seed_ledger'].update({seed: 'imported:' + role for seed, role in old['seed_ledger'].items()})
        def matchups(value):
            return [(r['sha256'], r['class'], r['options']) for r in value['opponents']]
        compatible = (old['binding_hash'] == state['binding_hash'] and old['runner_sha256'] == state['runner_sha256']
                      and matchups(old) == matchups(state)
                      and all(old['protocol'][key] == state['protocol'][key] for key in ('n', 'ticks', 'goal')))
        for record in old['history']:
            record = dict(record, compatible=compatible and record.get('compatible', True))
            if 'ir_text' not in record and record.get('evidence'):
                evidence = Path(record['evidence'])
                if not evidence.is_absolute():evidence = old_directory / evidence
                source = evidence.parent / 'artifacts' / record['name'] / 'recovered.policy.md'
                if source.exists():record['ir_text'] = source.read_text()
            state['history'].append(record)
        save(directory / 'imported-campaign.json', old)
        return
    report = json.loads((old_directory / 'report.json').read_text())
    contract = report['contract']
    for role in ('train_seeds', 'validation_seeds'):
        for seed in contract[role]:
            state['seed_ledger'][str(seed)] = 'imported:' + role
    opponents = state['opponents']
    compatible = (len(opponents) == 1 and opponents[0]['sha256'] == contract['baseline_sha256']
                  and opponents[0]['class'] == 'BasePolicy' and not opponents[0]['options']
                  and state['runner_sha256'] == contract['runner_sha256']
                  and all(state['protocol'][k] == contract[v] for k, v in [('n', 'n'), ('ticks', 'max_ticks'), ('goal', 'goal')]))
    parent = load_program(old_directory / 'artifacts/support/recovered.policy.md')
    for label in ('short_lead', 'long_lead'):
        child = load_program(old_directory / 'artifacts' / label / 'recovered.policy.md')
        state['history'].append(dict(parent=fingerprint(parent), fingerprint=fingerprint(child), name=label,
            status='imported', compatible=compatible, evidence=str(old_directory / 'report.json'),
            ir_text=render(child),
            outcome='confirmation_rejected' if report['selected'] == label and report['retained'] != label else 'development_evidence',
            note='Prior evaluation is remembered; it is not counted as fresh confirmation.'))
    save(directory / 'imported-report.json', report)


def initialize(args, directory):
    protocol = dict(n=args.n or 2, ticks=args.ticks or 38400, goal=args.goal or 30,
                    development_seeds=args.development_seeds or 2, confirmation_seeds=args.confirmation_seeds or 6,
                    audit_seeds=args.audit_seeds or 8, candidates=args.candidates or 2,
                    minimum_confirmation_seeds=6, minimum_margin_gain=1.0,
                    interval='4000 deterministic bootstrap resamples of seed clusters; two-sided 95% percentile interval')
    inputs = directory / 'inputs'; inputs.mkdir(exist_ok=True)
    initial = args.initial or Path('coaching/policies/executable/support.policy.md')
    if args.initial is None and args.import_run and (args.import_run / 'campaign.json').exists():
        old = json.loads((args.import_run / 'campaign.json').read_text())
        initial = args.import_run / old['incumbent']
    elif args.initial is None and args.import_run:
        initial = args.import_run / 'next-iteration.policy.md'
    program = extract(generate(load_program(initial)))
    (inputs / 'initial.policy.md').write_text(render(program, origin='Code-derived campaign incumbent.'))
    runner = args.runner or Path('tmp/coaching/symbolic_match')
    shutil.copy2(runner, inputs / 'native_match')
    shutil.copy2(skills.__file__, inputs / 'skills.snapshot.py')
    if program.binding_version != skills.VERSION:
        shutil.copy2(binding_module(program).__file__, inputs / 'skills_v2.snapshot.py')
    configs = json.loads(args.opponents.read_text()) if args.opponents else {
        'base': dict(path='coworld/player/base.py', **{'class': 'BasePolicy'}, options={})}
    if not configs:
        raise ValueError('At least one frozen opponent is required')
    opponents = []
    for name, config in sorted(configs.items()):
        if not re.fullmatch('[a-z][a-z0-9_]*', name):
            raise ValueError('Invalid opponent name')
        path = inputs / f'{name}.py'
        shutil.copy2(config['path'], path)
        kind = config.get('class', 'BasePolicy')
        if kind not in ('Policy', 'BasePolicy') or not isinstance(config.get('options', {}), dict):
            raise ValueError('Opponent must expose Policy or BasePolicy with named options')
        opponents.append(dict(name=name, path=str(path.relative_to(directory)), sha256=digest(path),
                              **{'class': kind}, options=config.get('options', {})))
    state = dict(schema=1, id=uuid.uuid4().hex, protocol=protocol, opponents=opponents,
                 runner_sha256=digest(inputs / 'native_match'), binding_hash=program.binding_hash,
                 binding_version=program.binding_version, runtime=runtime_hashes(),
                 incumbent='inputs/initial.policy.md', incumbent_fingerprint=fingerprint(program),
                 initial_fingerprint=fingerprint(program),
                 seed_ledger={}, seed_counter=0, history=[], rounds=[], audit=None)
    state['initialization'] = dict(import_run=str(args.import_run.resolve()) if args.import_run else None,
                                  initial_input_hash=digest(initial), runner_input_hash=digest(runner),
                                  opponents_config_hash=digest(args.opponents) if args.opponents else None)
    if args.import_run:
        import_run(directory, state, args.import_run)
    state['replication'] = None
    if args.replicate:
        matches = [r for r in state['history'] if r.get('compatible', True) and r['parent'] == state['incumbent_fingerprint']
                   and (r['name'] == args.replicate or r['fingerprint'].startswith(args.replicate)) and 'ir_text' in r]
        unique = {r['fingerprint']: r for r in matches}
        if len(unique) != 1:
            raise ValueError('Replication must identify one compatible recorded candidate of this exact parent')
        record = next(iter(unique.values()))
        if any(r.get('replication') and r['fingerprint'] == record['fingerprint'] and r['parent'] == record['parent'] for r in state['history']):
            raise ValueError('This parent/candidate already had its one independent replication')
        for key in ('layer', 'hypothesis', 'prediction', 'allowed_channels'):
            if key not in record:raise ValueError('Replication requires the original semantic hypothesis and contract')
        state['replication'] = record
    state['audit_seeds'] = reserve(state, 'reserved-final-audit', protocol['audit_seeds'])
    save(directory / 'campaign.json', state)
    return state


def verify_inputs(directory, state):
    if runtime_hashes() != state['runtime'] or binding_hash(state.get('binding_version',skills.VERSION)) != state['binding_hash']:
        raise ValueError('Research implementation changed. Start a new campaign; do not mix protocols.')
    if digest(directory / 'inputs/native_match') != state['runner_sha256']:
        raise ValueError('Frozen native runner changed')
    for opponent in state['opponents']:
        if digest(directory / opponent['path']) != opponent['sha256']:
            raise ValueError('Frozen opponent changed')
    if fingerprint(load_program(directory / state['incumbent'])) != state['incumbent_fingerprint']:
        raise ValueError('Incumbent text changed outside the recorded lineage')
    if fingerprint(load_program(directory / 'inputs/initial.policy.md')) != state['initial_fingerprint']:
        raise ValueError('Original audit comparator changed')


def materialize(directory, relative, program):
    root = directory / relative
    root.mkdir(parents=True, exist_ok=True)
    source = root / 'source.policy.md'
    source.write_text(render(program, origin='Campaign proposal; see the adjacent round plan for hypothesis and scope.'))
    paths = prepare(source, root)
    return dict(policy=str(paths[0].relative_to(directory)), roundtrip=str(paths[1].relative_to(directory)),
                recovered=str((root / 'recovered.policy.md').relative_to(directory)), fingerprint=fingerprint(program))


def plan_round(directory, state):
    number = len(state['rounds'])
    root = Path('rounds') / f'{number:03d}'
    (directory / root).mkdir(parents=True, exist_ok=True)
    parent = load_program(directory / state['incumbent'])
    attempted = {(r['parent'], r['fingerprint']) for r in state['history'] if r.get('compatible', True)}
    record = state.get('replication')
    candidates = [Proposal(record['name'], parse(record['ir_text']), record['layer'], record['hypothesis'], record['prediction'], tuple(record['allowed_channels']))] if record else propose(parent, attempted, state['protocol']['candidates'])
    if not candidates:
        return None
    arms = {'parent': materialize(directory, root / 'artifacts/parent', parent)}
    proposals = []
    for candidate in candidates:
        record = candidate.record(parent)
        record['ir_text'] = render(candidate.program)
        record['replication'] = state.get('replication') is not None
        try:
            record['contracts'] = check_proposal(parent, candidate)
            arms[candidate.name] = materialize(directory, root / 'artifacts' / candidate.name, candidate.program)
        except ValueError as error:
            record['status'] = 'contract_rejected'
            record['reason'] = str(error)
        proposals.append(record)
    plan = dict(number=number, directory=str(root), parent_fingerprint=fingerprint(parent), arms=arms, proposals=proposals,
                development_seeds=[] if state.get('replication') else reserve(state, f'round-{number}-development', state['protocol']['development_seeds']),
                confirmation_seeds=reserve(state, f'round-{number}-confirmation', state['protocol']['confirmation_seeds']),
                kind='independent_replication' if state.get('replication') else 'search',
                status='planned', selection='Largest development paired mean kill-margin gain; parent wins ties.',
                retention='Six or more confirmation seed clusters; gain >=1; bootstrap lower bound >0; nondecreasing win rate; no opponent loses >2 margin.',
                frozen_protocol=state['protocol'])
    state['rounds'].append(plan)
    save(directory / 'campaign.json', state)
    save(directory / root / 'plan.json', plan)
    return plan


def make_jobs(directory, state, plan, phase, arms, seeds, execution='generated'):
    jobs = []
    for arm in arms:
        for seed in seeds:
            for opponent in state['opponents']:
                for side in (0, 1):
                    name = f'{phase}-{arm}-{seed}-{opponent["name"]}-{side}'
                    jobs.append(dict(out=str(directory / plan['directory'] / 'games' / name), phase=phase,
                        arm=arm, seed=seed, side=side, opponent=opponent['name'], execution=execution,
                        n=state['protocol']['n'], goal=state['protocol']['goal'], ticks=state['protocol']['ticks'],
                        runner=str(directory / 'inputs/native_match'), baseline=str(directory / opponent['path']),
                        baseline_class=opponent['class'], baseline_options=opponent['options'],
                        policy=str(directory / plan['arms'][arm]['policy']), roundtrip=str(directory / plan['arms'][arm]['roundtrip'])))
    return jobs


def execute(jobs, workers):
    rows = []
    with ProcessPoolExecutor(max_workers=workers) as pool:
        pending = [pool.submit(play_cached, job) for job in jobs]
        for task in as_completed(pending):
            row = task.result(); rows.append(row)
            print(json.dumps({k: row[k] for k in ('phase', 'arm', 'seed', 'side', 'opponent', 'ours', 'theirs')}), flush=True)
    return sorted(rows, key=lambda r: (r['arm'], r['seed'], r['opponent'], r['side']))


def throughput(rows):
    result = {}
    for name in sorted({r['arm'] for r in rows}):
        ratios = [r['candidate_decisions_per_second'] / r['reference_decisions_per_second']
                  for r in rows if r['arm'] == name and r.get('timed_decisions', 0) >= 1000]
        if ratios:
            result[name] = statistics.median(ratios)
    return result


def select_candidate(comparisons):
    # Independent of dictionary ordering after an atomic JSON checkpoint/reload.
    improving = [name for name, evidence in comparisons.items() if evidence['mean_margin_difference'] > 0]
    return min(improving, key=lambda name: (-comparisons[name]['mean_margin_difference'], name)) if improving else 'parent'


def verify_plan(directory, plan):
    for arm in plan['arms'].values():
        for kind in ('policy', 'roundtrip'):
            if fingerprint(extract((directory / arm[kind]).read_text())) != arm['fingerprint']:
                raise ValueError('Planned executable changed; cannot resume this experiment')
        if fingerprint(load_program(directory / arm['recovered'])) != arm['fingerprint']:
            raise ValueError('Recovered IR changed outside the recorded plan')


def finish_round(directory, state, plan, workers):
    root = directory / plan['directory']
    verify_plan(directory, plan)
    # Saved selection is not recomputed from confirmation or audit evidence.
    development = execute(make_jobs(directory, state, plan, 'development', list(plan['arms']), plan['development_seeds']), workers) if len(plan['arms']) > 1 and plan['development_seeds'] else []
    comparisons = {name: compare(development, name) for name in plan['arms'] if name != 'parent'} if development else {}
    selected = next((name for name in plan['arms'] if name != 'parent'), 'parent') if plan['kind'] == 'independent_replication' else select_candidate(comparisons)
    selection = dict(selected=selected, comparisons=comparisons, summaries={name: summarize([r for r in development if r['arm'] == name]) for name in plan['arms']} if development else {})
    selection_path = root / 'selection.json'
    if selection_path.exists() and json.loads(selection_path.read_text()) != selection:
        raise ValueError('Persisted development selection changed')
    save(selection_path, selection)
    confirmation = []; repeats = []; evidence = None
    gate = dict(accepted=False, reasons=['No candidate improved development performance.'])
    runtime_failure = any(value < .5 for value in throughput(development).values())
    if selected != 'parent' and not runtime_failure:
        confirmation = execute(make_jobs(directory, state, plan, 'confirmation', ['parent', selected], plan['confirmation_seeds']), workers)
        evidence = compare(confirmation, selected)
        gate = promotion(evidence, state['protocol']['minimum_confirmation_seeds'], state['protocol']['minimum_margin_gain'])
        # Costly complete-trajectory repetition only for a potential promotion.
        if gate['accepted']:
            repeats = execute(make_jobs(directory, state, plan, 'regenerated', [selected], plan['confirmation_seeds'][:1], 'regenerated'), workers)
            for row in repeats:
                first = next(r for r in confirmation if r['arm'] == selected and r['seed'] == row['seed'] and r['side'] == row['side'] and r['opponent'] == row['opponent'])
                if any(row[k] != first[k] for k in ('trajectory_sha256', 'score', 'terminal_tick')):
                    raise ValueError('Regenerated controller changed a complete trajectory')
    retained = selected if gate['accepted'] else 'parent'
    rows = development + confirmation + repeats
    runtime_failure = runtime_failure or any(value < .5 for value in throughput(rows).values())
    if runtime_failure:
        retained = 'parent'; gate = dict(accepted=False, reasons=['Candidate throughput below half of reference; inspect runtime before model claims.'])
    verify_inputs(directory, state)
    next_path = root / 'next-iteration.policy.md'
    shutil.copy2(directory / plan['arms'][retained]['recovered'], next_path)
    report = dict(number=plan['number'], selection=selection, confirmation=evidence, gate=gate, retained=retained,
                  parent=plan['parent_fingerprint'], next_fingerprint=plan['arms'][retained]['fingerprint'],
                  games=len(rows), roundtrip_actions=sum(r['roundtrip_actions'] for r in rows),
                  roundtrip_mismatches=sum(r['roundtrip_mismatches'] for r in rows), runtime_failure=runtime_failure,
                  warmed_throughput_ratios=throughput(rows),
                  summaries={phase: {name: summarize([r for r in group if r['arm'] == name]) for name in sorted({r['arm'] for r in group})}
                             for phase, group in [('development', development), ('confirmation', confirmation)]},
                  limitation='Template-authored semantic search. Confirmation informs retention and is consumed; it is not the final audit.')
    save(root / 'report.json', report)
    brief = f'# Round {plan["number"]}: evidence for the next hypothesis\n\n'
    brief += f'Development selected **{selected}**; retained **{retained}**.\n\n'
    for proposal in plan['proposals']:
        brief += f'## {proposal["name"]} ({proposal["layer"]})\n\n{proposal["hypothesis"]}\n\nPrediction: {proposal["prediction"]}\n\n'
    brief += 'Retention evidence: ' + '; '.join(gate['reasons'] or ['Passed the exploratory paired gate.']) + '\n\n'
    brief += 'A rejection is evidence about this exact parent/change/protocol. It does not prove the concept universally wrong. An unsupported distinction needs new grounded predicates or skills, versioned contracts, and a new campaign.\n'
    (root / 'research-brief.md').write_text(brief)
    for record in plan['proposals']:
        record = dict(record)
        if record['status'] != 'contract_rejected':
            inconclusive = gate['reasons'] == ['paired interval includes no improvement']
            record['status'] = 'accepted' if record['name'] == retained else ('inconclusive' if inconclusive else 'confirmation_rejected') if record['name'] == selected else 'development_rejected'
        record['evidence'] = str((root / 'report.json').relative_to(directory))
        state['history'].append(record)
    plan['status'] = 'complete'
    state['incumbent'] = str(next_path.relative_to(directory))
    state['incumbent_fingerprint'] = report['next_fingerprint']
    save(directory / 'campaign.json', state)
    return report


def audit(directory, state, workers):
    """An audit seals this campaign; subsequent tuning requires a new campaign."""
    if any(r['status'] != 'complete' for r in state['rounds']):
        raise ValueError('Finish the pending round before auditing')
    if state['audit'] is None:
        root = Path('audit')
        arms = {'parent': materialize(directory, root / 'artifacts/parent', load_program(directory / 'inputs/initial.policy.md')),
                'final': materialize(directory, root / 'artifacts/final', load_program(directory / state['incumbent']))}
        state['audit'] = dict(directory='audit', arms=arms, status='started')
        save(directory / 'campaign.json', state)
    plan = state['audit']
    verify_plan(directory, plan)
    rows = execute(make_jobs(directory, state, plan, 'audit', ['parent', 'final'], state['audit_seeds']), workers)
    evidence = compare(rows, 'final')
    save(directory / 'audit/report.json', dict(evidence=evidence, games=len(rows), changes_policy=False,
        warning='Descriptive final comparison on previously unused seeds; it does not promote a policy.'))
    state['audit']['status'] = 'complete'
    save(directory / 'campaign.json', state)
    print(json.dumps(evidence, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--rounds', type=int, default=1, help='Total completed rounds desired, including prior rounds')
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--import-run', type=Path)
    parser.add_argument('--replicate', help='Run one fixed recorded hypothesis on new confirmation maps, without another search')
    parser.add_argument('--initial', type=Path)
    parser.add_argument('--runner', type=Path)
    parser.add_argument('--opponents', type=Path, help='JSON mapping names to path, class and options')
    for name in ('development-seeds', 'confirmation-seeds', 'audit-seeds', 'candidates', 'n', 'ticks', 'goal'):
        parser.add_argument('--' + name, type=int)
    parser.add_argument('--audit', action='store_true')
    args = parser.parse_args()
    if args.rounds < 0 or args.jobs < 1 or any(value is not None and value < 1 for value in
            (args.development_seeds, args.confirmation_seeds, args.audit_seeds, args.candidates, args.n, args.ticks, args.goal)):
        parser.error('Counts and game settings must be positive')
    directory = args.out.resolve()
    with exclusive(directory):
        state_path = directory / 'campaign.json'
        state = json.loads(state_path.read_text()) if state_path.exists() else initialize(args, directory)
        for key, path in [('initial_input_hash', args.initial), ('runner_input_hash', args.runner), ('opponents_config_hash', args.opponents)]:
            if path is not None and digest(path) != state['initialization'][key]:
                parser.error('Initialization input changed; start a new campaign: ' + key)
        if args.import_run and str(args.import_run.resolve()) != state['initialization']['import_run']:
            parser.error('Cannot add new imported history to a running campaign')
        if args.replicate and (state.get('replication') is None or (state['replication']['name'] != args.replicate and not state['replication']['fingerprint'].startswith(args.replicate))):
            parser.error('Replication identity differs from the frozen campaign')
        if state.get('replication') and args.rounds > 1:
            parser.error('A replication campaign permits one fixed experiment')
        for key in ('development_seeds', 'confirmation_seeds', 'audit_seeds', 'candidates', 'n', 'ticks', 'goal'):
            value = getattr(args, key)
            if value is not None and value != state['protocol'][key]:
                parser.error('Cannot change a running campaign protocol: ' + key)
        verify_inputs(directory, state)
        if args.audit:
            audit(directory, state, args.jobs)
            return
        if state['audit'] is not None:
            parser.error('This campaign is sealed for audit; start a new campaign to continue research')
        while sum(r['status'] == 'complete' for r in state['rounds']) < args.rounds:
            plan = next((r for r in state['rounds'] if r['status'] != 'complete'), None) or plan_round(directory, state)
            if plan is None:
                print('Supported proposal space exhausted. Ground a new hypothesis before another campaign.')
                break
            report = finish_round(directory, state, plan, args.jobs)
            print(json.dumps(dict(round=report['number'], selected=report['selection']['selected'], retained=report['retained'],
                                  gate=report['gate'], games=report['games'], report=str(directory / plan['directory'] / 'report.json'))), flush=True)
        print('Current code-derived IR:', directory / state['incumbent'])


if __name__ == '__main__':
    main()
