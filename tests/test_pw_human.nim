## Human seat: intent queue drain, acknowledgments, and hash-exact replays.

import
  std/[os, strutils],
  polyworld/[cli, tapes],
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/cheats,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  MatchTicks = 400'i32
  HeroSlot = 0

let
  map = generateMap(2026)
  basBotPath =
    currentSourcePath().parentDir.parentDir /
    "examples" / "pudge_wars" / "players" / "base.bas"

proc freshGame(): Game =
  result = newGame(map, MatchTicks, false, ReplayData())
  result.humanSlots.add HeroSlot

proc play(game: Game, ticks: int) =
  for _ in 0 ..< ticks:
    tickWorld(game, proc() = runBotDecisions(game))

proc startRecording(game: Game, maximumTicks: uint32) =
  game.recorder = initReplayRecorder(currentSetup(game, maximumTicks))
  game.replayPlayer = ReplayPlayer(data: game.recorder.data)

proc queueHero(game: Game, kind: IntentKind, a = 0'i32, b = 0'i32) =
  queueIntent(game, HumanIntent(
    slot: int32(HeroSlot), kind: kind, a: a, b: b
  ))

echo "Testing a human intent drains at the hero turn"
block:
  let game = freshGame()
  game.queueHero(IntentWalk, 30, 64)
  doAssert game.humanIntents.len == 1
  doAssert not game.world.pudges[HeroSlot].hasMoveTarget
  game.play(1)
  doAssert game.humanIntents.len == 0, "the hero turn should drain the queue"
  doAssert game.world.pudges[HeroSlot].hasMoveTarget
  doAssert game.intentResults.len == 1
  doAssert game.intentResults[0].kind == IntentWalk
  doAssert game.intentResults[0].accepted
  doAssert game.intentResults[0].slot == int32(HeroSlot)

echo "Testing rejected intents report without changing the world"
block:
  let game = freshGame()
  game.queueHero(IntentBuy, int32(UpgradeDamage.ord))
  game.play(1)
  doAssert game.intentResults.len == 1
  doAssert not game.intentResults[0].accepted,
    "a broke butcher cannot buy an upgrade"
  doAssert game.world.pudges[HeroSlot].upgrades[UpgradeDamage] == 0

echo "Testing replaceable walk/attack/stop intents coalesce per seat"
block:
  let game = freshGame()
  let enemyId = game.world.pudges[3].id
  for _ in 0 ..< 100:
    game.queueHero(IntentStop)
  doAssert game.humanIntents.len == 1,
    "spammed stop must collapse to the latest order"
  game.queueHero(IntentWalk, 30, 64)
  game.queueHero(IntentAttack, enemyId)
  game.queueHero(IntentWalk, 40, 64)
  game.queueHero(IntentAttack, enemyId)
  doAssert game.humanIntents.len == 1
  doAssert game.humanIntents[0].kind == IntentAttack,
    "a later attack must replace a walk so RMB spam keeps fighting"
  doAssert game.humanIntents[0].a == enemyId
  game.queueHero(IntentBuy, int32(UpgradeDamage.ord))
  doAssert game.humanIntents.len == 2,
    "buy stays queued alongside the replaceable order"
  game.play(1)
  doAssert game.humanIntents.len == 0
  doAssert game.world.pudges[HeroSlot].attackTargetId == enemyId
  doAssert not game.world.pudges[HeroSlot].hasMoveTarget

echo "Testing idle human auto-acquires a nearby enemy"
block:
  let game = freshGame()
  game.world.pudges[HeroSlot].placePudge(30, 64)
  game.world.pudges[3].placePudge(34, 64)
  doAssert game.world.pudges[HeroSlot].attackTargetId == 0
  game.play(1)
  doAssert game.world.pudges[HeroSlot].attackTargetId == game.world.pudges[3].id,
    "an idle human near an enemy should start attacking without a click"
  game.queueHero(IntentStop)
  game.play(1)
  doAssert game.world.pudges[HeroSlot].attackTargetId == 0,
    "Stop must clear the target on the same tick"
  game.play(1)
  doAssert game.world.pudges[HeroSlot].attackTargetId == game.world.pudges[3].id,
    "after Stop, a still-idle human reacquires on the next decision"

echo "Testing a walk order blocks idle auto-acquire"
block:
  let game = freshGame()
  game.world.pudges[HeroSlot].placePudge(30, 64)
  game.world.pudges[3].placePudge(34, 64)
  game.queueHero(IntentWalk, 20, 64)
  game.play(1)
  doAssert game.world.pudges[HeroSlot].hasMoveTarget
  doAssert game.world.pudges[HeroSlot].attackTargetId == 0,
    "a move order is an instruction: do not auto-attack while walking"

