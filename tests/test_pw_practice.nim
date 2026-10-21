## Jev practice coach: fog-honest options, exact decision samples, traces.
import
  std/[json, os, sequtils, strutils, tables],
  polyworld/[cli, oracles],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/practice,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  MatchTicks = 2000'i32
  HeroSlot = 0
  LipRow = 56
    ## Near the fountain bulge the lips sit 16 tiles apart: inside
    ## shared sight, and the line between them clears the rocks.
  LipWest = RiverCenterX - riverHalfWidthAt(LipRow) - 1
  LipEast = RiverCenterX + riverHalfWidthAt(LipRow) + 1

let
  map = generateMap(2026)
  basBotPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"
  traceRoot = getTempDir() / "pw-practice-test-" & $getCurrentProcessId()

proc freshGame(): Game =
  result = newGame(map, MatchTicks, false, ReplayData())
  loadBots(result, [BotGroup(path: basBotPath, count: PudgeCount)])
  result.humanSlots.add HeroSlot
  # Everyone parked at home; tests drop one enemy into the river, which
  # shared sight always lights.
  for i, at in [(LipWest, LipRow), (18, 16), (18, 112), (106, 16), (106, 64), (106, 112)]:
    result.world.pudges[i].placePudge(at[0], at[1])
    result.world.pudges[i].shieldTicks = 0

proc play(game: Game, ticks: int) =
  for _ in 0 ..< ticks:
    tickWorld(game, proc() = runBotDecisions(game))
    practiceTick(game)

proc queueHero(game: Game, kind: IntentKind, a = 0'i32, b = 0'i32) =
  queueIntent(game, HumanIntent(slot: int32(HeroSlot), kind: kind, a: a, b: b))

proc ids(list: seq[PracticeOption]): seq[string] =
  for item in list:
    result.add item.id

removeDir(traceRoot)

echo "Testing eligible options from the human's fogged view"
block:
  let game = freshGame()
  let enemy = game.world.pudges[3]
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let (actions, strategies) = practiceOptions(game.world, HeroSlot)
  doAssert ("hook_" & $enemy.id) in actions.ids, $actions.ids
  doAssert "reposition" in actions.ids
  doAssert "scout" notin actions.ids
  doAssert strategies.ids[0] == "coordinate", $strategies.ids
  doAssert "fish" in strategies.ids
  # The far enemy on the enemy bank is beyond shared sight.
  doAssert ("hook_" & $game.world.pudges[5].id) notin actions.ids

echo "Testing the hook solution leads a moving target and knows when to hold"
block:
  let game = freshGame()
  # An enemy on the far lip walking north, away from the fountain rocks:
  # the meeting point sits ahead of them, after the windup, inside range,
  # on a clear line.
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.world.pudges[3].velZ = -(WorldScale div 4)
  let enemy = game.world.pudges[3]
  let moving = hookSolution(game.world, HeroSlot, enemy)
  doAssert moving.targetId == enemy.id
  doAssert moving.ok, moving.reason
  doAssert moving.moving
  doAssert moving.ticks > HookWindupTicks, $moving.ticks
  doAssert moving.aimZ < moving.fromZ - 1.0, $moving.aimZ & " vs " & $moving.fromZ
  doAssert abs(moving.aimX - moving.fromX) < 0.01
  doAssert moving.leadTiles > 1.0
  doAssert moving.inRange and moving.clear
  doAssert aimAdvice(moving).startsWith("Throw at the marker"), aimAdvice(moving)
  # Standing still: no lead, a quicker meeting.
  game.world.pudges[3].velZ = 0
  let still = hookSolution(game.world, HeroSlot, game.world.pudges[3])
  doAssert still.ok and not still.moving and still.leadTiles < 0.01
  doAssert still.ticks < moving.ticks
  # A teammate parked on the line blocks the throw.
  game.world.pudges[1].placePudge((LipWest + LipEast) div 2, LipRow)
  game.world.pudges[1].shieldTicks = 0
  let blocked = hookSolution(game.world, HeroSlot, game.world.pudges[3])
  doAssert not blocked.ok and blocked.reason == "blocked", blocked.reason
  doAssert aimAdvice(blocked).startsWith("Line is blocked")
  game.world.pudges[1].placePudge(18, 16)
  # Too far: the hook runs out before it arrives.
  game.world.pudges[3].placePudge(126, LipRow)
  let far = hookSolution(game.world, HeroSlot, game.world.pudges[3])
  doAssert not far.ok and far.reason == "range", far.reason
  doAssert aimAdvice(far).startsWith("Out of reach")
  # The pilot aims at the meeting point, not where the enemy stands.
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.world.pudges[3].velZ = -(WorldScale div 4)
  let p = practiceBegin(game, traceRoot / "aim", enabled = true, offline = true)
  game.play(1)
  let aim = coachAim(p, game.world)
  doAssert aim.targetId == game.world.pudges[3].id, $aim.targetId
  doAssert aim.primary, "the local cue names the only enemy"
  doAssert aim.aimZ < aim.fromZ - 0.5
  practiceFinish(game)

