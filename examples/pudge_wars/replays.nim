## Pudge Wars action-only replay format and playback cursor.
##
## Format v2 adds the human seat: stop, ping, and take-over actions, a
## fine-grained (1/256-tile) hook aim, per-slot controller tags, and the
## recorded match knobs (kill goal, bot decision cadence, bot aim noise).
## Format v3 records the river rune spawn period; rune motion and pickups
## are fully deterministic, so no new actions are needed.

import
  std/[os, times],
  polyworld/tapes,
  content

when defined(posix):
  from posix import fsync

const
  ReplayGame* = "pudge_wars"
  ReplayFormatVersion* = 4'u16
  ReplayGameVersion* = 25'u16
    ## Physics the *viewer* runs. Observatory's static wasm must ship at
    ## this same number as the recording image (`pwcoworld`). Older tapes
    ## still load; playback skips hash checks so a rebuilt wasm does not
    ## freeze Featured Match. Bump when physics change, and bump the
    ## coworld version in lockstep. Live follow uses `NetProtocolVersion`
    ## in netproto.nim — that is not the observatory replay path.
    ## v25: seeded spawn jitter (lane shuffle + inland X/Z, mirrored
    ##      banks). `ReplayPudge.spawnX`/`spawnZ` record the pads.
    ##      Format v4 carries those fields.
    ## v24: Rot slow is 40% (was 30%) for everyone in the disk.
    ## v23: dying to your own Rot is a suicide: opposing `teamKills`
    ##      still increment (scoreboard / kill goal), but no gold,
    ##      personal KO, or PTS is paid.
    ## v22: Dota-style kill streaks. `streak` (kills this life) hashes
    ##      only when any butcher is on a spree, matching cheatFlags.
    ##      Enemy kills pay GoldPerKill plus scaled own-streak and
    ##      shutdown gold, plus First Blood on the match's first kill.
    ## v21: Rot toggle. A living butcher can blight a `RotRadius` disk:
    ##      pulse damage (including self) and a move-speed cut, and
    ##      anyone standing in it cannot blink. `rotOn`/`rotTicks` hash.
    ## v20: A/W dest on the walkable west/north lip still halt (no orbit),
    ##      but must not cancel a live D/RMB dest inland of the lip.
    ##      Tape bug_20260901_162503: dest 45 then dest 14 on tile 14
    ##      coasted east vel to 0 in one tick.
    ## v19: dest on the west/north playable lip no longer boosts inland.
    ##      Only a true overlap (tile west of PlayWestMin / north of
    ##      PlayZMin) still aims inland; A/W into the wall halt or
    ##      slide along it instead of orbiting 14↔16.
    ## v18: river is a walkable `RiverLayer`. Walk/slide cannot cross the
    ##      waterline; `settlePudge` after a walk does not promote onto
    ##      a bank. Blink may land in water and leave it. Drown is
    ##      periodic HP, not a forced walk to `homeBankX`.
    ## v17: a successful blink while a Meat Hook (or grapple) is already
    ##      out adds the actual hop distance to that chain's `range`
    ##      (remaining outbound = range − traveled). Head position and
    ##      heading stay put. Windup still blocks blink; a hooked
    ##      victim still cannot hop. `hook.range` enters the state hash.
    ## v16: rim overlap soft-nudges every tick without dropping the
    ##      walk order; D at the west cliff aims inland of PlayWestMin;
    ##      west/east spawns sit a quarter-tile inland of the pad center.
    ## v15: Big Hook rune/shop also adds +50% hook damage
    ##      (`RuneBigHookDamagePercent`). A landed Big Hook hit used to
    ##      deal unbuffed damage, so victim HP hashes differ.
    ## v14: blink may land on the opposite bank (river water is
    ##      transparent, never a landing) and always truncates to the
    ##      last legal tile along the aim ray instead of rejecting a
    ##      cliff / palisade / occupied click.
    ## v13: blink clamp 24 → 48 tiles. `blinkLanding` uses live
    ##      `BlinkRange`, so a max-range hop on a v12 tape would land
    ##      farther and hash-differ.
    ## v12: blink range 8 → 24 tiles. `blinkLanding` clamps with the
    ##      live `BlinkRange` / `BlinkRangeTiles`, so a max-range hop
    ##      on a v11 tape would land farther and hash-differ.
    ## v11: shop permanents are treads / longflight brand / palisade /
    ##      hooktrap; place-wall and place-mine are recorded actions.
    ## v10: F-blink dodge teleport (range, cooldown, replay actions).
    ## v9: gold-shop permanents occupy hashed inventory ranks (treads,
    ##     claws, circlet, regen band, long chain, wind wraps).
    ## v8: butchers overlapping a rim strip depenetrate inland without
    ##     dropping the walk order — D along the north/west cliff used
    ##     to no-op until a W/S jiggle.
    ## v7: victim dump points clamp to the map — mutual reels used to
    ##     leapfrog both butchers off the board until the sim crashed.
    ## v6: default walk 25% faster (`MovePerTick` 21_600 → 27_000).
    ## v5: rim-hook recovery backs toward the field instead of walking
    ##     a grazing heading off the map; off-grid butchers eject.
    ## v2: momentum-based walking (persistent velocity, accel/brake).
    ## v1 tapes replay under different physics and would hash-mismatch.
  ReplayGridTiles* = 128'u16
  ActionWalkTo* = 1'u8
  ActionHookTo* = 2'u8
  ActionAttackTarget* = 3'u8
  ActionBuyUpgrade* = 4'u8
  ActionStop* = 5'u8
    ## Halt in place: clears the move order and the attack target.
  ActionPing* = 6'u8
    ## Team-scoped map ping at one tile. Never changes combat state.
  ActionTakeOver* = 7'u8
    ## Provenance marker: `first` is the controller that now drives the
    ## slot (`ControllerBot`/`ControllerHuman`). A no-op on playback.
  ActionHookToFine* = 8'u8
  ActionGrappleTo* = 9'u8
    ## E-grapple cast aimed at a tile center: latches solids and yanks
    ## the caster to them. Never damages.
  ActionGrappleToFine* = 10'u8
    ## Grapple cast aimed at 1/256-tile precision.
  ActionBuyPower* = 11'u8
    ## Base-shop powerup purchase. `first` is the ShopItem ordinal.
  ActionBlinkTo* = 12'u8
    ## Instant dodge teleport aimed at a tile center.
  ActionBlinkToFine* = 13'u8
    ## Blink aimed at 1/256-tile precision.
  ActionPlaceWall* = 14'u8
    ## Drop a palisade on a nearby own-bank tile. `first`/`second` are
    ## map tiles.
  ActionPlaceMine* = 15'u8
    ## Drop a hidden mine on a nearby own-bank tile.
  ActionCheat* = 16'u8
    ## Warcraft 3-style cheat. `first` is CheatKind, `second` is an
    ## optional gold amount (0 uses the default purse).
  ActionRotToggle* = 17'u8
    ## Flip Rot on or off. No aim, no cooldown, no mana.
  FineAimScale* = 256'i32
    ## Fine-aim units per tile for `ActionHookToFine`.
  ControllerBot* = 0'u8
  ControllerHuman* = 1'u8
  MaxReplayBytes* = 64 * 1024 * 1024
  MaxReplayActions* = 10_000_000
  MaxReplayHashes* = 100_000_000
  MaxReplayPudges* = 32
  BugTapeDir* = "duels"
    ## Cwd-relative folder for named mid-match bug tapes (repo-root
    ## `duels/` when launched via host_party.sh / duel.sh).
  BugLatestName* = "bug_latest.txt"
    ## Pointer file agents should read first: path, seat, name, ticks.

