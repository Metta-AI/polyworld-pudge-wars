## Rebindable keys for the human seat.
##
## Defaults match the research doc's layout (Q hook, E grapple, F blink,
## R rot, X stop, G ping, F1 center, L follow, T take-over, 1-4 upgrades,
## M mute, R rematch on the end screen).
## A plain-text file overrides them, one `action = KeyName` per line,
## using windy button names such as KeyQ or KeyF1:
##
##   hook = KeyD
##   center = KeySpace
##
## Unknown actions or key names warn and keep the default, so a typo
## never bricks the seat.

import std/[os, strutils], windy

type
  BindAction* = enum
    BindHook = "hook"
    BindGrapple = "grapple"
    BindBlink = "blink"
    BindRot = "rot"
    BindStop = "stop"
    BindPing = "ping"
    BindCenter = "center"
    BindFollow = "follow"
    BindTakeOver = "takeover"
    BindUpgrade1 = "upgrade1"
    BindUpgrade2 = "upgrade2"
    BindUpgrade3 = "upgrade3"
    BindUpgrade4 = "upgrade4"
    BindWall = "wall"
    BindMine = "mine"
    BindMute = "mute"
    BindRematch = "rematch"

var keyBinds: array[BindAction, Button] = [
  # Stop lives on X: WASD steers the butcher directly now.
  # F blink: E is already grapple; Space stays free for rebinds.
  # R rot in-match; rematch keeps R on the end screen only.
  KeyQ, KeyE, KeyF, KeyR, KeyX, KeyG, KeyF1, KeyL, KeyT,
  Key1, Key2, Key3, Key4, KeyC, KeyV, KeyM, KeyR
]

proc bindKey*(action: BindAction): Button =
  ## The button currently bound to one action.
  keyBinds[action]

proc bindLabel*(action: BindAction): string =
  ## Short uppercase HUD label for the bound button, e.g. "Q" or
  ## "SPACE" or "MOUSE4".
  result = $keyBinds[action]
  result.removePrefix("Key")
  result = result.toUpperAscii()

proc loadKeyBinds*(path: string): bool =
  ## Applies overrides from a bindings file. Returns whether the file
  ## existed; bad lines warn and change nothing.
  if not fileExists(path):
    return false
  for rawLine in lines(path):
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#") or line.startsWith(";"):
      continue
    let split = line.find('=')
    if split < 0:
      echo "keys: ignored line without '=': ", line
      continue
    let
      actionName = line[0 ..< split].strip().toLowerAscii()
      keyName = line[split + 1 .. ^1].strip()
    var action: BindAction
    try:
      action = parseEnum[BindAction](actionName)
    except ValueError:
      echo "keys: unknown action '", actionName, "'"
      continue
    try:
      keyBinds[action] = parseEnum[Button](keyName)
    except ValueError:
      echo "keys: unknown key '", keyName, "' for ", actionName
  true
