import std/[json, os, strutils, tempfiles, unittest], bassy,
  polyworld/[cli, tapes],
  ../examples/pudge_wars/[bots, content, fileplayers, maps, replays, sim]

let root = createTempDir("pudge-fileplayers-", "")
let playersDir = currentSourcePath().parentDir.parentDir /
  "examples/pudge_wars/players"

proc fixture(sources: openArray[string], name: string): tuple[
    players: FilePlayers, game: Game, dir: string] =
  result.dir = root / name
  createDir(result.dir)
  var seats = newJArray()
  for slot, source in sources:
    let path = result.dir / $slot
    createDir(path)
    writeFile(path / "file", source)
    seats.add %*{"slot": slot, "file_uri": "file://" & path & "/file",
      "size_bytes": source.len, "log_uri": "file://" & path & "/log",
      "annotations_uri": "file://" & path & "/annotations.jsonl"}
  result.players = openFilePlayers(%*{"schema": "coworld-player-seats/2",
    "seats": seats, "player_status_uri": "file://" & result.dir & "/status"},
    sources.len, "file://" & result.dir & "/failure")
  result.game = newGame(generateMap(7, if sources.len == 2: TeamSize else: sources.len div 2),
    128, false, ReplayData(), duel = sources.len == 2)

suite "game-hosted BASIC seats":
  test "local paths preserve literal plus and reject remote URIs":
    check localPath("file:///tmp/a+b%20c") == "/tmp/a+b c"
    for path in ["https://example.com/file", "file://host/tmp/file", "relative",
                 "file:///tmp/file?query=1", "file:///tmp/%00file"]:
      expect FilePlayerError: discard localPath(path)

  test "invalid rosters fail before opening outputs":
    for document in [%*{}, %*{"schema": "coworld-player-seats/2"},
        %*{"schema": "unknown", "seats": []},
        %*{"schema": "coworld-player-seats/2", "seats": [{}, {}]}]:
      expect FilePlayerError:
        discard openFilePlayers(document, 2, "file://" & root & "/failure")

  test "extensionless files keep variables, strings, prints and annotations private":
    let f = fixture([
      "counter = counter + 1\nprint \"seat-zero-private\"\n" &
      "fraction = 5 / 2\ninteger = 5 \\ 2\ntruth = 1 = 1\n" &
      "text$ = \"hello\"\nANNOTATE(worldTick, \"decision\", \"idle\", \"{}\")\n",
      "counter = counter + 7\nprint \"seat-one-private\"\n"], "privacy")
    check f.players.load(f.game)
    for _ in 0 ..< 2: tickWorld(f.game, proc() = runBotDecisions(f.game))
    check f.game.heroVms[0].runtime.getGlobal("counter").asInt == 2
    check f.game.heroVms[1].runtime.getGlobal("counter").asInt == 14
    check $f.game.heroVms[0].runtime.getGlobalValue("fraction") == "2.50000"
    check f.game.heroVms[0].runtime.getGlobal("integer").asInt == 2
    check f.game.heroVms[0].runtime.getGlobal("truth").asInt == -1
    for speech in f.game.botSpeech: check speech.text.len == 0
    f.players.finish(f.game)
    let first = readFile(f.dir / "0/log")
    let second = readFile(f.dir / "1/log")
    check "seat-zero-private" in first and "seat-one-private" notin first
    check "seat-one-private" in second and "seat-zero-private" notin second
    let annotation = parseJson(readFile(f.dir / "0/annotations.jsonl").splitLines[0])
    check annotation["function"].getStr == "idle"
    check not fileExists(f.dir / "1/annotations.jsonl")
    check not fileExists(f.dir / "failure")

  test "compilation errors attribute the seat without public source":
    let f = fixture(["print 1", "this is private invalid syntax"], "compile-error")
    check not f.players.load(f.game)
    let failure = parseJson(readFile(f.dir / "failure"))
    check failure["failed_policy_index"].getInt == 1
    check "private" notin $failure
    check fileExists(f.dir / "0/log") and fileExists(f.dir / "1/log")

  test "source limits fail before compiling":
    let f = fixture(["'" & repeat('x', 65536), "print 1"], "oversize")
    check not f.players.load(f.game)
    check parseJson(readFile(f.dir / "failure"))["failed_policy_index"].getInt == 0

  test "runtime budget errors disable only the offending VM":
    let f = fixture(["while 1\nwend", "counter = counter + 1"], "runtime-error")
    check f.players.load(f.game)
    for _ in 0 ..< 2: tickWorld(f.game, proc() = runBotDecisions(f.game))
    check f.game.heroVms[0].failed
    check not f.game.heroVms[1].failed
    check f.game.heroVms[1].runtime.getGlobal("counter").asInt == 2
    f.players.finish(f.game)
    check not fileExists(f.dir / "failure")
    let status = parseJson(readFile(f.dir / "status"))
    check status["players"][0]["exit_code"].getInt == 1
    check status["players"][1]["exit_code"].getInt == 0

  test "silent seats still have logs and excessive output is bounded":
    let f = fixture(["x = 1", "x = 2"], "logs")
    check f.players.load(f.game)
    f.players.playerLog(0, repeat('x', PlayerLogLimit + 1))
    f.players.playerLog(0, "must be discarded")
    f.players.finish(f.game)
    check getFileSize(f.dir / "0/log") == PlayerLogLimit
    check "truncated" in readFile(f.dir / "0/log")
    check fileExists(f.dir / "1/log")

  test "native and file seats match and replay exactly for every roster size":
    for count in [2, 4, 6, 8, 10]:
      var sources: seq[string]
      var groups: seq[BotGroup]
      for slot in 0 ..< count:
        let path = playersDir / (if slot < count div 2: "base.bas" else: "aggressive.bas")
        sources.add readFile(path)
        groups.add BotGroup(path: path, count: 1)
      let f = fixture(sources, "parity-" & $count)
      check f.players.load(f.game)
      let native = newGame(f.game.map, 128, false, ReplayData(), duel = count == 2)
      native.loadBots(groups)
      f.game.recorder = initReplayRecorder(currentSetup(f.game, 128))
      f.game.replayPlayer = ReplayPlayer(data: f.game.recorder.data)
      for _ in 0 ..< 128:
        tickWorld(f.game, proc() = runBotDecisions(f.game))
        tickWorld(native, proc() = runBotDecisions(native))
        check stateHash(f.game) == stateHash(native)
      for vm in f.game.heroVms: check not vm.failed
      let replay = decodeReplay(encodeCoworldReplay(f.game.recorder.data))
      let follower = Game(world: newWorld(f.game.map, 128, replay.header.setup.pudges,
        replay.header.setup.killGoal, replay.header.setup.runePeriod),
        map: f.game.map, maximumTicks: 128, botEvery: 1, historyPlayback: true,
        replayPlayer: ReplayPlayer(data: replay))
      for tick in 1'u32 .. 128'u32:
        tickWorld(follower, proc() = discard)
        var expected: uint64
        check replay.hashes.hashAt(tick, expected)
        check stateHash(follower) == expected
      f.players.finish(f.game)

removeDir(root)