type
  ReplayPudge* = object
    id*: int32
    team*: uint8
    slot*: uint8
    controller*: uint8
      ## Who drove this slot when the match started
      ## (`ControllerBot` or `ControllerHuman`).
    lobbySeat*: uint8
      ## Stable lobby seat (0-5); rosters with disabled seats compact
      ## around it.
    spawnX*: int32
    spawnZ*: int32
      ## Home pad tile. 0/0 means "roll from the map seed". Tapes store
      ## the live tiles so a later jitter change still replays.

  Setup* = object
    mapSeed*: int32
    mapHash*: uint64
    tickRate*: uint16
    gridTiles*: uint16
    maximumTicks*: uint32
    killGoal*: int32
      ## First team to this many kills wins.
    botEvery*: int32
      ## Bot decision cadence in ticks (1 = every tick).
    botAimNoise*: int32
      ## Bot hook aim scatter in tiles (0 = perfect aim), applied before
      ## actions are recorded so tapes stay exact.
    runePeriod*: int32
      ## Ticks between river rune spawns; 0 disables runes.
    pudges*: seq[ReplayPudge]

  ReplayAction* = object
    tick*: uint32
    pudgeId*: int32
    kind*: uint8
    first*: int32
    second*: int32

  ReplayHeader* = TapeHeader[Setup]
  ReplayData* = ActionTape[Setup, ReplayAction]
  ReplayRecorder* = TapeRecorder[Setup, ReplayAction]
  ReplayPlayer* = TapePlayer[Setup, ReplayAction]

