#!/usr/bin/env bash
# Build a self-contained Mac app. No repository or server is needed to play.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"
export PATH="${HOME}/.nimby/nim/bin:${HOME}/.local/bin:${PATH}"
mkdir -p tmp
nim c -d:release --hints:off -o:tmp/pw-desktop examples/pudge_wars/pw.nim

python3 - "$root" <<'PY'
import plistlib
import shutil
import sys
from pathlib import Path

root = Path(sys.argv[1])
source = root / 'examples/pudge_wars/macos'
app = root / 'tmp/desktop/hookem.app'
if app.exists():
    shutil.rmtree(app)
macos = app / 'Contents/MacOS'
resources = app / 'Contents/Resources'
game = resources / 'game'
macos.mkdir(parents=True)
game.mkdir(parents=True)
shutil.copy2(root / 'tmp/pw-desktop', macos / 'pw')
shutil.copy2(source / 'AppIcon.icns', resources / 'AppIcon.icns')
with (source / 'Info.plist').open('rb') as f:
    info = plistlib.load(f)
info['CFBundleExecutable'] = 'hookem'
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)

data = root / 'polyworld_data'
if not data.is_dir():
    data = root.parent / 'polyworld_data'
for entry in (root / 'examples/pudge_wars/webdata.txt').read_text().splitlines():
    entry = entry.strip()
    if not entry or entry.startswith('#'):
        continue
    origin = data / entry
    target = resources / 'polyworld_data' / entry
    target.parent.mkdir(parents=True, exist_ok=True)
    if origin.is_dir():
        shutil.copytree(origin, target)
    else:
        shutil.copy2(origin, target)
# DataRoot supports both repository asset layouts at compile time.
(game / 'polyworld_data').symlink_to('../polyworld_data', target_is_directory=True)
shutil.copytree(root / 'examples/pudge_wars/assets/hookem', game / 'examples/pudge_wars/assets/hookem')
players = game / 'players'
players.mkdir()
for name in ('base', 'aggressive', 'sniper', 'challenger', 'denier', 'patient', 'support'):
    shutil.copy2(root / f'examples/pudge_wars/players/{name}.bas', players / f'{name}.bas')
launcher = macos / 'hookem'
launcher.write_text('''#!/bin/bash
set -euo pipefail
contents="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$HOME/Library/Logs/hookem"
exec >> "$HOME/Library/Logs/hookem/game.log" 2>&1
cd "$contents/Resources/game"
exec "$contents/MacOS/pw" --human:0 --difficulty fair --killGoal 30 \\
  --bot players/base.bas:1 --bot players/aggressive.bas:1 \\
  --bot players/base.bas:1 --bot players/aggressive.bas:1 \\
  --bot players/sniper.bas:1 --windowSize 1280x800 --practice "$@"
''')
launcher.chmod(0o755)
print(app)
PY

codesign --force --deep --sign - "tmp/desktop/hookem.app"
echo "Ready: $root/tmp/desktop/hookem.app"
