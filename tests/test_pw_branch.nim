## Answer-key rollouts: a recorded match branched at a decision window.
import
  std/[json, os, sequtils, strutils],
  polyworld/cli,
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/branch,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/practice,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  Ticks = 400'i32
  HeroSlot = 0
  Horizon = 96'i32

let
  map = generateMap(2026)
  basBotPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"

proc recordedMatch(): ReplayData =
  ## A short live match: bots on every other seat, the hero walking to
  ## the river lip and throwing once, taped exactly as the game does it.
  let game = newGame(map, Ticks, false, ReplayData())
  game.humanSlots.add HeroSlot
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount - 1)])
  game.recorder = initReplayRecorder(currentSetup(game, uint32(Ticks)))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  for tick in 1'i32 .. Ticks:
    if tick == 8:
      queueIntent(game, HumanIntent(slot: HeroSlot, kind: IntentWalk,
        a: int32(RiverCenterX - riverHalfWidthAt(56) - 2), b: 56))
    if tick == 200:
      queueIntent(game, HumanIntent(slot: HeroSlot, kind: IntentHook,
        a: int32(RiverCenterX + 10), b: 56))
    tickWorld(game, proc() = runBotDecisions(game))
  closeBotServices(game)
  closedReplay(game.recorder.data)

proc replayGame(data: ReplayData): Game =
  result = newGame(map, int32(data.hashes.len), true, data)
  result.maximumTicks = int32(data.hashes.len)
  result.replayPlayer = initReplayPlayer(data)
  result.historyPlayback = true
  for i, pudge in data.header.setup.pudges:
    if pudge.controller == ControllerHuman:
      result.humanSlots.add i

proc rows(path: string): seq[JsonNode] =
  for line in path.readFile().splitLines():
    if line.strip().len > 0:
      result.add parseJson(line)

let tape = recordedMatch()
doAssert tape.hashes.len == int(Ticks)
let outPath = getTempDir() / ("pw-branch-" & $getCurrentProcessId() & ".jsonl")

echo "Testing a window is scored for every eligible option plus none"
block:
  let game = replayGame(tape)
  var opts = BranchOptions(path: "tape", slot: HeroSlot, ticks: @[161'i32],
    horizon: Horizon, seeds: 1, botPath: basBotPath, outPath: outPath)
  runBranch(game, opts)
  doAssert game.world.tick == 161, $game.world.tick
  let scored = rows(outPath)
  let expected = windowOptions(game.world, HeroSlot)
  doAssert scored.mapIt(it["option"].getStr) == expected, $scored.mapIt(it["option"].getStr)
  doAssert expected[^1] == NoneOption and expected.len >= 2, $expected
  for row in scored:
    doAssert row["tick"].getInt == 161
    doAssert row["horizon"].getInt == int(Horizon), $row
    doAssert row["max_hp"].getInt > 0
    # Every option but none translates into an order; none issues nothing.
    doAssert row["queued"].getBool == (row["option"].getStr != NoneOption), $row

echo "Testing a teacher script answers each window with an offered option"
block:
  let game = replayGame(tape)
  var opts = BranchOptions(path: "tape", slot: HeroSlot, ticks: @[161'i32],
    horizon: Horizon, seeds: 1, botPath: basBotPath, outPath: outPath,
    teachers: @[basBotPath])
  runBranch(game, opts)
  let scored = rows(outPath)
  let teacherRows = scored.filterIt(it.hasKey("teacher"))
  doAssert teacherRows.len == 1, $teacherRows.len
  doAssert teacherRows[0]["teacher"].getStr == "base"
  let label = teacherRows[0]["label"].getStr
  doAssert label in windowOptions(game.world, HeroSlot), label
  # Rollout rows are unchanged by the teacher ask.
  doAssert scored.len == teacherRows.len + windowOptions(game.world, HeroSlot).len
  echo "  base would " & label & " at tick 161"

echo "Testing rollouts leave the replay untouched and stay deterministic"
block:
  let game = replayGame(tape)
  while game.world.tick < 193:
    tickWorld(game, proc() = discard)
  let hashBefore = game.stateHash()
  let first = scoreWindow(game, HeroSlot, @["none"], Horizon, 1, basBotPath)
  let second = scoreWindow(game, HeroSlot, @["none"], Horizon, 1, basBotPath)
  doAssert game.world.tick == 193 and game.stateHash() == hashBefore
  doAssert first.len == 1 and $first[0] == $second[0], $first & "\n" & $second
  # The replay still verifies tick for tick after branching off it.
  while game.world.tick < int32(tape.hashes.len):
    tickWorld(game, proc() = discard)
  doAssert game.hashCheck.mismatches == 0, "replay diverged after branching"

echo "Testing several windows score in one pass and the forced hook is thrown"
block:
  let game = replayGame(tape)
  # The first window after the walk where an enemy is in hook range.
  var hookTick = 200'i32
  var hookId = ""
  block:
    let probe = replayGame(tape)
    while probe.world.tick < Ticks - Horizon:
      tickWorld(probe, proc() = discard)
      if probe.world.tick >= 100 and (probe.world.tick - 1) mod 32 == 0:
        let (actions, _) = practiceOptions(probe.world, HeroSlot)
        for item in actions:
          if item.id.startsWith("hook_"):
            hookId = item.id
            hookTick = probe.world.tick
        if hookId.len > 0:
          break
  var opts = BranchOptions(path: "tape", slot: HeroSlot,
    ticks: @[33'i32, hookTick], horizon: Horizon, seeds: 2,
    botPath: basBotPath, outPath: outPath)
  runBranch(game, opts)
  let scored = rows(outPath)
  doAssert scored.anyIt(it["tick"].getInt == 33) and
    scored.anyIt(it["tick"].getInt == int(hookTick))
  doAssert scored.allIt(it["seed"].getInt in [0, 1])
  if hookId.len > 0:
    let thrown = scored.filterIt(it["tick"].getInt == int(hookTick) and
      it["option"].getStr == hookId)
    doAssert thrown.len == 2 and thrown.allIt(it["hooks_thrown"].getInt >= 1),
      $thrown
    echo "  forced ", hookId, " at tick ", hookTick, " threw"
  else:
    echo "  (no enemy came into range on this tape; hook check skipped)"

removeFile(outPath)
echo "branch tests passed"
