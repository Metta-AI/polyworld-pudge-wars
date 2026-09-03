#!/usr/bin/env bash
## Bot lab: pit one policy against another across seeds, both sides,
## and print per-match lines plus an aggregate. The workhorse behind
## evolving players/base.bas via headless self-play.
##
##   examples/pudge_wars/botlab.sh CANDIDATE REFERENCE [SEEDS] [--three]
##
## CANDIDATE/REFERENCE are .bas paths (repo-relative or absolute).
## SEEDS defaults to 10; every seed runs twice with the candidate on
## each bank, so side bias cancels. --three plays 3v3 instead of the
## duel. A "VM FAILURE" line means a script died or blew its budget.
##
##   examples/pudge_wars/botlab.sh players/base.bas players/denier.bas
##   examples/pudge_wars/botlab.sh my.bas players/base.bas 6 --three

set -euo pipefail

cd "$(dirname "$0")/../.."
pwdir=examples/pudge_wars

cand="${1:?usage: botlab.sh CANDIDATE REFERENCE [SEEDS] [--three]}"
ref="${2:?usage: botlab.sh CANDIDATE REFERENCE [SEEDS] [--three]}"
seeds="${3:-10}"
mode="${4:-duel}"
[[ -f "$cand" ]] || cand="$pwdir/$cand"
[[ -f "$ref" ]] || ref="$pwdir/$ref"
for f in "$cand" "$ref"; do
  [[ -f "$f" ]] || { echo "error: script not found: $f" >&2; exit 1; }
done

stale=$(find "$pwdir" src -name '*.nim' -newer ./pwheadless 2>/dev/null |
  head -1 || true)
if [[ ! -x ./pwheadless || -n "$stale" ]]; then
  echo "building the headless binary..."
  nim c -d:release -d:headless --hints:off --warnings:off \
    -o:pwheadless "$pwdir/pw.nim"
fi

candWins=0; refWins=0; draws=0; fails=0
for seed in $(seq 1 "$seeds"); do
  for side in west east; do
    if [[ "$side" == west ]]; then a="$cand"; b="$ref"; else a="$ref"; b="$cand"; fi
    if [[ "$mode" == "--three" ]]; then
      out=$(./pwheadless --bot "$a:3" --bot "$b:3" \
        --seed "$seed" --killGoal 10 --minutes 10 2>&1) || true
      want=6
    else
      out=$(./pwheadless --duel --bot "$a:1" --bot "$b:1" \
        --seed "$seed" --killGoal 10 --minutes 10 2>&1) || true
      want=2
    fi
    score=$(grep -o 'score: west [0-9]* / east [0-9]*' <<<"$out" || true)
    w=$(sed 's/score: west \([0-9]*\).*/\1/' <<<"$score")
    e=$(sed 's/.*east \([0-9]*\)/\1/' <<<"$score")
    active=$(grep -o "scripts: $want/$want active" <<<"$out" || true)
    if [[ -z "$active" ]]; then
      fails=$((fails+1))
      echo "seed $seed candSide=$side: VM FAILURE"
      continue
    fi
    if [[ "$w" -gt "$e" ]]; then winner=west
    elif [[ "$e" -gt "$w" ]]; then winner=east
    else winner=draw; fi
    if [[ "$winner" == draw ]]; then draws=$((draws+1)); res=draw
    elif { [[ "$side" == west && "$winner" == west ]] ||
        [[ "$side" == east && "$winner" == east ]]; }; then
      candWins=$((candWins+1)); res=CAND
    else refWins=$((refWins+1)); res=ref; fi
    echo "seed $seed candSide=$side  west $w / east $e  -> $res"
  done
done
echo "== cand $candWins  ref $refWins  draws $draws" \
  "vmfails $fails  (n=$((candWins+refWins+draws)))"
