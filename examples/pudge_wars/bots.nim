## Pudge Wars scripting: the BASIC surface one butcher has on the match.
##
## Observations are fog-clipped the same way the renderer is, so a script
## cannot track an enemy through the far bank. Human seats live beside
## the scripts: a slot listed in `game.humanSlots` skips its VM (which
## may not exist) and drains the queued human intents through the same
## record-then-apply path at its hero turn. Fairness knobs live here too:
## `game.botEvery` throttles script decisions to a human-like cadence and
## `game.botAimNoise` scatters hook aim deterministically before the
## action is recorded.

import
  bassy,
  std/[os, strutils],
  polyworld/[annotations, cli, llms, policies, tensors, timings, pathing, profiles, rngs, tapes],
  content,
  maps,
  sim,
  teammates,
  replays

type
  PudgeDataSlot = enum
    DataSelfId,
    DataSelfTeam,
    DataSelfX,
    DataSelfY,
    DataSelfHp,
    DataSelfMaxHp,
    DataSelfKills,
    DataSelfPoints,
    DataSelfLayer,
    DataSelfHooked,
    DataSelfShield,
    DataSelfBuff,
    DataSelfRot,
    DataHookReady,
    DataBlinkReady,
    DataWorldTick,
    DataRiverWest,
    DataRiverEast,
    DataHomeX,
    DataHomeY,
    DataAllyPingX,
    DataAllyPingY,
    DataAllyPingAge,
    DataAllyPingBy,
    DataSelfGold,
    DataSelfInShop,
    DataRuneSoon,
    DataRuneNextKind,
    DataRuneNextX,
    DataRuneNextY,
    DataTeamPingResponder

const
  PudgeDataNames: array[PudgeDataSlot, string] = [
    "selfId",
    "selfTeam",
    "selfX",
    "selfY",
    "selfHp",
    "selfMaxHp",
    "selfKills",
    "selfPoints",
    "selfLayer",
    "selfHooked",
    "selfShield",
    "selfBuff",
    "selfRot",
    "hookReady",
    "blinkReady",
    "worldTick",
    "riverWest",
    "riverEast",
    "homeX",
    "homeY",
    "allyPingX",
    "allyPingY",
    "allyPingAge",
    "allyPingBy",
    "selfGold",
    "selfInShop",
    "runeSoon",
    "runeNextKind",
    "runeNextX",
    "runeNextY",
    "teamPingResponder"
  ]

var
  activeGame: Game
  pudgeDataIds: array[PudgeDataSlot, int32]

proc bindPudgeData(program: Program) =
  for slot, name in PudgeDataNames:
    pudgeDataIds[slot] = program.hostDataIndex(name)
    doAssert pudgeDataIds[slot] >= 0, "missing host data " & name

proc pudgeVmLimits*(): Limits =
  result = defaultLimits()
  result.maxSourceBytes = 64 * 1024
  result.maxCodeInstructions = 20_000
  result.maxArrays = 32
  result.maxArrayElements = 4096
  result.maxGlobals = 256
  result.maxHostData = 32
  result.maxHostFunctions = 160
  result.maxRoutines = 64
  result.maxParameters = 16
  result.maxRegisters = 256
  result.maxSyntaxDepth = 32
  result.maxCallDepth = 16
  result.maxMemoryBytes = 2 * 1024 * 1024
  result.maxInstructions = 100_000
  result.maxWorkUnits = 250_000
  result.maxNativeMemoryBytes = 32 * 1024 * 1024
  result.maxStrings = 1024
  result.maxStringBytes = 256 * 1024
  result.maxStringLength = 64 * 1024
  result.maxPrintBytes = 1024
  result.maxPrintEvents = 128

