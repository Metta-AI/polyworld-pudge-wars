#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
coach_use_softmax_key=false
if [[ "${1:-}" == "--softmax-key" ]]; then
  coach_use_softmax_key=true
  shift
fi
export PATH="${HOME}/.nimby/nim/bin:${HOME}/.local/bin:${PATH}"
mkdir -p tmp/coaching
if [[ ! -x tmp/coaching/venv/bin/python ]]; then
  python3 -m venv tmp/coaching/venv
fi
tmp/coaching/venv/bin/python -m pip install -q -r coaching/requirements.txt
nim c -d:release --hints:off --warnings:off -o:tmp/coaching/pwcoworld examples/pudge_wars/coworld_host.nim
if command -v emcc >/dev/null; then
  nim c -d:emscripten --hints:off --warnings:off examples/pudge_wars/pw.nim > tmp/coaching/wasm-build.log 2>&1 || {
    tail -40 tmp/coaching/wasm-build.log
    exit 1
  }
else
  echo "emcc is required to build a browser client matching this engine."
  exit 1
fi
for asset in cover.webp recap-overlay.js boot-scene.js touch-input.js; do
  cp "examples/pudge_wars/$asset" "examples/pudge_wars/emscripten/$asset"
done
if [[ "$coach_use_softmax_key" == true ]]; then
  # Match metta's documented Secrets Manager path. Never trace or persist the value.
  set +x
  OPENAI_API_KEY="$(aws secretsmanager get-secret-value \
    --profile "${COACH_AWS_PROFILE:-softmax}" --region us-east-1 \
    --secret-id openai/agent-api-key --query SecretString --output text)"
  export OPENAI_API_KEY
fi
exec tmp/coaching/venv/bin/python -m coaching.server "$@"