echo "Testing the intent result feed stays bounded"
block:
  let game = freshGame()
  for _ in 0 ..< 100:
    game.queueHero(IntentBuy, int32(UpgradeDamage.ord))
  doAssert game.humanIntents.len == 64, "the oldest floods must drop"
  game.play(1)
  doAssert game.humanIntents.len == 0
  doAssert game.intentResults.len == 64

echo "Testing intents only drive the owned seat"
block:
  let game = freshGame()
  queueIntent(game, HumanIntent(
    slot: 3'i32, kind: IntentWalk, a: 90'i32, b: 64'i32
  ))
  game.play(2)
  doAssert not game.world.pudges[3].hasMoveTarget,
    "a bot seat never drains the human queue"
  doAssert game.humanIntents.len == 1,
    "the foreign intent stays parked instead of leaking"

echo "Testing a human hook intent commits the windup"
block:
  let game = freshGame()
  game.queueHero(
    IntentHookFine,
    fineOfTile(40),
    fineOfTile(64)
  )
  game.play(1)
  doAssert game.world.pudges[HeroSlot].windupTicks > 0,
    "the cast point should start on the drain tick"
  game.play(int(HookWindupTicks))
  var flying = false
  for hook in game.world.hooks:
    if hook.ownerId == game.world.pudges[HeroSlot].id and
        hook.phase != HookIdle:
      flying = true
  doAssert flying, "the wound-up hook should be in the air"
  doAssert game.world.pudges[HeroSlot].hooksThrown == 1

echo "Testing loadBots leaves the human seat VM-free"
block:
  let game = freshGame()
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount - 1)])
  doAssert game.heroVms.len == PudgeCount
  doAssert game.heroVms[HeroSlot] == nil, "the human seat runs no script"
  for i in 1 ..< PudgeCount:
    doAssert game.heroVms[i] != nil, "bot seats still get their VM"

echo "Testing take-over and release swap the seat's driver"
block:
  let game = freshGame()
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount)])
  doAssert game.heroVms[HeroSlot] != nil,
    "a full roster of programs gives the human seat autopilot"
  game.queueHero(IntentWalk, 30, 64)
  doAssert applyTakeOver(game, HeroSlot, false), "release to autopilot"
  doAssert HeroSlot notin game.humanSlots
  doAssert game.humanIntents.len == 0,
    "parked commands from the human stint must not fire later"
  doAssert not applyTakeOver(game, HeroSlot, false),
    "double release is a no-op"
  let decisionsBefore = game.heroVms[HeroSlot].decisions
  game.play(int(TickRate))
  doAssert game.heroVms[HeroSlot].decisions > decisionsBefore,
    "the freed seat runs its script again"
  doAssert applyTakeOver(game, HeroSlot, true), "retake the seat"
  doAssert HeroSlot in game.humanSlots
  doAssert not applyTakeOver(game, HeroSlot, true),
    "double take-over is a no-op"

echo "Testing release without autopilot is denied"
block:
  let game = freshGame()
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount - 1)])
  doAssert not applyTakeOver(game, HeroSlot, false),
    "a VM-free seat cannot be released or the butcher would freeze"
  doAssert HeroSlot in game.humanSlots

echo "Testing two human seats drain their own intents"
block:
  let game = newGame(map, MatchTicks, false, ReplayData())
  game.humanSlots.add 0
  game.humanSlots.add 4
  queueIntent(game, HumanIntent(
    slot: 0'i32, kind: IntentWalk, a: 30'i32, b: 60'i32
  ))
  queueIntent(game, HumanIntent(
    slot: 4'i32, kind: IntentWalk, a: 90'i32, b: 70'i32
  ))
  game.play(1)
  doAssert game.world.pudges[0].hasMoveTarget
  doAssert game.world.pudges[4].hasMoveTarget
  doAssert game.humanIntents.len == 0
  doAssert game.intentResults.len == 2

echo "Testing bot print lines land in the speech feed"
block:
  let game = newGame(map, MatchTicks, false, ReplayData())
  let speakPath = getTempDir() / "pw_speak_test.bas"
  writeFile(speakPath, "print \"grr fresh meat\"\n")
  loadBots(game, [BotGroup(path: speakPath, count: PudgeCount)])
  game.play(1)
  removeFile(speakPath)
  for i in 0 ..< PudgeCount:
    doAssert game.botSpeech[i].text == "grr fresh meat",
      "every scripted seat speaks its printed line"

