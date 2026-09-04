## Fluffy profiling for Polyworld.
##
## `{.measure.}` and `profileBlock` always record while a trace is active.
## Compile-time capture: `-d:profileTracePath=tmp/x.json -d:profileFrames=100`.
## Runtime capture: F2 starts a trace, F2 again writes tmp/fluffy.json and
## opens the Fluffy viewer.

import
  std/os,
  fluffy/measure

when not defined(emscripten):
  import std/osproc

export measure

const
  ProfileTracePath* {.strdefine.} = ""
  MapProfileTracePath* {.strdefine.} = ""
  ProfileFrames* {.intdefine.} = 0
  RuntimeTracePath* = "tmp/fluffy.json"
  ActiveTracePath* =
    if ProfileTracePath.len > 0:
      ProfileTracePath
    else:
      MapProfileTracePath

var
  profileStarted = false
  profileDumped = false
  profileFrameCount = 0
  runtimeTracing = false

proc runtimeTraceActive*(): bool =
  ## True while an F2 Fluffy capture is recording.
  runtimeTracing

proc tracingNow(): bool {.inline.} =
  ## True when a compile-time or F2 capture should pair push/pop.
  runtimeTracing or (profileStarted and not profileDumped)

proc ensureProfileDir(path: string) =
  ## Creates the parent directory for the profile trace.
  let dir = path.parentDir()
  if dir.len > 0:
    createDir(dir)

proc writeMeasures(path: string) =
  ## Writes the Fluffy capture. dumpMeasures indexes events[0] and
  ## raises IndexDefect when the capture recorded no completed spans.
  try:
    dumpMeasures(path)
  except IndexDefect:
    echo "Fluffy trace has no completed spans; skipped ", path

proc startProfileTrace*() =
  ## Starts the compile-time Fluffy capture once.
  if profileStarted:
    return
  when ActiveTracePath.len > 0:
    profileStarted = true
    ensureProfileDir(ActiveTracePath)
    echo "Profile trace enabled: ", ActiveTracePath
    echo "Profile frames: ", ProfileFrames
    startTrace()

proc finishProfileTrace*() =
  ## Stops and writes the compile-time Fluffy capture once.
  when ActiveTracePath.len > 0:
    if not profileStarted or profileDumped:
      return
    profileDumped = true
    endTrace()
    ensureProfileDir(ActiveTracePath)
    writeMeasures(ActiveTracePath)

proc profileShouldDump*(frames: int): bool =
  ## Returns true when the compile-time frame budget has elapsed.
  ProfileFrames > 0 and frames >= ProfileFrames and not profileDumped

proc noteProfileFrame*(): bool =
  ## Counts one presented frame. True when the compile-time budget finished.
  if not profileStarted or profileDumped:
    return false
  inc profileFrameCount
  if ProfileFrames > 0 and profileFrameCount >= ProfileFrames:
    finishProfileTrace()
    return true
  false

template profileBlock*(name: string, body: untyped) =
  ## Measures a named block while a Fluffy trace is active.
  ## Snapshot at entry: F2's startTrace clears Fluffy's span stack and
  ## enables tracing, so a matching pop of a skipped push is IndexDefect.
  let measureThis = tracingNow()
  if measureThis:
    measurePush(name)
  try:
    body
  finally:
    if measureThis:
      # startTrace mid-block (F2 while a compile-time capture is live)
      # clears Fluffy's stack; pop would raise IndexDefect.
      try:
        measurePop()
      except IndexDefect:
        discard

template profilePush*(name: string) =
  ## Starts a named span. Pair with `profilePop`.
  measurePush(name)

template profilePop*() =
  ## Ends the span started by `profilePush`.
  measurePop()

proc fluffyNimPath(): string =
  ## Finds the Fluffy viewer next to this repo or in a sibling checkout.
  let
    fromHere = currentSourcePath().parentDir / "../../.." / "fluffy" /
      "src" / "fluffy.nim"
    fromRepo = currentSourcePath().parentDir / "../.." / ".." / "fluffy" /
      "src" / "fluffy.nim"
    fromCwd = getCurrentDir() / ".." / "fluffy" / "src" / "fluffy.nim"
    fromExample = getCurrentDir() / "../.." / "fluffy" / "src" / "fluffy.nim"
    fromNimby = getHomeDir() / ".nimby" / "pkgs" / "fluffy" / "src" /
      "fluffy.nim"
  for candidate in [fromHere, fromRepo, fromCwd, fromExample, fromNimby]:
    if fileExists(candidate):
      return candidate.normalizedPath
  ""

proc openFluffy(path: string) =
  ## Opens the written trace in the Fluffy viewer.
  when defined(emscripten):
    discard
  else:
    let
      absPath = path.absolutePath
      fluffyNim = fluffyNimPath()
    if fluffyNim.len == 0:
      echo "Fluffy viewer not found; open ", absPath, " by hand"
      return
    let fluffyRoot = fluffyNim.parentDir.parentDir
    echo "Opening Fluffy: ", absPath
    discard startProcess(
      "nim",
      workingDir = fluffyRoot,
      args = ["r", "src/fluffy.nim", absPath],
      options = {poUsePath}
    )

proc toggleRuntimeTrace*() =
  ## F2: start a runtime capture, or write it and open Fluffy.
  when defined(emscripten):
    discard
  else:
    if runtimeTracing:
      endTrace()
      ensureProfileDir(RuntimeTracePath)
      writeMeasures(RuntimeTracePath)
      runtimeTracing = false
      if fileExists(RuntimeTracePath):
        openFluffy(RuntimeTracePath)
    else:
      if not tracingNow():
        startTrace()
      runtimeTracing = true
      echo "Runtime Fluffy trace started; F2 writes ", RuntimeTracePath
