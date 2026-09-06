#!/usr/bin/env bash
## Hosts a Pudge Wars party with base.bas on every unclaimed seat and
## hands you the invite link (copied to the clipboard on macOS).
##
##   examples/pudge_wars/host_party.sh [extra pw flags]
##
## Party defaults: first to 30 kills, fair-handicap bots. Anything you
## pass is appended after the defaults, so your flags win, e.g.:
##
##   examples/pudge_wars/host_party.sh --difficulty pro --killGoal 15
##   examples/pudge_wars/host_party.sh --human --name Aaron
##
## Launches native ./pw (not Pudge Wars.app). The browser client rebuild
## is optional and runs in the background after the host is started:
##   PW_BUILD_WEB=0   skip the emscripten rebuild (existing html still served)
##   PW_BUILD_WEB=1   force a background rebuild even if html looks current

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

stale=$(find examples/pudge_wars src \( -name '*.nim' -o -name '*.m' \) -newer ./pw \
  2>/dev/null | head -1 || true)
if [[ ! -x ./pw || -n "$stale" ]]; then
  echo "building the native host..."
  nim c -d:release --hints:off --warnings:off -o:pw examples/pudge_wars/pw.nim
fi
examples/pudge_wars/macos/attach_app_icon.sh --no-app ./pw

html=examples/pudge_wars/emscripten/pw.html
web_log=examples/pudge_wars/emscripten/build.log
overlay=examples/pudge_wars/recap-overlay.js
boot_scene=examples/pudge_wars/boot-scene.js
cover=examples/pudge_wars/cover.webp
if [[ -d examples/pudge_wars/emscripten && -f "$overlay" ]]; then
  cp "$overlay" examples/pudge_wars/emscripten/recap-overlay.js
fi
if [[ -d examples/pudge_wars/emscripten && -f "$boot_scene" ]]; then
  cp "$boot_scene" examples/pudge_wars/emscripten/boot-scene.js
fi
if [[ -d examples/pudge_wars/emscripten && -f "$cover" ]]; then
  cp "$cover" examples/pudge_wars/emscripten/cover.webp
fi
web_stale=$(find examples/pudge_wars src -name '*.nim' \
  -newer "$html" 2>/dev/null |
  head -1 || true)
need_web=0
if [[ "${PW_BUILD_WEB:-}" == "1" ]]; then
  need_web=1
elif [[ "${PW_BUILD_WEB:-}" == "0" ]]; then
  need_web=0
elif [[ ! -f "$html" || -n "$web_stale" ]]; then
  need_web=1
fi

if [[ -f "$html" ]]; then
  echo "browser client: optional — existing html is served immediately; wasm rebuild does not block the lobby"
else
  echo "browser client: optional — no html yet; native play still works, friends' browsers wait on a background rebuild"
fi
if [[ "${PW_BUILD_WEB:-}" == "0" ]]; then
  echo "browser client: skipped rebuild (PW_BUILD_WEB=0)"
elif [[ "$need_web" -eq 1 ]] && ! command -v emcc >/dev/null; then
  echo "warning: no emcc on the PATH and the web bundle needs a rebuild —" >&2
  echo "friends can only join with a native client (--join) until html is built." >&2
fi

# Same baseline on every seat so bank assignment is not a roster mix.
players=examples/pudge_wars/players
roster=(
  --bot "$players/base.bas:6"
)

echo "starting native host (./pw)..."
./pw --host --difficulty fair --killGoal 30 "${roster[@]}" "$@" 2>&1 |
  while IFS= read -r line; do
    echo "$line"
    case "$line" in
      *"lobby open at "*)
        url="${line##*lobby open at }"
        if command -v pbcopy > /dev/null; then
          printf '%s' "$url" | pbcopy
          echo ">>> invite link copied to the clipboard: $url"
        else
          echo ">>> invite link: $url"
        fi
        echo ">>> press Enter in the game window to start (1-6 claims your seat)"
        if [[ "$need_web" -eq 1 ]] && command -v emcc > /dev/null; then
          mkdir -p examples/pudge_wars/emscripten
          echo "browser client: rebuilding in the background (PW_BUILD_WEB=0 skips) → $web_log"
          (nim c -d:emscripten --hints:off --warnings:off examples/pudge_wars/pw.nim \
            >"$web_log" 2>&1 && cp "$overlay" examples/pudge_wars/emscripten/recap-overlay.js && cp "$boot_scene" examples/pudge_wars/emscripten/boot-scene.js && cp "$cover" examples/pudge_wars/emscripten/cover.webp && echo "browser client: background rebuild finished") &
        fi
        ;;
    esac
  done