echo "Testing low health is an urgent local retreat cue"
block:
  let game = freshGame()
  game.world.pudges[HeroSlot].hp = 200
  game.world.pudges[HeroSlot].maxHp = 1000
  let (actions, strategies) = practiceOptions(game.world, HeroSlot)
  doAssert actions[0].id == "retreat" and actions[0].urgent, $actions.ids
  doAssert strategies[0].id == "recover", $strategies.ids
  doAssert ("hook_" & $game.world.pudges[3].id) notin actions.ids

echo "Testing the request drafts both Choice questions with a none option"
block:
  let game = freshGame()
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let (actions, strategies) = practiceOptions(game.world, HeroSlot)
  let body = practiceRequest(newOracle(), "jev-test",
    observationJson(game.world, HeroSlot), actions, strategies)
  doAssert body.len > 0
  let request = parseJson(body)
  doAssert request["model"].getStr == "jev-test"
  doAssert request["questions"]["action"]["type"].getStr == "choice"
  let criteria = request["questions"]["action"]["criteria"]
  doAssert criteria.hasKey("hook_" & $game.world.pudges[3].id)
  doAssert criteria.hasKey("none")
  doAssert request["questions"]["strategy"]["criteria"].hasKey("coordinate")
  let obs = request["state"]["observation"]
  doAssert obs["self"]["hp"].getInt == game.world.pudges[HeroSlot].hp
  doAssert obs["self"].hasKey("hook_ready")
  var sawEnemy = false
  for p in obs["visible"]["pudges"]:
    if p["id"].getInt == game.world.pudges[3].id:
      sawEnemy = true
      doAssert not p.hasKey("hook_ready"), "enemy cooldowns are private"
  doAssert sawEnemy

echo "Testing a hook intent closes the window as that enemy and records files"
block:
  let game = freshGame()
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let enemyId = game.world.pudges[3].id
  let p = practiceBegin(game, traceRoot / "hook", enabled = true, offline = true)
  doAssert p.enabled and p.slot == HeroSlot
  doAssert p.status == "local", p.status
  game.play(1)
  doAssert p.cue.source == "local" and p.cue.option.id.len > 0
  var probabilities = {"hook_" & $enemyId: 900'i32, "none": 100'i32}.toTable
  practiceBindAnswer(p, game.world.tick, "hook_" & $enemyId, "coordinate",
    900, 800, probabilities, 120)
  game.play(1)
  doAssert p.cue.source == "jev", p.cue.source
  doAssert p.cue.option.id == "hook_" & $enemyId
  doAssert not p.cue.tentative
  doAssert p.plan.option.id == "coordinate" and p.plan.source == "jev"
  game.queueHero(IntentHook, int32(LipEast), int32(LipRow))
  game.play(1)
  doAssert p.hasLast
  doAssert p.last.humanId == "hook_" & $enemyId, p.last.humanId
  doAssert p.last.agreed == 1
  doAssert p.stats.samples == 1 and p.stats.compared == 1 and p.stats.agreed == 1
  doAssert p.stats.hooksThrown == 1
  let intents = readFile(p.dir / "intents.jsonl").strip.splitLines
  doAssert intents.len == 1, $intents
  doAssert parseJson(intents[0])["kind"].getStr == "IntentHook"
  let samples = readFile(p.dir / "samples.jsonl").strip.splitLines
  doAssert samples.len == 1
  let sample = parseJson(samples[0])
  doAssert sample["human"]["id"].getStr == "hook_" & $enemyId
  doAssert sample["jev"]["action"].getStr == "hook_" & $enemyId
  doAssert sample["jev"]["probabilities"]["none"].getFloat == 0.1
  doAssert sample["agreed"].getBool
  doAssert sample["observation"]["self"]["id"].getInt ==
    game.world.pudges[HeroSlot].id
  # The recorded request re-renders the prompt: state keys in order,
  # observation left to the sample, option text and both questions.
  let request = sample["request"]
  var keys: seq[string]
  for key, _ in request["state"]:
    keys.add key
  doAssert keys == @["game", "view", "actions", "strategies"], $keys
  doAssert request["state"]["actions"].hasKey("hook_" & $enemyId)
  doAssert request["questions"]["action"]["criteria"].hasKey("none")
  doAssert request["questions"]["strategy"]["type"].getStr == "choice"
  practiceFinish(game)
  let summary = parseJson(readFile(p.dir / "summary.json"))
  doAssert summary["samples"].getInt == 1
  doAssert summary["agreed"].getInt == 1
  doAssert p.status == "finished"

