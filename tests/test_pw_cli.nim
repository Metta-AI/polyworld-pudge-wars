## Shared CLI flags used by the graphical client.

import polyworld/cli

proc parseCommon(arguments: seq[string]): GameOptions =
  ## Parses only shared flags, the same way the game loop would.
  result = GameOptions(seed: 2026)
  var index = 0
  while index < arguments.len:
    let argument = arguments[index]
    if not result.takeCommonFlag(arguments, index, argument):
      doAssert false, "unexpected argument: " & argument
    inc index

echo "Testing --vsync is on by default"
block:
  let options = parseCommon(@[])
  doAssert options.vsync
  let off = parseCommon(@["--vsync:off"])
  doAssert not off.vsync
  let on = parseCommon(@["--vsync=on"])
  doAssert on.vsync
  let split = parseCommon(@["--vsync", "off"])
  doAssert not split.vsync
  let splitOn = parseCommon(@["--vsync", "on"])
  doAssert splitOn.vsync

echo "Testing --windowSize is a shared flag"
block:
  let options = parseCommon(@["--windowSize:800x400"])
  doAssert options.windowWidth == 800
  doAssert options.windowHeight == 400
  let split = parseCommon(@["--windowSize", "1024x576"])
  doAssert split.windowWidth == 1024
  doAssert split.windowHeight == 576
  let equals = parseCommon(@["--windowSize=1280x720"])
  doAssert equals.windowWidth == 1280
  doAssert equals.windowHeight == 720

echo "Testing --windowPos places the window"
block:
  let unset = parseCommon(@[])
  doAssert unset.windowX == -1 and unset.windowY == -1
  let colon = parseCommon(@["--windowPos:400,80"])
  doAssert colon.windowX == 400 and colon.windowY == 80
  let split = parseCommon(@["--windowPos", "0,25"])
  doAssert split.windowX == 0 and split.windowY == 25
  let equals = parseCommon(@["--windowPos=1200,600"])
  doAssert equals.windowX == 1200 and equals.windowY == 600

echo "test_pw_cli: all checks passed"
