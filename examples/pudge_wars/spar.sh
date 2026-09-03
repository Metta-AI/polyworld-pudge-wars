#!/usr/bin/env bash
## Headless sparring for the challenger policy: pits
## players/challenger.bas against a chosen opponent script with full
## duel logs, so a policy edit can be sanity-checked before facing the
## human. No window opens and matches run as fast as the CPU allows.
##
##   examples/pudge_wars/spar.sh [opponent.bas] [seed] [extra flags]
##
## Defaults: opponent players/base.bas, seed 1. Examples:
##
##   examples/pudge_wars/spar.sh
##   examples/pudge_wars/spar.sh players/sniper.bas 7
##   examples/pudge_wars/spar.sh players/base.bas 3 --killGoal 5
##
## Logs land in examples/pudge_wars/duels/ (spar matches look the same
## as human matches; the summary names the scripts on each side).

set -euo pipefail

cd "$(dirname "$0")/../.."

if ! command -v nim > /dev/null; then
  echo "error: nim not found on the PATH" >&2
  exit 1
fi

pwdir=examples/pudge_wars
opponent="${1:-$pwdir/players/base.bas}"
seed="${2:-1}"
shift $(( $# > 2 ? 2 : $# ))
[[ -f "$opponent" ]] || opponent="$pwdir/$opponent"
if [[ ! -f "$opponent" ]]; then
  echo "error: opponent script not found: $opponent" >&2
  exit 1
fi

stale=$(find "$pwdir" src -name '*.nim' -newer ./pwheadless 2>/dev/null |
  head -1 || true)
if [[ ! -x ./pwheadless || -n "$stale" ]]; then
  echo "building the headless binary..."
  nim c -d:release -d:headless --hints:off --warnings:off \
    -o:pwheadless "$pwdir/pw.nim"
fi

# Challenger takes the west seat, the opponent the east seat, mirroring
# the human duel layout (human west, challenger east) from the other
# side so the same policy code is exercised on both banks over time.
exec ./pwheadless --duel \
  --bot "$pwdir/players/challenger.bas:1" \
  --bot "$opponent:1" \
  --seed "$seed" "$@"
