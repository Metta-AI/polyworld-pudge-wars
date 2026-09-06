## 1v1 duel mode: roster, bot fill, replay round-trip, and the match
## analysis logs the improvement loop reads.

import
  std/[json, os, strutils, tempfiles],
  polyworld/[cli, tapes],
  ../examples/pudge_wars/[bots, content, duellog, maps, replays, sim]

let
  playersDir =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players"
  map = generateMap(2026)

proc newDuel(ticks: int32): Game =
  newGame(map, ticks, false, ReplayData(), DuelKillGoal, RunePeriodTicks,
    duel = true)

proc startRecording(game: Game, maximumTicks: uint32) =
  game.recorder = initReplayRecorder(currentSetup(game, maximumTicks))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)

proc loadDuelBots(game: Game) =
  loadBots(game, [
    BotGroup(path: playersDir / "challenger.bas", count: 1),
    BotGroup(path: playersDir / "base.bas", count: 1)
  ])

echo "Testing the duel roster"
block:
  let setup = livePudgeSetup(duel = true)
  doAssert setup.len == DuelPudgeCount
  doAssert setup[0].team == uint8(WestTeam.ord)
  doAssert setup[1].team == uint8(EastTeam.ord)
  doAssert setup[0].slot == 1 and setup[1].slot == 1,
    "both butchers use team slot 1"
  let game = newDuel(400)
  doAssert game.world.pudges.len == DuelPudgeCount
  doAssert game.world.pudges[0].team == WestTeam
  doAssert game.world.pudges[1].team == EastTeam
  doAssert game.world.killGoal == DuelKillGoal
  # Mirrored pads face each other across the river (same Z, mirrored X).
  doAssert game.world.pudges[0].position.z == game.world.pudges[1].position.z
  doAssert game.world.pudges[0].position.x < game.world.pudges[1].position.x

echo "Testing the challenger policy runs on both banks"
block:
  var game = newDuel(400)
  loadBots(game, [
    BotGroup(path: playersDir / "challenger.bas", count: 2)
  ])
  doAssert game.heroVms.len == DuelPudgeCount
  for _ in 0 ..< 64:
    tickWorld(game, proc() = runBotDecisions(game))
  for i in 0 ..< DuelPudgeCount:
    doAssert game.heroVms[i] != nil
    doAssert not game.heroVms[i].failed,
      "seat " & $i & ": " & game.heroVms[i].lastError
    doAssert game.heroVms[i].decisions > 0

echo "Testing a recorded duel replays hash-clean"
block:
  const MatchTicks = 1200'i32
  var live = newDuel(MatchTicks)
  live.loadDuelBots()
  live.startRecording(uint32(MatchTicks))
  var steps = 0
  while steps < int(MatchTicks) and not live.world.gameOver:
    tickWorld(live, proc() = runBotDecisions(live))
    inc steps
  doAssert live.recordingError.len == 0
  doAssert live.recorder.data.actions.len > 0, "bots recorded no actions"
  doAssert live.recorder.data.header.setup.maximumTicks == uint32(MatchTicks),
    "saving must keep the original match duration"
  let dir = createTempDir("pw_duel_replay", "")
  defer: removeDir(dir)
  let path = dir / "duel.pwr"
  saveReplay(path, live.recorder.data)
  let data = loadReplay(path)
  doAssert data.header.setup.pudges.len == DuelPudgeCount
  doAssert data.header.setup.maximumTicks == uint32(MatchTicks)
  doAssert data.hashes.len == live.world.tick
  var replay = newGame(
    map, int32(data.header.setup.maximumTicks), true, data
  )
  replay.replayPlayer = initReplayPlayer(data)
  replay.historyPlayback = true
  doAssert replay.world.pudges.len == DuelPudgeCount
  while replay.world.tick < data.hashes.len:
    tickWorld(replay, proc() = discard)
  replay.hashCheck.requireReplayComplete(
    uint32(replay.world.tick),
    data.hashes.len
  )
  doAssert replay.replayPlayer.finished
  doAssert replay.stateHash() == live.stateHash(),
    "replay ended in a different state"

echo "Testing the duel analysis log"
block:
  const MatchTicks = 3200'i32
  let base = createTempDir("pw_duel_log", "")
  defer: removeDir(base)
  var game = newDuel(MatchTicks)
  game.loadDuelBots()
  game.startRecording(uint32(MatchTicks))
  let logger = newDuelLogger(
    game,
    nextMatchDir(base),
    @[playersDir / "challenger.bas", playersDir / "base.bas"]
  )
  var steps = 0
  while steps < int(MatchTicks) and not game.world.gameOver:
    tickWorld(game, proc() = runBotDecisions(game))
    logDuelTick(logger, game)
    inc steps
  finishDuelLog(logger, game)
  finishDuelLog(logger, game) # idempotent
  logDuelTick(logger, game)   # ignored after finish

  let lines = readFile(logger.dir / "events.jsonl").strip().splitLines()
  doAssert lines.len > 10, "expected a stream of events"
  let start = parseJson(lines[0])
  doAssert start["ev"].getStr == "match_start"
  doAssert start["mode"].getStr == "duel"
  doAssert start["players"].len == DuelPudgeCount
  for player in start["players"]:
    doAssert player["controller"].getStr == "bot"
    doAssert player.hasKey("policySha")
  let last = parseJson(lines[^1])
  doAssert last["ev"].getStr == "match_end"
  doAssert last["reason"].getStr in ["kill_goal", "time_limit", "quit"]
  var seen: seq[string]
  for line in lines:
    let name = parseJson(line)["ev"].getStr
    if name notin seen:
      seen.add name
  for expected in ["action", "state", "hook_launched"]:
    doAssert expected in seen, "no " & expected & " event logged"

  let summary = parseJson(readFile(logger.dir / "summary.json"))
  doAssert summary["schema"].getInt == 1
  doAssert summary["mode"].getStr == "duel"
  doAssert summary["players"].len == DuelPudgeCount
  doAssert summary["players"][0]["name"].getStr == "challenger"
  doAssert summary["players"][0]["hooksThrown"].getInt > 0,
    "the challenger never threw a hook"
  doAssert summary["hooks"].len > 0
  doAssert summary["score"].hasKey("west") and summary["score"].hasKey("east")

  let history = readFile(base / "history.jsonl").strip().splitLines()
  doAssert history.len == 1, "one finished match, one history line"
  let entry = parseJson(history[0])
  doAssert entry["dir"].getStr == logger.dir.extractFilename
  doAssert entry["players"].len == DuelPudgeCount

echo "Testing log directory rotation"
block:
  let base = createTempDir("pw_duel_dirs", "")
  defer: removeDir(base)
  let
    first = nextMatchDir(base)
    second = nextMatchDir(base)
  doAssert first != second
  doAssert dirExists(first) and dirExists(second)

echo "Testing the policy fingerprint"
block:
  doAssert fnv1a("") == "cbf29ce484222325"
  doAssert fnv1a("hook") != fnv1a("Hook")

echo "Testing duel replays validate"
block:
  var setup = Setup(
    mapSeed: 2026,
    mapHash: map.hash,
    tickRate: uint16(TickRate),
    gridTiles: ReplayGridTiles,
    maximumTicks: 32,
    killGoal: DuelKillGoal,
    botEvery: 1,
    runePeriod: RunePeriodTicks,
    pudges: livePudgeSetup(duel = true)
  )
  var data = initReplayData(setup)
  data.hashes = newSeq[uint64](32)
  validate(data)

echo "test_pw_duel: all checks passed"