proc fail(message: string) {.noreturn.} =
  ## Raises one Pudge Wars replay error.
  raise newException(ReplayError, message)

proc validKind(kind: uint8): bool =
  kind >= ActionWalkTo and kind <= ActionRotToggle

proc initReplayData*(setup: Setup): ReplayData =
  ## Creates an empty replay with a versioned deterministic setup.
  initActionTape[Setup, ReplayAction](
    setup,
    ReplayFormatVersion,
    ReplayGameVersion
  )

proc initReplayRecorder*(setup: Setup): ReplayRecorder =
  ## Creates an in-memory Pudge Wars action recorder.
  initTapeRecorder[Setup, ReplayAction](
    setup,
    ReplayFormatVersion,
    ReplayGameVersion
  )

proc record*(recorder: ReplayRecorder, action: ReplayAction) =
  ## Appends one bot action in deterministic tick order.
  if recorder == nil:
    return
  if not validKind(action.kind):
    fail("replay action kind is invalid")
  recorder.data.actions.appendAction(action, MaxReplayActions)

proc recordWalkTo*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one walkTo action.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionWalkTo,
    first: x,
    second: y
  )

proc recordHookTo*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one hookTo action.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionHookTo,
    first: x,
    second: y
  )

proc recordAttackTarget*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    targetId: int32
) =
  ## Records one attackTarget action.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionAttackTarget,
    first: targetId
  )

proc recordBuyUpgrade*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    upgrade: int32
) =
  ## Records one buyUpgrade action.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionBuyUpgrade,
    first: upgrade
  )

proc recordStop*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId: int32
) =
  ## Records one stop action.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionStop
  )

proc recordPing*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one team map ping.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionPing,
    first: x,
    second: y
  )

proc recordTakeOver*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId: int32,
    controller: uint8
) =
  ## Records who controls a slot from this tick on. Playback ignores it.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionTakeOver,
    first: int32(controller)
  )

proc recordHookToFine*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    fineX,
    fineY: int32
) =
  ## Records one hook cast aimed in 1/256-tile units.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionHookToFine,
    first: fineX,
    second: fineY
  )

proc recordGrappleTo*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one tile-grain grapple cast.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionGrappleTo,
    first: x,
    second: y
  )

proc recordGrappleToFine*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    fineX,
    fineY: int32
) =
  ## Records one fine-aim grapple cast.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionGrappleToFine,
    first: fineX,
    second: fineY
  )

proc recordBuyPower*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    item: int32
) =
  ## Records one base-shop powerup purchase.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionBuyPower,
    first: item
  )

proc recordBlinkTo*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one tile-grain blink.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionBlinkTo,
    first: x,
    second: y
  )

proc recordBlinkToFine*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    fineX,
    fineY: int32
) =
  ## Records one fine-aim blink.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionBlinkToFine,
    first: fineX,
    second: fineY
  )

proc recordPlaceWall*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one palisade drop.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionPlaceWall,
    first: x,
    second: y
  )