echo "Testing a mid-match take-over records and replays hash-exact"
block:
  let game = freshGame()
  loadBots(game, [BotGroup(path: basBotPath, count: PudgeCount)])
  game.startRecording(uint32(MatchTicks))

  game.queueHero(IntentWalk, 30, 64)
  game.play(6)
  doAssert applyTakeOver(game, HeroSlot, false)
  game.play(40)
  doAssert applyTakeOver(game, HeroSlot, true)
  game.queueHero(IntentStop)
  game.play(6)
  doAssert game.recordingError.len == 0

  var takeovers = 0
  for action in game.recorder.data.actions:
    if action.kind == ActionTakeOver:
      inc takeovers
  doAssert takeovers == 2, "both handoffs land on the tape"

  let
    liveHash = stateHash(game)
    liveTick = game.world.tick
  game.recorder.data.header.setup.maximumTicks =
    max(uint32(game.world.tick), 1'u32)
  let decoded = decodeReplay(game.recorder.data.encodeReplay())
  let replayGame = newGame(map, MatchTicks, true, decoded)
  replayGame.replayPlayer = initReplayPlayer(decoded)
  replayGame.historyPlayback = true
  while replayGame.world.tick < liveTick:
    tickWorld(replayGame, proc() = discard)
  doAssert replayGame.hashCheck.mismatches == 0,
    "take-overs must replay hash-exact: " & replayGame.hashCheck.error
  doAssert stateHash(replayGame) == liveHash,
    "the replayed world must equal the live world"

echo "Testing scripted human intents produce a hash-exact replay"
block:
  let game = freshGame()
  game.startRecording(uint32(MatchTicks))

  game.queueHero(IntentWalk, 34, 60)
  game.play(8)
  game.queueHero(IntentHookFine, fineOfTile(52), fineOfTile(62))
  game.play(int(HookWindupTicks) + 20)
  game.queueHero(IntentStop)
  game.play(2)
  game.queueHero(IntentPing, 70, 44)
  game.play(2)
  game.queueHero(IntentBlink, 28, 64)
  game.play(2)
  game.queueHero(IntentBuy, int32(UpgradeDistance.ord))
  game.play(2)
  game.queueHero(IntentWalk, 22, 88)
  game.play(46)
  doAssert game.recordingError.len == 0
  doAssert game.recorder.data.actions.len >= 6,
    "every drained intent lands on the tape"

  let
    liveHash = stateHash(game)
    liveTick = game.world.tick
  # Like saveRecording: the tape closes at the tick the match stopped.
  game.recorder.data.header.setup.maximumTicks =
    max(uint32(game.world.tick), 1'u32)
  let
    encoded = game.recorder.data.encodeReplay()
    decoded = decodeReplay(encoded)
  doAssert decoded.header.setup.pudges[HeroSlot].controller ==
    ControllerHuman, "the seat controller tag survives the round trip"
  doAssert decoded.header.setup.pudges[1].controller == ControllerBot

  let replayGame = newGame(map, MatchTicks, true, decoded)
  replayGame.replayPlayer = initReplayPlayer(decoded)
  replayGame.historyPlayback = true
  while replayGame.world.tick < liveTick:
    tickWorld(replayGame, proc() = discard)
  doAssert replayGame.hashCheck.mismatches == 0,
    "human actions must replay hash-exact: " & replayGame.hashCheck.error
  doAssert stateHash(replayGame) == liveHash,
    "the replayed world must equal the live world"
  doAssert replayGame.world.pudges[HeroSlot].hooksThrown ==
    game.world.pudges[HeroSlot].hooksThrown

echo "Testing debug recorder stop writes a loadable bug tape"
block:
  let game = freshGame()
  game.startRecording(uint32(MatchTicks))
  game.queueHero(IntentWalk, 30, 64)
  game.play(12)
  doAssert game.recorder.data.hashes.len == 12
  doAssert game.recorder.data.header.setup.maximumTicks == uint32(MatchTicks)
  let dir = getTempDir() / "polyworld-pw-bug-human"
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  let bugPath = writeBugReplay(
    dir, game.recorder.data, HeroSlot, "Aaron",
    game.world.pudges[HeroSlot].id, 0'i32
  )
  doAssert game.recorder.data.header.setup.maximumTicks == uint32(MatchTicks),
    "stop must not mutate the live match tape duration"
  doAssert fileExists(bugPath)
  let loaded = loadReplay(bugPath)
  doAssert loaded.header.setup.maximumTicks ==
    uint32(game.recorder.data.hashes.len)
  doAssert loaded.actions.len >= 1
  doAssert loaded.header.setup.pudges[HeroSlot].controller == ControllerHuman
  doAssert readFile(dir / BugLatestName).contains("Aaron")
  removeDir(dir)

echo "Testing WC3-style cheat code suffixes"
block:
  doAssert matchCheatBuffer("greedisgood").found
  doAssert matchCheatBuffer("greedisgood").kind == CheatGreed
  doAssert matchCheatBuffer("xxgreedisgood").found
  doAssert not matchCheatBuffer("greedi").found
  doAssert matchCheatBuffer("iseedeadpeople").reveal
  doAssert matchCheatBuffer("whosyourdaddy").kind == CheatGod
  doAssert matchCheatBuffer("thereisnospoon").kind == CheatMana
  doAssert matchCheatBuffer("warpten").kind == CheatMana
  doAssert matchCheatBuffer("keysersoze").kind == CheatGold
  doAssert matchCheatBuffer("leafittome").kind == CheatGoods
  doAssert matchCheatBuffer("allyourbasearebelongtous").kind == CheatWin
  doAssert not matchCheatBuffer("").found

echo "Testing greedisgood grants gold and shop goods through the intent path"
block:
  let game = freshGame()
  game.queueHero(IntentCheat, int32(CheatGreed.ord), CheatGoldAmount)
  game.play(1)
  doAssert game.intentResults.len == 1
  doAssert game.intentResults[0].accepted
  doAssert game.world.pudges[HeroSlot].gold == CheatGoldAmount
  for item in ShopBoots..ShopMine:
    doAssert game.world.pudges[HeroSlot].itemRank[item] == ItemMaxRank,
      $item & " should be maxed as the lumber analog"

echo "Testing fair matches keep the pre-cheat state hash"
block:
  let
    fair = freshGame()
    alsoFair = freshGame()
  fair.play(8)
  alsoFair.play(8)
  doAssert stateHash(fair) == stateHash(alsoFair)
  alsoFair.queueHero(IntentCheat, int32(CheatGold.ord), CheatGoldAmount)
  alsoFair.play(1)
  fair.play(1)
  doAssert stateHash(fair) != stateHash(alsoFair),
    "a gold cheat must change the hashed world"

echo "Testing whosyourdaddy is immune and one-shots"
block:
  let game = freshGame()
  game.world.pudges[HeroSlot].placePudge(30, 64)
  game.world.pudges[3].placePudge(34, 64)
  doAssert applyCheat(
    game.world, game.world.pudges[HeroSlot].id, int32(CheatGod.ord), 0
  )
  doAssert game.world.pudges[HeroSlot].hasCheat(CheatFlagGod)
  killPudgeForTest(game.world, HeroSlot, game.world.pudges[3].id)
  doAssert game.world.pudges[HeroSlot].state == Alive,
    "god mode must refuse the kill path"
  doAssert applyAttackTarget(
    game.world, game.world.pudges[HeroSlot].id, game.world.pudges[3].id
  )
  game.play(int(AttackTicks) + 2)
  doAssert game.world.pudges[3].state == Dying,
    "a god-mode melee hit must one-shot"

echo "Testing cheated gold replays hash-exact"
block:
  let game = freshGame()
  game.startRecording(uint32(MatchTicks))
  game.queueHero(IntentCheat, int32(CheatGreed.ord), CheatGoldAmount)
  game.play(4)
  game.queueHero(IntentCheat, int32(CheatGod.ord), 0)
  game.play(4)
  doAssert game.recordingError.len == 0
  let
    liveHash = stateHash(game)
    liveTick = game.world.tick
  game.recorder.data.header.setup.maximumTicks =
    max(uint32(game.world.tick), 1'u32)
  let decoded = decodeReplay(game.recorder.data.encodeReplay())
  var cheatActions = 0
  for action in decoded.actions:
    if action.kind == ActionCheat:
      inc cheatActions
  doAssert cheatActions == 2
  let replayGame = newGame(map, MatchTicks, true, decoded)
  replayGame.replayPlayer = initReplayPlayer(decoded)
  replayGame.historyPlayback = true
  while replayGame.world.tick < liveTick:
    tickWorld(replayGame, proc() = discard)
  doAssert replayGame.hashCheck.mismatches == 0,
    "cheats must replay hash-exact: " & replayGame.hashCheck.error
  doAssert stateHash(replayGame) == liveHash
  doAssert replayGame.world.pudges[HeroSlot].gold == CheatGoldAmount
  doAssert replayGame.world.pudges[HeroSlot].hasCheat(CheatFlagGod)

echo "Testing allyourbasearebelongtous ends the match"
block:
  let game = freshGame()
  doAssert not game.world.gameOver
  doAssert applyCheat(
    game.world, game.world.pudges[HeroSlot].id, int32(CheatWin.ord), 0
  )
  doAssert game.world.gameOver
  doAssert game.world.winner == game.world.pudges[HeroSlot].team
  doAssert not applyCheat(
    game.world, game.world.pudges[HeroSlot].id, int32(CheatLose.ord), 0
  ), "a second ending cheat is rejected"

echo "test_pw_human: all checks passed"