proc initPudgeHost(pudgeId: int32, annotations: AnnotationSink = nil,
                   policy: Policy = nil, llm: LlmClient = nil): Host =
  result = initHost()
  result.addAnnotationFunctions(annotations)
  result.addBufferFunctions()
  result.addTensorFunctions(policy)
  let services = if llm == nil: newLlmClient(0, LlmConfig()) else: llm
  services.addFunctions(result)
  for name in PudgeDataNames:
    discard result.addData(name)

  let objectCountProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    int32(worldObjectCount(activeGame.world, pudgeId))
  let objectIdProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      value.id
    else:
      0
  let objectKindProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      value.kind
    else:
      0
  let objectTeamProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      int32(value.team.ord)
    else:
      0
  let objectXProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      mapCoordinate(value.position.x)
    else:
      0
  let objectYProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      mapCoordinate(value.position.z)
    else:
      0
  let objectHpProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      max(value.hp, 0'i32)
    else:
      0
  let objectAliveProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    int32(
      worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value) and
        value.alive
    )
  let objectLayerProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    if worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value):
      value.layer
    else:
      0
  let objectHookedProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    int32(
      worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value) and
        value.hooked
    )
  let objectShieldedProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    int32(
      worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value) and
        value.shielded
    )
  let objectRotProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var value: WorldObject
    int32(
      worldObjectAt(activeGame.world, pudgeId, int(arguments[0]), value) and
        value.rotting
    )
  let walkToProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordWalkTo(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyWalkTo(activeGame.world, pudgeId, arguments[0], arguments[1]))
  proc castHook(
      arguments: openArray[int32], rescueId = -1'i32
  ): int32 =
    var
      aimX = arguments[0]
      aimY = arguments[1]
    if activeGame.botAimNoise > 0:
      # Seeded scatter derived from (map seed, tick, caster): identical
      # on every run, applied before recording so the tape stays exact.
      var rng = initRng(
        activeGame.map.seed xor activeGame.world.tick,
        uint64(cast[uint32](pudgeId))
      )
      let spread = activeGame.botAimNoise
      aimX = clamp(
        aimX + rng.between(-spread, spread), 0'i32, int32(GridTiles - 1)
      )
      aimY = clamp(
        aimY + rng.between(-spread, spread), 0'i32, int32(GridTiles - 1)
      )
    if rescueId >= 0:
      let index = activeGame.world.pudgeIndex(pudgeId)
      if index < 0 or
          not activeGame.world.canThrowHook(activeGame.world.pudges[index]) or
          not activeGame.world.friendlyHookLaneClear(
            pudgeId, aimX, aimY, rescueId):
        return 0
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordHookTo(
          uint32(activeGame.world.tick),
          pudgeId,
          aimX,
          aimY
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyHookTo(activeGame.world, pudgeId, aimX, aimY))
  let hookToProc: HostProc = proc(arguments: openArray[int32]): int32 =
    castHook(arguments)
  let safeHookToProc: HostProc = proc(arguments: openArray[int32]): int32 =
    castHook(arguments, 0)
  let rescueAllyProc: HostProc = proc(arguments: openArray[int32]): int32 =
    let allyId = arguments[0]
    if not activeGame.world.mayRescueAlly(pudgeId, allyId):
      return 0
    let ally = activeGame.world.pudges[activeGame.world.pudgeIndex(allyId)]
    let at = tileOf(ally.position)
    castHook([int32(at.x), int32(at.z)], allyId)
  let allyNeedsRescueProc: HostProc = proc(arguments: openArray[int32]): int32 =
    let
      caster = activeGame.world.pudgeIndex(pudgeId)
      ally = activeGame.world.pudgeIndex(arguments[0])
    if caster < 0 or ally < 0 or caster == ally or
        activeGame.world.pudges[caster].team != activeGame.world.pudges[ally].team:
      return 0
    int32(activeGame.world.needsRescue(activeGame.world.pudges[ally]))
  let attackTargetProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordAttackTarget(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyAttackTarget(activeGame.world, pudgeId, arguments[0]))
  let hookCountProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    discard arguments
    int32(worldHookCount(activeGame.world, pudgeId))
  let hookTeamProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook):
      int32(hook.team.ord)
    else:
      0
  let hookXProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook):
      mapCoordinate(hook.position.x)
    else:
      0
  let hookYProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook):
      mapCoordinate(hook.position.z)
    else:
      0
  let hookFlyingProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook) and
        hook.phase == HookFlying:
      1'i32
    else:
      0
  let hookVictimProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook):
      hook.victimId
    else:
      0
  let hookOwnerProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var hook: Hook
    if worldHookAt(activeGame.world, pudgeId, int(arguments[0]), hook):
      hook.ownerId
    else:
      0
  let runeCountProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    discard arguments
    int32(worldRuneCount(activeGame.world, pudgeId))
  let runeXProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var rune: Rune
    if worldRuneAt(activeGame.world, pudgeId, int(arguments[0]), rune):
      mapCoordinate(rune.position.x)
    else:
      -1
  let runeYProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var rune: Rune
    if worldRuneAt(activeGame.world, pudgeId, int(arguments[0]), rune):
      mapCoordinate(rune.position.z)
    else:
      -1
  let runeKindProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    var rune: Rune
    if worldRuneAt(activeGame.world, pudgeId, int(arguments[0]), rune):
      int32(rune.kind.ord)
    else:
      -1
  let buyUpgradeProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordBuyUpgrade(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyBuyUpgrade(activeGame.world, pudgeId, arguments[0]))
  let buyPowerProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordBuyPower(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyBuyPower(activeGame.world, pudgeId, arguments[0]))
  let itemRankProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    let
      index = activeGame.world.pudgeIndex(pudgeId)
      kind = arguments[0]
    if index < 0 or kind < 0 or
        kind > int32(ShopWard.ord - ShopBoots.ord):
      return 0
    activeGame.world.pudges[index].itemRank[
      ShopItem(int32(ShopBoots.ord) + kind)
    ]
  let upgradeLevelProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    let
      index = activeGame.world.pudgeIndex(pudgeId)
      kind = arguments[0]
    if index < 0 or kind < 0 or kind > UpgradeKind.high.ord:
      return 0
    activeGame.world.pudges[index].upgrades[UpgradeKind(kind)]
  let stopProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    discard arguments
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordStop(uint32(activeGame.world.tick), pudgeId)
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyStop(activeGame.world, pudgeId))
  let pingProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordPing(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyPing(activeGame.world, pudgeId, arguments[0], arguments[1]))
  let blinkToProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordBlinkTo(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyBlinkTo(activeGame.world, pudgeId, arguments[0], arguments[1]))
  let rotToggleProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    discard arguments
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordRotToggle(
          uint32(activeGame.world.tick), pudgeId
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyRotToggle(activeGame.world, pudgeId))
  let placeWallProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordPlaceWall(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyPlaceWall(activeGame.world, pudgeId, arguments[0], arguments[1]))
  let placeMineProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordPlaceMine(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyPlaceMine(activeGame.world, pudgeId, arguments[0], arguments[1]))
  let placeWardProc: HostProc = proc(
      arguments: openArray[int32]
  ): int32 =
    try:
      if activeGame.recorder != nil:
        activeGame.recorder.recordPlaceWard(
          uint32(activeGame.world.tick),
          pudgeId,
          arguments[0],
          arguments[1]
        )
    except ReplayError as error:
      activeGame.recordingError = error.msg
      raise newException(BasicError, "replay recording failed: " & error.msg)
    int32(applyPlaceWard(activeGame.world, pudgeId, arguments[0], arguments[1]))

  discard result.addFunction("objectCount", 0, objectCountProc, 2)
  discard result.addFunction("objectId", 1, objectIdProc, 4)
  discard result.addFunction("objectKind", 1, objectKindProc, 4)
  discard result.addFunction("objectTeam", 1, objectTeamProc, 4)
  discard result.addFunction("objectX", 1, objectXProc, 4)
  discard result.addFunction("objectY", 1, objectYProc, 4)
  discard result.addFunction("objectHp", 1, objectHpProc, 4)
  discard result.addFunction("objectAlive", 1, objectAliveProc, 4)
  discard result.addFunction("objectLayer", 1, objectLayerProc, 4)
  discard result.addFunction("objectHooked", 1, objectHookedProc, 4)
  discard result.addFunction("objectShielded", 1, objectShieldedProc, 4)
  discard result.addFunction("objectRot", 1, objectRotProc, 4)
  discard result.addFunction("hookCount", 0, hookCountProc, 2)
  discard result.addFunction("hookTeam", 1, hookTeamProc, 4)
  discard result.addFunction("hookX", 1, hookXProc, 4)
  discard result.addFunction("hookY", 1, hookYProc, 4)
  discard result.addFunction("hookFlying", 1, hookFlyingProc, 4)
  discard result.addFunction("hookVictim", 1, hookVictimProc, 4)
  discard result.addFunction("hookOwner", 1, hookOwnerProc, 4)
  discard result.addFunction("runeCount", 0, runeCountProc, 2)
  discard result.addFunction("runeX", 1, runeXProc, 4)
  discard result.addFunction("runeY", 1, runeYProc, 4)
  discard result.addFunction("runeKind", 1, runeKindProc, 4)
  discard result.addFunction("walkTo", 2, walkToProc, 400)
  discard result.addFunction("hookTo", 2, hookToProc, 400)
  discard result.addFunction("safeHookTo", 2, safeHookToProc, 400)
  discard result.addFunction("rescueAlly", 1, rescueAllyProc, 400)
  discard result.addFunction("allyNeedsRescue", 1, allyNeedsRescueProc, 20)
  discard result.addFunction("attackTarget", 1, attackTargetProc, 20)
  discard result.addFunction("buyUpgrade", 1, buyUpgradeProc, 20)
  discard result.addFunction("buyPower", 1, buyPowerProc, 20)
  discard result.addFunction("itemRank", 1, itemRankProc, 4)
  discard result.addFunction("upgradeLevel", 1, upgradeLevelProc, 4)
  discard result.addFunction("halt", 0, stopProc, 20)
  discard result.addFunction("ping", 2, pingProc, 20)
  discard result.addFunction("blinkTo", 2, blinkToProc, 400)
  discard result.addFunction("rotToggle", 0, rotToggleProc, 20)
  discard result.addFunction("placeWall", 2, placeWallProc, 20)
  discard result.addFunction("placeMine", 2, placeMineProc, 20)
  discard result.addFunction("placeWard", 2, placeWardProc, 20)