proc recordPlaceMine*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    x,
    y: int32
) =
  ## Records one hidden-mine drop.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionPlaceMine,
    first: x,
    second: y
  )

proc recordCheat*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId,
    kind,
    amount: int32
) =
  ## Records one typed cheat. `kind` is a `CheatKind` ordinal.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionCheat,
    first: kind,
    second: amount
  )

proc recordRotToggle*(
    recorder: ReplayRecorder,
    tick: uint32,
    pudgeId: int32
) =
  ## Records one Rot enable/disable.
  recorder.record ReplayAction(
    tick: tick,
    pudgeId: pudgeId,
    kind: ActionRotToggle
  )

proc recordHash*(recorder: ReplayRecorder, hash: uint64) =
  ## Appends the canonical simulation hash for one completed tick.
  recordHash(recorder, hash, MaxReplayHashes)

proc validate*(data: ReplayData) =
  ## Validates format, setup bounds, actor IDs, and action ordering.
  ##
  ## Game version is the physics that *hashed* the tape, not a load
  ## gate. Observatory wasm is often rebuilt ahead of the league image;
  ## rejecting older tapes froze Featured Match on the boot overlay.
  if data.header.formatVersion != ReplayFormatVersion:
    fail("unsupported replay format version")
  let setup = data.header.setup
  if setup.tickRate != uint16(TickRate):
    fail("replay setup has an unsupported tick rate")
  if setup.gridTiles != ReplayGridTiles:
    fail("replay setup has an unsupported map size")
  if setup.mapHash == 0:
    fail("replay setup has no deterministic map fingerprint")
  if setup.maximumTicks == 0:
    fail("replay setup has an invalid duration")
  if setup.maximumTicks > uint32(MaxReplayHashes):
    fail("replay setup duration exceeds the hash limit")
  if setup.killGoal <= 0:
    fail("replay setup has an invalid kill goal")
  if setup.botEvery <= 0:
    fail("replay setup has an invalid bot decision cadence")
  if setup.botAimNoise < 0:
    fail("replay setup has an invalid bot aim noise")
  if setup.runePeriod < 0:
    fail("replay setup has an invalid rune period")
  if setup.pudges.len < DuelPudgeCount or setup.pudges.len > PudgeCount:
    fail("replay setup must list a full 3v3 or 1v1 duel roster")
  if data.actions.len > MaxReplayActions:
    fail("replay action limit exceeded")
  if data.hashes.len > MaxReplayHashes:
    fail("replay hash limit exceeded")
  if data.hashes.len != int(setup.maximumTicks):
    fail("replay must contain exactly one hash per simulation tick")
  for i, pudge in setup.pudges:
    if pudge.team > 1 or pudge.slot >= uint8(TeamSize):
      fail("replay setup has invalid pudge metadata")
    if pudge.controller > ControllerHuman:
      fail("replay setup has an unknown slot controller")
    if pudge.spawnX != 0 or pudge.spawnZ != 0:
      if pudge.spawnX < 0 or pudge.spawnZ < 0 or
          pudge.spawnX >= int32(ReplayGridTiles) or
          pudge.spawnZ >= int32(ReplayGridTiles):
        fail("replay setup has a spawn off the map")
    for j in 0 ..< i:
      if setup.pudges[j].id == pudge.id:
        fail("replay setup contains a duplicate pudge ID")
  var lastTick = 0'u32
  for i, action in data.actions:
    if i > 0 and action.tick < lastTick:
      fail("replay actions move backward in time")
    if setup.maximumTicks > 0 and action.tick > setup.maximumTicks:
      fail("replay action exceeds the configured duration")
    if not validKind(action.kind):
      fail("replay action kind is invalid")
    var known = false
    for pudge in setup.pudges:
      if pudge.id == action.pudgeId:
        known = true
        break
    if not known:
      fail("replay action references an unknown pudge")
    lastTick = action.tick

proc encodeReplay*(data: ReplayData): string =
  ## Encodes a validated Pudge Wars replay.
  data.validate()
  if data.header.gameVersion != ReplayGameVersion:
    fail("cannot encode a tape from another game version")
  encodeReplayFile(
    ReplayGame,
    ReplayGameVersion,
    data,
    MaxReplayBytes
  )

