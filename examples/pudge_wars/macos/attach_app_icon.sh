#!/usr/bin/env bash
## Stamp a Finder icon onto the Mach-O at the repo root. By default also
## copies that binary into Pudge Wars.app — pass --no-app to skip the
## bundle (host_party launches ./pw, not the .app).
##
##   examples/pudge_wars/macos/attach_app_icon.sh [./pw] [--no-app]

set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"

stamp_app=1
binary=./pw
for arg in "$@"; do
  case "$arg" in
    --no-app) stamp_app=0 ;;
    *) binary="$arg" ;;
  esac
done

dir="examples/pudge_wars/macos"
icns="$dir/AppIcon.icns"
plist="$dir/Info.plist"

if [[ ! -x "$binary" ]]; then
  echo "error: missing executable $binary" >&2
  exit 1
fi
if [[ ! -f "$icns" ]]; then
  echo "error: missing $icns — run pack_app_icon.sh first" >&2
  exit 1
fi
if [[ "$stamp_app" -eq 1 && ! -f "$plist" ]]; then
  echo "error: missing $plist" >&2
  exit 1
fi

app="$dir/Pudge Wars.app"
macos_dir="$app/Contents/MacOS"
resources="$app/Contents/Resources"
app_exec="$macos_dir/Pudge Wars"

abs_icns="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$icns")"
abs_bin="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$binary")"

if [[ "$stamp_app" -eq 1 ]]; then
  mkdir -p "$macos_dir" "$resources"
  cp -f "$plist" "$app/Contents/Info.plist"
  printf 'APPL????' > "$app/Contents/PkgInfo"
  cp -f "$icns" "$resources/AppIcon.icns"
  if pgrep -f 'Pudge Wars.app/Contents/MacOS/Pudge Wars' >/dev/null 2>&1; then
    echo "skipping copy over $app_exec — a Pudge Wars.app process is still running"
  else
    cp -f "$binary" "$app_exec"
    chmod +x "$app_exec"
  fi
  abs_app="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$app")"
  PW_ICON="$abs_icns" PW_BIN="$abs_bin" PW_APP="$abs_app" osascript -l JavaScript <<'JS'
ObjC.import('AppKit')
function envStr (key) {
  return ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(key))
}
function setIcon (imagePath, filePath) {
  const image = $.NSImage.alloc.initWithContentsOfFile(imagePath)
  if (image.isNil()) {
    throw new Error('could not load icon ' + imagePath)
  }
  const ok = $.NSWorkspace.sharedWorkspace.setIconForFileOptions(image, filePath, 0)
  if (!ok) {
    throw new Error('NSWorkspace setIcon failed for ' + filePath)
  }
}
setIcon(envStr('PW_ICON'), envStr('PW_BIN'))
setIcon(envStr('PW_ICON'), envStr('PW_APP'))
JS
  echo "attached icon to $binary"
  echo "updated $app"
else
  PW_ICON="$abs_icns" PW_BIN="$abs_bin" osascript -l JavaScript <<'JS'
ObjC.import('AppKit')
function envStr (key) {
  return ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey(key))
}
function setIcon (imagePath, filePath) {
  const image = $.NSImage.alloc.initWithContentsOfFile(imagePath)
  if (image.isNil()) {
    throw new Error('could not load icon ' + imagePath)
  }
  const ok = $.NSWorkspace.sharedWorkspace.setIconForFileOptions(image, filePath, 0)
  if (!ok) {
    throw new Error('NSWorkspace setIcon failed for ' + filePath)
  }
}
setIcon(envStr('PW_ICON'), envStr('PW_BIN'))
JS
  echo "attached icon to $binary"
fi
