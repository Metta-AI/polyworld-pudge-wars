#!/usr/bin/env python3
"""Full released-engine JSON regression game; never a hosted win-rate oracle."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
from coworld.player.base import BasePolicy


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--arm', choices=['healing', 'spacing', 'combined'], required=True)
    parser.add_argument('--seed', type=int, required=True)
    parser.add_argument('--side', type=int, choices=[0, 1], required=True)
    parser.add_argument('--n', type=int, choices=[1, 3], default=3)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('frozen_base', args.baseline)
    frozen = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = frozen
    spec.loader.exec_module(frozen)
    bots = [BasePolicy(heal_allies=args.arm in ['healing', 'combined'], spread_fishing=args.arm in ['spacing', 'combined'], trace=True)
            if i // args.n == args.side else frozen.BasePolicy() for i in range(args.n * 2)]
    controls = [BasePolicy() for _ in bots]
    references = [frozen.BasePolicy() for _ in bots]
    checked = 0
    started = time.monotonic()
    with (args.out / 'engine.log').open('w') as log, (args.out / 'policy-events.jsonl').open('w') as trace:
        process = subprocess.Popen([str(args.runner.resolve()), str(args.seed), str(args.n)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log, text=True)
        try:
            for line in process.stdout:
                observations = json.loads(line)
                if isinstance(observations, dict) and observations.get('final'):
                    result = observations
                    break
                actions = []
                for i, obs in enumerate(observations):
                    reference_action = references[i].choose_action(obs)
                    assert controls[i].choose_action(obs) == reference_action, (i, obs['tick'])
                    checked += 1
                    action = bots[i].choose_action(obs)
                    if args.n == 1:
                        assert action == reference_action, ('duel behavior changed', i, obs['tick'])
                    actions.append(action)
                    if isinstance(bots[i], BasePolicy):
                        for event in bots[i].events:
                            trace.write(json.dumps(dict(slot=i, **event)) + '\n')
                        bots[i].events.clear()
                process.stdin.write(json.dumps(actions, separators=(',', ':')) + '\n')
                process.stdin.flush()
            else:
                raise RuntimeError('Engine exited without a terminal result')
            process.wait(timeout=10)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    result.update(arm=args.arm, seed=args.seed, candidate_side=args.side, n=args.n,
                  baseline_equivalent_actions=checked, wall_seconds=time.monotonic() - started)
    if args.n == 1:
        result['candidate_duel_equivalent_actions'] = checked // 2
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()