proc botScriptLabel(path: string): string =
  ## "players/aggressive.bas" becomes "Aggressive".
  result = path.splitFile.name
  if result.len == 0:
    return "Bot"
  result[0] = result[0].toUpperAscii()

proc uniquifySeatLabels(labels: var seq[string]) =
  ## "Base","Base","Support" becomes "Base 1","Base 2","Support".
  var numbered = newSeq[string](labels.len)
  for i, name in labels:
    if name.len == 0:
      continue
    var copies = 0
    for other in labels:
      if other == name:
        inc copies
    if copies <= 1:
      numbered[i] = name
      continue
    var k = 0
    for j in 0 .. i:
      if labels[j] == name:
        inc k
    numbered[i] = name & " " & $k
  labels = numbered

proc applySeatLabels*(game: Game, names: openArray[string]) =
  ## Nameplates and kill feed: one display name per roster seat.
  ## Coworld hosted dispatch writes these into `players[].name`.
  if game == nil:
    return
  let total = game.world.pudges.len
  game.seatLabels = newSeq[string](total)
  for i in 0 ..< min(total, names.len):
    game.seatLabels[i] = names[i]
  uniquifySeatLabels(game.seatLabels)

proc loadBots*(game: Game, groups: openArray[BotGroup]) =
  ## Compiles bot programs into seats. With one program per seat, human
  ## seats get a VM too, so releasing control falls back to script
  ## autopilot. With one program per non-human seat, human seats stay
  ## VM-free and cost nothing.
  activeGame = game
  let limits = pudgeVmLimits()
  var schema = initPudgeHost(0)
  var
    programs: seq[Program]
    programPaths: seq[string]
    policies: seq[Policy]
  for group in groups:
    let policy = readPolicy(group.path)
    let program = compile(policy.source, schema, limits)
    for _ in 0 ..< group.count:
      programs.add program
      programPaths.add group.path
      policies.add policy
  let
    total = game.world.pudges.len
    humans = game.humanSlots.len
  doAssert programs.len == total or programs.len == total - humans,
    "bot programs must fill every seat or every non-human seat"
  game.heroVms.setLen(total)
  game.seatLabels = newSeq[string](total)
  if programs.len == 0:
    return
  bindPudgeData(programs[0])
  var next = 0
  for i in 0 ..< total:
    if programs.len < total and i in game.humanSlots:
      game.heroVms[i] = nil
      continue
    let llm = newLlmClient(i)
    var host = initPudgeHost(game.world.pudges[i].id, policy = policies[next], llm = llm)
    game.heroVms[i] = HeroVm(
      runtime: initRuntime(programs[next], host, limits),
      limits: limits,
      prepareDecision: llm.decisionCallback(),
      pollRequests: llm.requestPoller(),
      closeServices: proc() = llm.close(),
      ready: true
    )
    llm.bindRuntime(game.heroVms[i].runtime)
    if i notin game.humanSlots:
      game.seatLabels[i] = botScriptLabel(programPaths[next])
    inc next
  uniquifySeatLabels(game.seatLabels)

