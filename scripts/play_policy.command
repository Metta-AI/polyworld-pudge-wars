#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
exec uv run scripts/play_policy.py "$@"
