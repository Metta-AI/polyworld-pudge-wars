#!/usr/bin/env bash
## Starts a 1v1 duel: you on the west bank, the evolving challenger
## policy (players/challenger.bas) on the east. Every match writes an
## analysis bundle under examples/pudge_wars/duels/ for the agent to
## study between games.
##
##   examples/pudge_wars/duel.sh [extra pw flags]
##
## Your flags land after the defaults, so they win, e.g.:
##
##   examples/pudge_wars/duel.sh --killGoal 5
##   examples/pudge_wars/duel.sh --seed 42
##
## In game: right-click walks (on an enemy: attacks), Q aims the
## hook, 1-4 buy upgrades. R restarts a finished match and rotates a
## fresh log directory.

set -euo pipefail

cd "$(dirname "$0")/../.."

# Prefer the Nimby toolchain scripts/setup.sh installs.
export PATH="${HOME}/.nimby/nim/bin:${HOME}/.local/bin:${PATH}"
if ! command -v nim > /dev/null; then
  echo "error: nim not found on the PATH" >&2
  echo "  run: scripts/setup.sh" >&2
  echo "  then: export PATH=\"\$HOME/.nimby/nim/bin:\$HOME/.local/bin:\$PATH\"" >&2
  exit 1
fi

stale=$(find examples/pudge_wars src \( -name '*.nim' -o -name '*.m' \) -newer ./pw 2>/dev/null | head -1 || true)
if [[ ! -x ./pw || -n "$stale" ]]; then
  echo "building the native client..."
  nim c -d:release --hints:off --warnings:off -o:pw examples/pudge_wars/pw.nim
fi
examples/pudge_wars/macos/attach_app_icon.sh ./pw
pw_bin=./pw
if [[ -x "examples/pudge_wars/macos/Fresh Meat.app/Contents/MacOS/Fresh Meat" ]]; then
  pw_bin="examples/pudge_wars/macos/Fresh Meat.app/Contents/MacOS/Fresh Meat"
fi

exec "$pw_bin" --duel --human:0 "$@"