echo "Testing a walk home when hurt reads as a retreat and disagrees"
block:
  let game = freshGame()
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.world.pudges[HeroSlot].hp = 500
  game.world.pudges[HeroSlot].maxHp = 1000
  let p = practiceBegin(game, traceRoot / "walk", enabled = true, offline = true)
  game.play(1)
  practiceBindAnswer(p, game.world.tick, "hook_" & $game.world.pudges[3].id,
    "fish", 950, 700, initTable[string, int32](), 90)
  let home = game.world.pudges[HeroSlot].spawnTile
  game.queueHero(IntentWalk, int32(home.x), int32(home.z))
  game.play(int(TickRate) + 1)
  doAssert p.hasLast
  doAssert p.last.humanId == "retreat", p.last.humanId
  doAssert p.last.agreed == 0
  doAssert p.stats.compared == 1 and p.stats.agreed == 0
  practiceFinish(game)

echo "Testing an expired answer falls back to local guidance"
block:
  let game = freshGame()
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let p = practiceBegin(game, traceRoot / "expiry", enabled = true, offline = true)
  game.play(1)
  practiceBindAnswer(p, game.world.tick, "hook_" & $game.world.pudges[3].id,
    "coordinate", 900, 800, initTable[string, int32](), 100)
  game.play(1)
  doAssert p.cue.source == "jev"
  game.play(int(AnswerMaxAgeTicks) + 2)
  doAssert p.cue.source == "local", p.cue.source
  doAssert p.stats.samples >= 2
  practiceFinish(game)

echo "Testing practice stays off without a human seat"
block:
  let game = newGame(map, MatchTicks, false, ReplayData())
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount)])
  let p = practiceBegin(game, traceRoot / "none", enabled = true, offline = true)
  doAssert not p.enabled
  game.play(3)
  doAssert not dirExists(traceRoot / "none")

echo "Testing endpoint names resolve to allowed base URLs and defaults"
block:
  let jev = coachConfig("jev", "")
  doAssert jev.endpoint == PracticeEndpoint and jev.provider == "typesafe"
  let d1 = coachConfig("d1", "")
  doAssert d1.endpoint == LiquidEndpoint and d1.provider == "liquid"
  doAssert d1.model == LiquidDefaultModel
  let local = coachConfig("local", "custom-merge")
  doAssert local.endpoint == LocalEndpoint and local.provider == "local"
  doAssert local.model == "custom-merge"
  let url = coachConfig("http://127.0.0.1:9000/", "")
  doAssert url.endpoint == "http://127.0.0.1:9000" and url.provider == "local"

echo "Testing a local pilot drives its seat through the intent queue"
block:
  let game = freshGame()
  game.humanSlots.add 3
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let p = pilotBegin(game, 3, traceRoot / "pilot", offline = true)
  doAssert p.enabled and p.actor == "pilot" and p.slot == 3
  doAssert p.dir == traceRoot / "pilot" / "pilot-3"
  doAssert fileExists(p.dir / "match.json")
  let meta = parseJson(readFile(p.dir / "match.json"))
  doAssert meta["actor"].getStr == "pilot" and meta["started_ms"].getInt > 0
  # The pilot sees the human hero across the river and, with no model,
  # takes the first local option: a hook on that hero.
  game.play(3)
  doAssert p.cue.source == "local"
  let intents = readFile(p.dir / "intents.jsonl").strip.splitLines
  doAssert intents.len >= 1, $intents
  let first = parseJson(intents[0])
  doAssert first["kind"].getStr == "IntentHookFine", $first
  doAssert first["accepted"].getBool
  doAssert first["at_ms"].getInt > 0
  doAssert game.world.pudges[3].hooksThrown == 1
  # The window closes with what the pilot did, labelled by actor.
  game.play(int(AskEveryTicks) + 2)
  let samples = readFile(p.dir / "samples.jsonl").strip.splitLines
  doAssert samples.len >= 1
  let sample = parseJson(samples[0])
  doAssert sample["actor"].getStr == "pilot"
  doAssert sample["human"]["id"].getStr == "hook_" & $game.world.pudges[HeroSlot].id
  doAssert sample["cue"]["source"].getStr == "local"
  doAssert sample["at_ms"].getInt > 0
  practiceFinish(game)
  doAssert p.status == "finished"
  let summary = parseJson(readFile(p.dir / "summary.json"))
  doAssert summary["actor"].getStr == "pilot"
  doAssert summary["hooks_thrown"].getInt >= 1

