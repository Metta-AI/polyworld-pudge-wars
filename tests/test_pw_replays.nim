## Pudge Wars action replay codec, playback cursor, and validation.

import
  std/[os, strutils],
  polyworld/tapes,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/replays

proc testSetup(): Setup =
  result = Setup(
    mapSeed: 2026,
    mapHash: 0x123456789ABCDEF0'u64,
    tickRate: uint16(TickRate),
    gridTiles: ReplayGridTiles,
    maximumTicks: 20,
    killGoal: KillGoal,
    botEvery: 8,
    botAimNoise: 1,
    runePeriod: RunePeriodTicks,
    pudges: newSeq[ReplayPudge](PudgeCount)
  )
  for i in 0 ..< PudgeCount:
    result.pudges[i] = ReplayPudge(
      id: 1 + int32(i),
      team: uint8(if i < TeamSize: 0 else: 1),
      slot: uint8(i mod TeamSize),
      controller: if i == 0: ControllerHuman else: ControllerBot,
      spawnX: int32(if i < TeamSize: 22 else: 106),
      spawnZ: int32(40 + (i mod TeamSize) * 24)
    )

let setup = testSetup()

echo "Testing Flatty action replay round trip"
let recorder = initReplayRecorder(setup)
recorder.recordWalkTo(4, 1, 52, 64)
recorder.recordHookTo(4, 1, 76, 64)
recorder.recordStop(6, 1)
recorder.recordPing(8, 2, 70, 44)
recorder.recordHookToFine(10, 1, 76 * FineAimScale + 90, 64 * FineAimScale)
recorder.recordAttackTarget(12, 2, 5)
recorder.recordTakeOver(15, 3, ControllerHuman)
recorder.recordBuyUpgrade(19, 4, 1)
recorder.recordBlinkTo(19, 1, 30, 64)
recorder.recordBlinkToFine(19, 1, 30 * FineAimScale, 64 * FineAimScale)
recorder.recordPlaceWall(19, 1, 28, 64)
recorder.recordPlaceMine(19, 1, 30, 64)
recorder.recordCheat(19, 1, 0, 500)
for tick in 1'u64 .. 20'u64:
  recorder.recordHash(tick xor 0x9E3779B97F4A7C15'u64)
let
  encoded = recorder.data.encodeReplay()
  decoded = decodeReplay(encoded)
  fileHeader = replayFileHeader(encoded)
doAssert encoded.startsWith(ReplayMagic)
doAssert fileHeader.formatVersion == ReplayFileVersion
doAssert fileHeader.game == ReplayGame
doAssert fileHeader.gameVersion == ReplayGameVersion
doAssert decoded.header.formatVersion == ReplayFormatVersion
doAssert decoded.header.formatVersion == 4'u16,
  "spawn pads ship in replay format v4"
doAssert decoded.header.gameVersion == ReplayGameVersion
doAssert decoded.header.setup.mapSeed == 2026
doAssert decoded.header.setup.killGoal == KillGoal
doAssert decoded.header.setup.botEvery == 8
doAssert decoded.header.setup.botAimNoise == 1
doAssert decoded.header.setup.runePeriod == RunePeriodTicks
doAssert decoded.header.setup.pudges.len == PudgeCount
doAssert decoded.header.setup.pudges[0].controller == ControllerHuman
doAssert decoded.header.setup.pudges[1].controller == ControllerBot
doAssert decoded.header.setup.pudges[0].spawnX == 22
doAssert decoded.header.setup.pudges[3].spawnX == 106
doAssert decoded.actions.len == 13
doAssert decoded.actions[0].kind == ActionWalkTo
doAssert decoded.actions[0].first == 52
doAssert decoded.actions[1].kind == ActionHookTo
doAssert decoded.actions[2].kind == ActionStop
doAssert decoded.actions[3].kind == ActionPing
doAssert decoded.actions[3].second == 44
doAssert decoded.actions[4].kind == ActionHookToFine
doAssert decoded.actions[4].first == 76 * FineAimScale + 90
doAssert decoded.actions[5].kind == ActionAttackTarget
doAssert decoded.actions[6].kind == ActionTakeOver
doAssert decoded.actions[6].first == int32(ControllerHuman)
doAssert decoded.actions[7].kind == ActionBuyUpgrade
doAssert decoded.actions[8].kind == ActionBlinkTo
doAssert decoded.actions[8].first == 30
doAssert decoded.actions[9].kind == ActionBlinkToFine
doAssert decoded.actions[10].kind == ActionPlaceWall
doAssert decoded.actions[10].first == 28
doAssert decoded.actions[11].kind == ActionPlaceMine
doAssert decoded.actions[12].kind == ActionCheat
doAssert decoded.actions[12].second == 500
doAssert decoded.hashes == recorder.data.hashes
doAssert decoded.hashes.len == int(decoded.header.setup.maximumTicks)

echo "Testing exact-tick action playback"
let player = initReplayPlayer(decoded)
doAssert player.actionsAt(0).len == 0
let first = player.actionsAt(4)
doAssert first.len == 2
doAssert first[0].pudgeId == 1
doAssert first[1].kind == ActionHookTo
doAssert player.actionsAt(6).len == 1
doAssert player.actionsAt(8).len == 1
doAssert player.actionsAt(10).len == 1
doAssert player.actionsAt(12).len == 1
doAssert player.actionsAt(15).len == 1
doAssert player.actionsAt(18).len == 0
doAssert player.actionsAt(19).len == 6
doAssert player.finished

echo "Testing allocation-free action playback"
let directPlayer = initReplayPlayer(decoded)
var action: ReplayAction
doAssert not directPlayer.takeActionAt(0, action)
doAssert directPlayer.takeActionAt(4, action)
doAssert action.pudgeId == 1
doAssert directPlayer.takeActionAt(4, action)
doAssert action.kind == ActionHookTo
doAssert not directPlayer.takeActionAt(4, action)
doAssert directPlayer.takeActionAt(6, action)
doAssert action.kind == ActionStop
doAssert directPlayer.takeActionAt(8, action)
doAssert action.kind == ActionPing
doAssert directPlayer.takeActionAt(10, action)
doAssert action.kind == ActionHookToFine
doAssert directPlayer.takeActionAt(12, action)
doAssert action.first == 5
doAssert directPlayer.takeActionAt(15, action)
doAssert action.kind == ActionTakeOver
doAssert directPlayer.finished == false
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionBuyUpgrade
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionBlinkTo
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionBlinkToFine
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionPlaceWall
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionPlaceMine
doAssert directPlayer.takeActionAt(19, action)
doAssert action.kind == ActionCheat
doAssert directPlayer.finished

echo "Testing replay file I/O"
let path = getTempDir() / "polyworld-pw-test.replay"
saveReplay(path, recorder.data)
let loaded = loadReplay(path)
doAssert loaded.actions == decoded.actions
removeFile(path)

echo "Testing a mid-match bug-tape flush is loadable"
block:
  var liveSetup = testSetup()
  liveSetup.maximumTicks = 100
  let live = initReplayRecorder(liveSetup)
  live.recordWalkTo(2, 1, 52, 64)
  live.recordStop(6, 1)
  for tick in 1'u64 .. 8'u64:
    live.recordHash(tick xor 0x9E3779B97F4A7C15'u64)
  doAssert live.data.header.setup.maximumTicks == 100
  let dir = getTempDir() / "polyworld-pw-bug-tape"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  let bugPath = writeBugReplay(dir, live.data, 0, "Aaron", 1'i32, 2'i32)
  doAssert live.data.header.setup.maximumTicks == 100,
    "flush must not close the live recorder"
  doAssert fileExists(bugPath)
  let bugLoaded = loadReplay(bugPath)
  doAssert bugLoaded.header.setup.maximumTicks == 100
  doAssert bugLoaded.hashes.len == 8
  doAssert bugLoaded.actions.len == 2
  doAssert bugLoaded.actions[0].kind == ActionWalkTo
  let pointer = readFile(dir / BugLatestName)
  doAssert pointer.contains("Aaron")
  doAssert pointer.contains(bugPath)
  doAssert pointer.contains("fromTick: 2")
  doAssert pointer.contains("toTick: 8")
  doAssert pointer.contains("seat: 0")
  removeDir(dir)

echo "Testing replay validation"
try:
  discard decodeReplayFile(
    "gods_of_the_arena",
    1,
    encoded,
    ReplayData
  )
  doAssert false, "a replay from another game should fail"
except ReplayError as error:
  doAssert error.msg.contains("pudge_wars")
  doAssert error.msg.contains("gods_of_the_arena")

var invalid = decoded
invalid.hashes.setLen(18)
try:
  discard invalid.encodeReplay()
  doAssert false, "an action after the last recorded tick should fail"
except ReplayError:
  discard

invalid = decoded
invalid.hashes.setLen(int(decoded.header.setup.maximumTicks) + 1)
try:
  discard invalid.encodeReplay()
  doAssert false, "hashes past the configured duration should fail"
except ReplayError:
  discard

invalid = decoded
invalid.header.setup.pudges.setLen(DuelPudgeCount - 1)
try:
  discard invalid.encodeReplay()
  doAssert false, "a replay that drops below a duel roster should fail"
except ReplayError:
  discard

invalid = decoded
invalid.header.setup.killGoal = 0
try:
  discard invalid.encodeReplay()
  doAssert false, "a replay without a kill goal should fail"
except ReplayError:
  discard

invalid = decoded
invalid.header.setup.botEvery = 0
try:
  discard invalid.encodeReplay()
  doAssert false, "a replay without a bot cadence should fail"
except ReplayError:
  discard

invalid = decoded
invalid.header.setup.runePeriod = -1
try:
  discard invalid.encodeReplay()
  doAssert false, "a replay with a negative rune period should fail"
except ReplayError:
  discard

invalid = decoded
invalid.header.setup.pudges[0].controller = 9
try:
  discard invalid.encodeReplay()
  doAssert false, "a replay with an unknown controller should fail"
except ReplayError:
  discard

try:
  discard decodeReplay("NOT-A-PUDGE-WARS-REPLAY")
  doAssert false, "invalid magic should fail"
except ReplayError:
  discard

echo "Testing an older file header is rejected"
block:
  var encoded = recorder.data.encodeReplay()
  let older = ReplayGameVersion - 1
  encoded[ReplayMagic.len + 2] = char(older and 0xff)
  encoded[ReplayMagic.len + 3] = char((older shr 8) and 0xff)
  let oldPath = getTempDir() / "polyworld-pw-oldver.replay"
  writeFile(oldPath, encoded)
  try:
    discard loadReplay(oldPath)
    doAssert false, "an older simulation version must not load"
  except ReplayError as error:
    doAssert error.msg.contains("game version")
  removeFile(oldPath)

echo "Testing encode refuses another game version"
block:
  var other = decoded
  other.header.gameVersion = ReplayGameVersion - 1
  try:
    discard other.encodeReplay()
    doAssert false, "encoding another game version should fail"
  except ReplayError as error:
    doAssert error.msg.contains("unsupported replay game version") or
      error.msg.contains("another game version")

echo "Testing empty and partial recordings keep the original setup"
block:
  var liveSetup = testSetup()
  liveSetup.maximumTicks = 100
  let live = initReplayRecorder(liveSetup)
  doAssert live.data.hashes.len == 0
  let emptyEncoded = live.data.encodeReplay()
  let empty = decodeReplay(emptyEncoded)
  doAssert empty.header.setup == liveSetup
  doAssert empty.hashes.len == 0
  doAssert empty.actions.len == 0
  live.recordWalkTo(2, 1, 52, 64)
  live.recordStop(6, 1)
  for tick in 1'u64 .. 8'u64:
    live.recordHash(tick xor 0x9E3779B97F4A7C15'u64)
  let partial = decodeReplay(live.data.encodeReplay())
  doAssert partial.header.setup == liveSetup
  doAssert partial.hashes.len == 8
  doAssert partial.actions.len == 2

echo "Testing coworld save strips commands past the last hash"
block:
  var liveSetup = testSetup()
  liveSetup.maximumTicks = 100
  let live = initReplayRecorder(liveSetup)
  live.recordWalkTo(2, 1, 52, 64)
  live.recordStop(6, 1)
  live.recordWalkTo(12, 1, 60, 64)
  for tick in 1'u64 .. 8'u64:
    live.recordHash(tick xor 0x9E3779B97F4A7C15'u64)
  doAssert live.data.actions.len == 3
  let encoded = encodeCoworldReplay(live.data)
  let decoded = decodeReplay(encoded)
  doAssert decoded.header.setup.maximumTicks == 100
  doAssert decoded.hashes.len == 8
  doAssert decoded.actions.len == 2
  doAssert decoded.actions[^1].kind == ActionStop
  doAssert live.data.actions.len == 3,
    "closing the save copy must not mutate the live recorder"

echo "Testing replay completion rejects divergence and missing ticks"
block:
  var check: ReplayHashCheck
  check.requireReplayComplete(0, 0)
  check.requireReplayComplete(2, 2)
  for tick in [1'u32, 3'u32]:
    try:
      check.requireReplayComplete(tick, 2)
      doAssert false, "playback must consume exactly the recorded ticks"
    except ReplayError:
      discard
  check = ReplayHashCheck(mismatches: 1, firstTick: 2)
  try:
    check.requireReplayComplete(2, 2)
    doAssert false, "a hash mismatch must fail replay verification"
  except ReplayError as error:
    doAssert error.msg.contains("first at tick 2")

echo "test_pw_replays: all checks passed"