proc decodeReplay*(bytes: string): ReplayData =
  ## Decodes and validates one Pudge Wars replay buffer.
  result = decodeReplayFile(
    ReplayGame,
    ReplayGameVersion,
    bytes,
    ReplayData,
    MaxReplayBytes
  )
  result.validate()

proc saveReplay*(path: string, data: ReplayData) =
  ## Writes one complete Pudge Wars replay file.
  writeFile(path, data.encodeReplay())

proc writeFileSynced(path, contents: string) =
  ## Writes `contents` and fsyncs so a mid-match Stop is durable.
  let f = open(path, fmWrite)
  try:
    f.write(contents)
    f.flushFile()
    when defined(posix):
      if fsync(f.getFileHandle()) != 0:
        fail("bug tape fsync failed")
  finally:
    f.close()

proc saveReplaySynced*(path: string, data: ReplayData) =
  ## Writes one validated tape and fsyncs the file.
  writeFileSynced(path, data.encodeReplay())

proc closedReplay*(data: ReplayData): ReplayData =
  ## Copy of a live tape closed at the last recorded hash so `validate`
  ## accepts a mid-match flush. Does not mutate the live recorder.
  result = data
  let ticks = max(uint32(result.hashes.len), 1'u32)
  result.header.setup.maximumTicks = ticks
  if result.actions.len == 0:
    return
  var last = 0
  for i, action in result.actions:
    if action.tick > ticks:
      break
    last = i + 1
  if last < result.actions.len:
    result.actions.setLen(last)

proc nextBugTapePath*(dir = BugTapeDir): string =
  ## `dir/bug_YYYYMMDD_HHMMSS.pwr`, with a numeric suffix on collision.
  createDir(dir)
  let stamp = now().format("yyyyMMdd'_'HHmmss")
  result = dir / ("bug_" & stamp & ".pwr")
  var counter = 1
  while fileExists(result):
    inc counter
    result = dir / ("bug_" & stamp & "_" & $counter & ".pwr")

proc writeBugReplay*(
    dir: string,
    data: ReplayData,
    seat: int,
    name: string,
    pudgeId: int32,
    fromTick: int32,
    eventsSrc = ""
): string =
  ## Flushes a closed copy of `data` to `dir/bug_*.pwr` plus
  ## `dir/bug_latest.txt`. Returns the absolute `.pwr` path.
  ## Does not change the live recorder or sim hashes.
  if data.hashes.len == 0:
    fail("bug tape has no recorded ticks yet")
  let
    tape = closedReplay(data)
    path = nextBugTapePath(dir)
  result = absolutePath(path)
  saveReplaySynced(path, tape)
  var eventsPath = ""
  if eventsSrc.len > 0 and fileExists(eventsSrc):
    eventsPath = absolutePath(path.changeFileExt("events.jsonl"))
    copyFile(eventsSrc, eventsPath)
  var pointer = ""
  pointer.add "path: " & result & "\n"
  pointer.add "fromTick: " & $fromTick & "\n"
  pointer.add "toTick: " & $tape.header.setup.maximumTicks & "\n"
  pointer.add "seat: " & $seat & "\n"
  pointer.add "name: " & name & "\n"
  pointer.add "pudgeId: " & $pudgeId & "\n"
  if eventsPath.len > 0:
    pointer.add "events: " & eventsPath & "\n"
  writeFileSynced(dir / BugLatestName, pointer)

proc loadReplay*(path: string): ReplayData =
  ## Loads one complete Pudge Wars replay file.
  ##
  ## File-header `gameVersion` may differ from this build; the inner
  ## tape version still drives hash skipping on playback.
  result = loadReplayFile(
    path,
    ReplayGame,
    ReplayGameVersion,
    ReplayData,
    MaxReplayBytes,
    requireGameVersion = false
  )
  result.validate()

proc initReplayPlayer*(data: ReplayData): ReplayPlayer =
  ## Creates a playback cursor over validated action data.
  data.validate()
  initTapePlayer(data)