echo "Testing a pilot waits for the model, then follows its answer"
block:
  let game = freshGame()
  game.humanSlots.add 3
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.world.pudges[3].hp = 200
  game.world.pudges[3].maxHp = 1000
  let p = pilotBegin(game, 3, traceRoot / "pilot-model", offline = true)
  game.play(1)
  # Urgent local retreat wins regardless; a bound answer still records.
  practiceBindAnswer(p, game.world.tick, "reposition", "fish", 900, 700,
    initTable[string, int32](), 50)
  game.play(2)
  let intents = readFile(p.dir / "intents.jsonl").strip.splitLines
  doAssert intents.len >= 1, $intents
  doAssert parseJson(intents[0])["kind"].getStr == "IntentWalk", $intents
  practiceFinish(game)

echo "Testing the coach and pilots share one match directory"
block:
  let game = freshGame()
  game.humanSlots.add 3
  let c = practiceBegin(game, traceRoot / "shared", enabled = true,
    offline = true, endpoint = "d1")
  doAssert c.enabled and c.provider == "liquid"
  let p = pilotBegin(game, 3, c.dir, offline = true, endpoint = "d1")
  doAssert p.dir == c.dir / "pilot-3"
  game.play(2)
  practiceFinish(game)
  doAssert fileExists(c.dir / "summary.json")
  doAssert fileExists(c.dir / "pilot-3" / "summary.json")

echo "Testing melee, rot and blink options and the pilot's intents for them"
block:
  let game = freshGame()
  game.humanSlots.add 3
  # An enemy standing beside the hero: attack and rot are on the table.
  game.world.pudges[3].placePudge(LipWest + 1, LipRow)
  game.world.pudges[3].shieldTicks = 0
  game.world.pudges[HeroSlot].shieldTicks = 0
  let (actions, _) = practiceOptions(game.world, HeroSlot)
  let enemyId = game.world.pudges[3].id
  doAssert ("attack_" & $enemyId) in actions.ids, $actions.ids
  doAssert "rot" in actions.ids, $actions.ids
  let p = pilotBegin(game, 3, traceRoot / "melee", offline = true)
  # The pilot on seat 3 sees the hero beside it and can attack or rot.
  game.play(1)
  let heroId = game.world.pudges[HeroSlot].id
  doAssert ("attack_" & $heroId) in p.offered.ids, $p.offered.ids
  var intent: HumanIntent
  doAssert p.pilotIntent(game.world, 1, p.offered.find("attack_" & $heroId), intent)
  doAssert intent.kind == IntentAttack and intent.a == heroId
  doAssert p.pilotIntent(game.world, 1, p.offered.find("rot"), intent)
  doAssert intent.kind == IntentRot
  practiceFinish(game)
  # Low health with blink ready offers blink, which jumps away.
  let g2 = freshGame()
  g2.world.pudges[HeroSlot].hp = 200
  g2.world.pudges[HeroSlot].maxHp = 1000
  g2.world.pudges[HeroSlot].blinkCooldown = 0
  let (low, _) = practiceOptions(g2.world, HeroSlot)
  doAssert "blink" in low.ids and "retreat" in low.ids, $low.ids