proc loadBotSource*(game: Game, slot: int, source: string,
                    output: PrintProc, annotations: AnnotationSink) =
  ## Each staged source compiles and executes in its own bounded VM.
  activeGame = game
  let limits = pudgeVmLimits()
  let policy = loadPolicy(source)
  let llm = newLlmClient(slot)
  let host = initPudgeHost(game.world.pudges[slot].id, annotations, policy, llm)
  let program = compile(policy.source, host, limits)
  bindPudgeData(program)
  game.heroVms.setLen(game.world.pudges.len)
  game.heroVms[slot] = HeroVm(runtime: initRuntime(program, host, limits),
    limits: limits, ready: true, output: output,
    prepareDecision: llm.decisionCallback(), pollRequests: llm.requestPoller(),
    closeServices: proc() = llm.close())
  llm.bindRuntime(game.heroVms[slot].runtime)

proc runPudgeScript(game: Game, index: int) {.measure.} =
  if index < 0 or index >= game.heroVms.len:
    return
  let
    pudge = game.world.pudges[index]
    vm = game.heroVms[index]
  if vm == nil or vm.failed or pudge.state == Dying:
    return
  vm.runtime.restart()
  # BASIC `print` is captured on the seat for logs and tests. The
  # world shows a nameplate, not the printed line.
  var spokenLine = ""
  let speak: PrintProc = proc(event: PrintEvent) =
    if vm.output != nil:
      vm.output(event)
      return
    case event.kind
    of TextPrint:
      spokenLine.add event.text
    of ValuePrint:
      spokenLine.add $event.value
    of FixedPrint:
      spokenLine.add $event.fixedValue
    of NewlinePrint:
      if spokenLine.len > 0 and index < game.botSpeech.len:
        game.botSpeech[index] = BotSpeech(
          text: spokenLine, tick: game.world.tick
        )
      spokenLine.setLen(0)
  try:
    if vm.prepareDecision != nil:
      vm.prepareDecision(game.world.tick)
    vm.runtime.setData(pudgeDataIds[DataSelfId], pudge.id)
    vm.runtime.setData(pudgeDataIds[DataSelfTeam], int32(pudge.team.ord))
    vm.runtime.setData(pudgeDataIds[DataSelfX], mapCoordinate(pudge.position.x))
    vm.runtime.setData(pudgeDataIds[DataSelfY], mapCoordinate(pudge.position.z))
    vm.runtime.setData(pudgeDataIds[DataSelfHp], max(pudge.hp, 0'i32))
    vm.runtime.setData(pudgeDataIds[DataSelfMaxHp], pudge.maxHp)
    vm.runtime.setData(pudgeDataIds[DataSelfKills], pudge.kills)
    vm.runtime.setData(pudgeDataIds[DataSelfPoints], pudge.points)
    vm.runtime.setData(pudgeDataIds[DataSelfGold], pudge.gold)
    vm.runtime.setData(
      pudgeDataIds[DataSelfInShop],
      if pudge.inOwnShop: 1'i32 else: 0'i32
    )
    vm.runtime.setData(pudgeDataIds[DataSelfLayer], pudge.layer)
    vm.runtime.setData(
      pudgeDataIds[DataSelfHooked],
      if pudge.hookedBy != 0: 1'i32 else: 0'i32
    )
    vm.runtime.setData(pudgeDataIds[DataSelfShield], max(pudge.shieldTicks, 0'i32))
    vm.runtime.setData(
      pudgeDataIds[DataSelfBuff],
      if pudge.buffTicks > 0: int32(pudge.buffKind.ord) + 1 else: 0'i32
    )
    vm.runtime.setData(
      pudgeDataIds[DataSelfRot],
      if pudge.rotOn: 1'i32 else: 0'i32
    )
    vm.runtime.setData(
      pudgeDataIds[DataHookReady],
      int32(game.world.canThrowHook(pudge))
    )
    vm.runtime.setData(
      pudgeDataIds[DataBlinkReady],
      if pudge.blinkCooldown <= 0 and pudge.windupTicks <= 0 and
          pudge.hookedBy == 0 and
          not activeGame.world.rotAffected(pudge): 1'i32 else: 0'i32
    )
    vm.runtime.setData(pudgeDataIds[DataWorldTick], game.world.tick)
    vm.runtime.setData(pudgeDataIds[DataRiverWest], int32(PlayWestMax))
    vm.runtime.setData(pudgeDataIds[DataRiverEast], int32(PlayEastMin))
    let home = pudge.spawnTile
    vm.runtime.setData(pudgeDataIds[DataHomeX], int32(home.x))
    vm.runtime.setData(pudgeDataIds[DataHomeY], int32(home.z))
    var ping: Ping
    if latestTeamPing(game.world, pudge.team, ping):
      vm.runtime.setData(pudgeDataIds[DataAllyPingX], ping.x)
      vm.runtime.setData(pudgeDataIds[DataAllyPingY], ping.y)
      vm.runtime.setData(
        pudgeDataIds[DataAllyPingAge],
        max(game.world.tick - ping.tick, 0'i32)
      )
      vm.runtime.setData(pudgeDataIds[DataAllyPingBy], ping.byId)
    else:
      vm.runtime.setData(pudgeDataIds[DataAllyPingX], -1'i32)
      vm.runtime.setData(pudgeDataIds[DataAllyPingY], -1'i32)
      vm.runtime.setData(pudgeDataIds[DataAllyPingAge], -1'i32)
      vm.runtime.setData(pudgeDataIds[DataAllyPingBy], 0'i32)
    vm.runtime.setData(
      pudgeDataIds[DataTeamPingResponder], game.teamPingResponder(pudge.team)
    )
    let soon = runeSoonTicks(game.world)
    vm.runtime.setData(pudgeDataIds[DataRuneSoon], soon)
    if soon <= 0:
      vm.runtime.setData(pudgeDataIds[DataRuneNextKind], -1'i32)
      vm.runtime.setData(pudgeDataIds[DataRuneNextX], -1'i32)
      vm.runtime.setData(pudgeDataIds[DataRuneNextY], -1'i32)
    else:
      vm.runtime.setData(
        pudgeDataIds[DataRuneNextKind], int32(game.world.nextRuneKind.ord)
      )
      vm.runtime.setData(pudgeDataIds[DataRuneNextX], int32(RiverCenterX))
      vm.runtime.setData(pudgeDataIds[DataRuneNextY], game.world.nextRuneZTile)
    discard vm.runtime.run(speak)
    inc vm.decisions
    if spokenLine.len > 0 and index < game.botSpeech.len:
      # A trailing `print ... ;` without a newline still surfaces.
      game.botSpeech[index] = BotSpeech(
        text: spokenLine, tick: game.world.tick
      )
  except BasicError as error:
    vm.failed = true
    vm.lastError = error.msg
    if vm.output == nil:
      echo "pudge ", pudge.id, " BASIC error: ", error.msg
  vm.lastWork = vm.runtime.workUsed
  vm.lastInstructions = vm.runtime.instructionsUsed

proc isHumanSlot*(game: Game, index: int): bool =
  ## Returns whether a human currently drives this roster slot.
  index in game.humanSlots

proc runBotDecisions*(game: Game) {.measure.} =
  ## Runs every seat's decision source in rotation order: human seats
  ## drain their intent queue, bot seats run their script on the
  ## configured cadence (staggered by slot so bots do not act in bursts).
  activeGame = game
  if game.world.pudges.len == 0:
    return
  for offset in 0 ..< game.world.pudges.len:
    let index = (game.world.heroTurnStart + offset) mod game.world.pudges.len
    if game.isHumanSlot(index):
      runHumanIntents(game, index)
    elif game.botEvery <= 1 or
        (int(game.world.tick) + index) mod int(game.botEvery) == 0:
      runPudgeScript(game, index)
  game.world.heroTurnStart =
    (game.world.heroTurnStart + 1) mod game.world.pudges.len

proc waitForBotRequests*(game: Game) =
  ## Poll all seats together without rerunning a decision or advancing the world.
  var pollers: seq[RequestPoll]
  for vm in game.heroVms:
    if vm != nil:
      pollers.add vm.pollRequests
  waitForRequests(pollers)

proc closeBotServices*(game: Game) =
  for vm in game.heroVms:
    if vm != nil and vm.closeServices != nil:
      vm.closeServices()
