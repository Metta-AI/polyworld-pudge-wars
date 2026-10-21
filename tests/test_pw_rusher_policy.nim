## Behavioral checks for the BASIC projection of retained Python v16/E06b.
import std/[os, unittest], bassy, polyworld/cli,
  ../examples/pudge_wars/[bots, content, maps, replays, sim]

let policy = currentSourcePath().parentDir.parentDir /
  "examples/pudge_wars/players/rusher.bas"

proc fixture(): Game =
  result = newGame(generateMap(2026), TickRate * 120, false, ReplayData())
  loadBots(result, [BotGroup(path: policy, count: PudgeCount)])
  result.humanSlots = @[1, 2, 3, 4, 5]
  result.world.tick = 200
  for i, at in [(36, 40), (18, 16), (18, 112),
      (106, 16), (106, 64), (106, 112)]:
    result.world.pudges[i].placePudge(at[0], at[1])
    result.world.pudges[i].shieldTicks = 0
    result.world.pudges[i].blinkCooldown = BlinkCooldownTicks

proc step(game: Game) =
  tickWorld(game, proc() = runBotDecisions(game))
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

proc value(game: Game, name: string): int32 =
  game.heroVms[0].runtime.getGlobal(name)

suite "v16 BASIC transfer":
  test "a defensive blink can still cast at an exposed target on the same tick":
    let game = fixture()
    game.world.pudges[0].blinkCooldown = 0
    game.world.pudges[3].placePudge(64, 40)
    game.world.hooks.add Hook(
      id: game.world.nextHookId, ownerId: game.world.pudges[3].id,
      team: EastTeam, phase: HookFlying,
      position: worldAtTile(54, 40), prior: worldAtTile(54, 40),
      origin: worldAtTile(76, 40), heading: heading(-WorldScale, 0),
      range: BaseHookRange, speed: BaseHookSpeed, peakSpeed: BaseHookSpeed,
      radius: BaseHookRadius, damage: BaseHookDamage)
    inc game.world.nextHookId
    game.step()
    check game.world.pudges[0].justBlinked
    check game.world.pudges[0].windupTicks > 0

  test "fountain rejects a blocked combat shot":
    let game = fixture()
    game.world.pudges[0].placePudge(36, 64)
    game.world.pudges[3].placePudge(78, 64)
    game.step()
    check game.value("fountainBlocked") == 1
    check game.world.pudges[0].windupTicks == 0

  test "a nearby healthy teammate blocks an ordinary offensive lane":
    let game = fixture()
    game.world.pudges[1].placePudge(42, 40)
    game.world.pudges[3].placePudge(76, 40)
    game.step()
    check game.world.pudges[0].windupTicks == 0

  test "an allied melee midpoint intentionally permits that ally":
    let game = fixture()
    game.world.pudges[1].placePudge(45, 40)
    game.world.pudges[1].hp = 500
    game.world.pudges[3].placePudge(50, 40)
    game.step()
    check game.world.pudges[0].windupTicks > 0
    check game.world.pudges[0].windupAimX div FineAimScale == 47
    check game.value("castRecipient") == game.world.pudges[1].id

  test "deliberate healing holds still and starts a real ally hook":
    let game = fixture()
    game.world.pudges[0].placePudge(30, 40)
    game.world.pudges[1].placePudge(42, 40)
    game.world.pudges[1].hp = 700
    game.step()
    check game.world.pudges[0].windupTicks > 0
    check game.world.pudges[0].windupAimX div FineAimScale == 42
    check not game.world.pudges[0].hasMoveTarget
    check game.value("curveActive") == 0
    check game.value("rescueUntil") > game.world.tick

  test "curve survives actual native windup and continues through return":
    let game = fixture()
    var flying, returning, windup: int
    var finished = false
    for tick in 0 ..< 240:
      game.step()
      game.world.pudges[0].hookCooldown = HookCooldownTicks
      if game.world.pudges[0].windupTicks > 0 and game.value("curveActive") == 1:
        inc windup
      for hook in game.world.hooks:
        if hook.ownerId == game.world.pudges[0].id and game.value("curveActive") == 1:
          if hook.phase == HookFlying: inc flying
          if hook.phase == HookReeling: inc returning
          check game.world.pudges[0].moveX <= PlayWestMax - 1
          check game.world.pudges[0].moveZ in 16'i32..111'i32
      if returning > 0 and game.value("curveActive") == 0:
        finished = true
        break
    check windup > 0
    check flying > 0
    check returning > 0
    check finished

  test "recovery and capture interrupt an active curve":
    for capture in [false, true]:
      let game = fixture()
      game.step()
      check game.value("curveActive") == 1
      if capture:
        game.world.pudges[0].hookedBy = game.world.pudges[3].id
      else:
        game.world.pudges[0].hp = 300
      game.step()
      check game.value("curveActive") == 0

  test "respawn clears a pending curve before another cast is possible":
    let game = fixture()
    game.step()
    check game.value("curveActive") == 1
    game.world.pudges[0].shieldTicks = 50
    game.world.pudges[0].hookCooldown = HookCooldownTicks
    game.world.pudges[0].windupTicks = 0
    game.step()
    check game.value("curveActive") == 0
    check game.value("rescueUntil") == 0

  test "nearest shielded enemy cannot mask an exposed target":
    let game = fixture()
    game.world.pudges[3].placePudge(50, 40)
    game.world.pudges[3].shieldTicks = 100
    game.world.pudges[4].placePudge(64, 50)
    game.step()
    check game.world.pudges[0].windupTicks > 0
    check game.world.pudges[0].windupAimX div FineAimScale == 64
    check game.world.pudges[0].windupAimY div FineAimScale == 50