echo "Testing a speculative hook is offered at the lip with nothing in sight"
block:
  let game = freshGame()
  let (actions, _) = practiceOptions(game.world, HeroSlot)
  doAssert "hook_blind" in actions.ids, $actions.ids
  doAssert not actions.ids.anyIt(it.startsWith("hook_") and it != "hook_blind")
  let c = practiceBegin(game, traceRoot / "blind", enabled = true, offline = true)
  var intent: HumanIntent
  doAssert c.pilotIntent(game.world, 1, actions.find("hook_blind"), intent)
  doAssert intent.kind == IntentHookFine and intent.a > int32(RiverCenterX) * 256
  practiceFinish(game)

echo "Testing a shadowed script seat records windows labelled by its actions"
block:
  let game = freshGame()
  game.recorder = initReplayRecorder(currentSetup(game, uint32(MatchTicks)))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let shadow = shadowBegin(game, 3, traceRoot / "shadow")
  doAssert shadow.enabled and shadow.actor == "bot" and shadow.status == "shadow"
  doAssert shadow.dir == traceRoot / "shadow" / "bot-3"
  game.play(int(AskEveryTicks) * 3)
  practiceFinish(game)
  let samples = readFile(shadow.dir / "samples.jsonl").strip.splitLines.mapIt(parseJson(it))
  doAssert samples.len >= 2, $samples.len
  doAssert samples.allIt(it["actor"].getStr == "bot")
  let labels = samples.mapIt(it["human"]["id"].getStr)
  doAssert labels.anyIt(it != "none" and it.len > 0), $labels
  let acts = readFile(shadow.dir / "intents.jsonl").strip.splitLines.mapIt(parseJson(it))
  doAssert acts.len > 0 and acts.allIt(it["kind"].getStr.len > 0)
  let meta = parseJson(readFile(shadow.dir / "match.json"))
  doAssert meta["actor"].getStr == "bot" and meta["provider"].getStr == "script"
  # A human or pilot seat cannot be shadowed.
  doAssert not shadowBegin(game, HeroSlot, traceRoot / "shadow").enabled

echo "Testing --coach none seats a pilot on local guidance alone"
block:
  let game = freshGame()
  game.humanSlots.add 3
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let p = pilotBegin(game, 3, traceRoot / "drafter", endpoint = "none")
  doAssert p.enabled and p.provider == "drafter" and p.model == "local-drafter"
  doAssert p.status == "local", p.status
  game.play(3)
  doAssert p.cue.source == "local" and game.world.pudges[3].hooksThrown == 1
  practiceFinish(game)

echo "Testing an event opens a window between heartbeats"
block:
  let game = freshGame()
  let p = practiceBegin(game, traceRoot / "events", enabled = true, offline = true)
  game.play(3)
  # An enemy steps onto the lip: contact. The window opens once the
  # minimum gap since the heartbeat has passed, not at the next heartbeat.
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.play(int(AskMinGapTicks) + 4)
  practiceFinish(game)
  let samples = readFile(p.dir / "samples.jsonl").strip.splitLines
  doAssert samples.len == 2, $samples.len
  let first = parseJson(samples[0])
  let second = parseJson(samples[1])
  doAssert first["trigger"].getStr == "periodic" and first["tick"].getInt == 1
  doAssert second["trigger"].getStr == "contact", second["trigger"].getStr
  doAssert second["tick"].getInt > 1 and second["tick"].getInt < int(AskEveryTicks),
    $second["tick"]
  doAssert ("hook_" & $game.world.pudges[3].id) in second["options"].mapIt(it.getStr)

echo "Testing periodic-only asks ignore events"
block:
  askEvents = false
  let game = freshGame()
  let p = practiceBegin(game, traceRoot / "periodic", enabled = true, offline = true)
  game.play(3)
  game.world.pudges[3].placePudge(LipEast, LipRow)
  game.play(int(AskMinGapTicks) + 4)
  practiceFinish(game)
  askEvents = true
  let samples = readFile(p.dir / "samples.jsonl").strip.splitLines
  doAssert samples.len == 1, $samples.len

echo "Testing pilot noise executes an option other than the cue"
block:
  let game = freshGame()
  game.humanSlots.add 3
  game.world.pudges[3].placePudge(LipEast, LipRow)
  let p = pilotBegin(game, 3, traceRoot / "noise", offline = true)
  p.pilotNoise(1.0, seed = 42)
  doAssert p.noise == 1000
  game.play(3)
  doAssert p.cue.source == "local"
  let hookId = "hook_" & $game.world.pudges[HeroSlot].id
  doAssert p.cue.option.id == hookId
  game.play(int(AskEveryTicks) + 2)
  practiceFinish(game)
  let sample = parseJson(readFile(p.dir / "samples.jsonl").strip.splitLines[0])
  doAssert sample["cue"]["source"].getStr == "noise", $sample["cue"]
  doAssert sample["cue"]["id"].getStr != hookId, $sample["cue"]
  doAssert sample["cue"]["id"].getStr in sample["options"].mapIt(it.getStr)

