#!/usr/bin/env bash
## Build AppIcon.png / .icns / .ico from the Flux concept (or an existing PNG).
##
##   examples/pudge_wars/macos/pack_app_icon.sh [source.png]

set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"

dir="examples/pudge_wars/macos"
source="${1:-}"
if [[ -z "$source" ]]; then
  if [[ -f ../polyworld_data/generated/pudge_wars_app/app_icon/concept.png ]]; then
    source="../polyworld_data/generated/pudge_wars_app/app_icon/concept.png"
  elif [[ -f "$dir/AppIcon.png" ]]; then
    source="$dir/AppIcon.png"
  else
    echo "error: no concept PNG; pass a source path" >&2
    exit 1
  fi
fi

python3 "$dir/pack_app_icon.py" "$source" --png "$dir/AppIcon.png" --ico "$dir/AppIcon.ico"

tmp="$(mktemp -d)"
iconset="$tmp/AppIcon.iconset"
mkdir "$iconset"

# Apple iconset names: 1x and @2x for 16, 32, 128, 256, 512.
sips -z 16 16 "$dir/AppIcon.png" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$dir/AppIcon.png" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$dir/AppIcon.png" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$dir/AppIcon.png" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$dir/AppIcon.png" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$dir/AppIcon.png" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$dir/AppIcon.png" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$dir/AppIcon.png" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$dir/AppIcon.png" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$dir/AppIcon.png" --out "$iconset/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$iconset" -o "$dir/AppIcon.icns"
rm -rf "$tmp"

python3 - <<PY
from pathlib import Path
from PIL import Image
src = Image.open("$dir/AppIcon.png")
for size in (16, 32, 128):
    src.resize((size, size), Image.Resampling.LANCZOS).save(f"/tmp/pw_app_icon_{size}.png")
    print(size, Path(f"/tmp/pw_app_icon_{size}.png"))
PY

echo "packed $dir/AppIcon.png"
echo "packed $dir/AppIcon.icns"
echo "packed $dir/AppIcon.ico"
ls -l "$dir/AppIcon.png" "$dir/AppIcon.icns" "$dir/AppIcon.ico"