removeDir(traceRoot)
echo "practice tests passed"

echo "Testing fitted thresholds replace the constants per option class"
block:
  doAssert optionClass("hook_7") == "hook" and optionClass("rescue_2") == "hook"
  doAssert optionClass("regroup") == "move" and optionClass("retreat") == "safety"
  doAssert optionClass("upgrade") == "economy" and optionClass("none") == "none"
  let (actions, _) = practiceOptions(freshGame().world, HeroSlot)
  doAssert actions.len > 0
  # Without a table the built-in constants hold.
  thresholds = ThresholdTable()
  doAssert thresholdFor(actions[0]) == actions[0].threshold
  doAssert strategyThreshold() == 600
  let table = parseThresholds("""{"model": "jev-latest", "default": 0.7,
    "classes": {"hook": {"threshold": 0.9}, "move": 0.55, "strategy": 0.65}}""", "t.json")
  doAssert table.loaded and table.model == "jev-latest" and table.default == 700
  doAssert table.classes["hook"] == 900 and table.classes["move"] == 550
  thresholds = table
  doAssert thresholdFor(PracticeOption(id: "hook_3", threshold: 850)) == 900
  doAssert thresholdFor(PracticeOption(id: "scout", threshold: 600)) == 550
  doAssert thresholdFor(PracticeOption(id: "upgrade", threshold: 600)) == 700
  doAssert strategyThreshold() == 650
  # A missing file leaves the constants in force; a present one installs.
  doAssert not loadThresholds(getTempDir() / "pw-no-such-thresholds.json").loaded
  doAssert not thresholds.loaded
  let path = getTempDir() / ("pw-thresholds-" & $getCurrentProcessId() & ".json")
  writeFile(path, """{"default": 0.5, "classes": {"hook": 0.95}}""")
  doAssert loadThresholds(path).loaded and thresholds.path == path
  doAssert thresholdFor(PracticeOption(id: "hook_1", threshold: 850)) == 950
  doAssert thresholdFor(PracticeOption(id: "scout", threshold: 600)) == 500
  removeFile(path)

echo "Testing a pilot delegates only above the fitted threshold"
block:
  let game = freshGame()
  # Beyond half a hook's reach of the lip, so no speculative hook leads
  # the local options.
  game.world.pudges[HeroSlot].placePudge(LipWest - 40, LipRow)
  let pilot = pilotBegin(game, HeroSlot, traceRoot / "fitted", offline = true)
  doAssert pilot.enabled
  play(game, 1)
  # Local guidance leads with its first option; the model prefers another,
  # whose class gets a high fitted threshold.
  doAssert pilot.offered.len >= 2, $pilot.offered.ids
  let local = pilot.offered[0].id
  let alt = pilot.offered[1].id
  thresholds = parseThresholds(
    "{\"default\": 0.5, \"classes\": {\"" & optionClass(alt) & "\": 0.9}}")
  # A confident-looking answer under its class threshold is not the cue.
  pilot.practiceBindAnswer(game.world.tick, alt, "none", 800, 0,
    {alt: 800'i32, local: 200'i32}.toTable)
  play(game, 1)
  doAssert pilot.cue.source == "local" and pilot.cue.option.id == local,
    pilot.cue.option.id & "/" & pilot.cue.source
  doAssert pilot.stats.answers == 1 and pilot.stats.delegated == 0
  # One that clears it replaces the held local cue at once.
  pilot.practiceBindAnswer(game.world.tick, alt, "none", 950, 0,
    {alt: 950'i32, local: 50'i32}.toTable)
  play(game, 1)
  doAssert pilot.cue.source == "jev" and pilot.cue.option.id == alt,
    pilot.cue.option.id & "/" & pilot.cue.source
  doAssert pilot.stats.delegated == 1
  practiceFinish(game)
  let summary = parseJson(readFile(traceRoot / "fitted" / "pilot-0" / "summary.json"))
  doAssert summary["answers"].getInt == 2 and summary["delegated"].getInt == 1
  thresholds = ThresholdTable()
