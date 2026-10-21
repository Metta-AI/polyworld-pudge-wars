## The opt-in interface between a tactical adviser and the BASIC executor.
import std/strutils
import content, sim

const TacticalLifetime* = 4 * TickRate

proc visibleEnemy*(world: World, slot: int, target: int32): bool =
  if target == 0: return true
  let me = world.pudges[slot]
  for i in 0 ..< worldObjectCount(world, me.id):
    var obj: WorldObject
    if worldObjectAt(world, me.id, i, obj) and obj.kind == PudgeObjectKind and obj.id == target and
        obj.alive and obj.team != me.team and not obj.shielded:
      return true

proc clearTactics*(vm: HeroVm) =
  vm.tacticTarget = 0
  vm.tacticLane = 0
  vm.tacticAggression = 0
  vm.tacticUntil = 0

proc validateTactics*(game: Game, slot: int) =
  let vm = game.heroVms[slot]
  let me = game.world.pudges[slot]
  if game.world.tick >= vm.tacticUntil or me.state != Alive or
      me.deaths != vm.tacticDeaths or
      not visibleEnemy(game.world, slot, vm.tacticTarget):
    vm.clearTactics()

proc applyTactics*(game: Game, slot: int, observed, deaths, target, lane,
    aggression: int32): string =
  ## Empty means accepted. The deadline is tied to the observation.
  let me = game.world.pudges[slot]
  if observed > game.world.tick or game.world.tick >= observed + TacticalLifetime:
    return "expired"
  if me.state != Alive or me.deaths != deaths: return "life_changed"
  if lane notin [0'i32, 32, 64, 96] or aggression notin -1'i32 .. 1'i32:
    return "invalid_settings"
  if not visibleEnemy(game.world, slot, target): return "target_unavailable"
  let vm = game.heroVms[slot]
  if vm == nil or not vm.tactical: return "unsupported_policy"
  vm.tacticTarget = target
  vm.tacticLane = lane
  vm.tacticAggression = aggression
  vm.tacticUntil = observed + TacticalLifetime
  vm.tacticDeaths = deaths

proc tacticalSource*(source: string): string =
  ## Adapt the known generated rusher/base policy without editing its source.
  ## Exact, unique anchors deliberately fail closed when the policy changes.
  for declaration in ["holdBack = 16\n", "retreatPct = 40\n", "recoverUntilPct = 75\n"]:
    if source.count(declaration) != 1:
      raise newException(ValueError, "--hybrid requires the base/rusher parameter defaults: " & declaration)
  result = source
  proc replaceOnce(text: var string, anchor, replacement: string) =
    if text.count(anchor) != 1:
      raise newException(ValueError,
        "--hybrid requires the supported base/rusher BASIC policy; missing or ambiguous anchor: " & anchor)
    text = text.replace(anchor, replacement)
  result.replaceOnce("curveEnabled = 1\n", """curveEnabled = 1
' Tactical preferences are recomputed every decision; zero keeps defaults.
tacticMood = tacticalAggression()
if tacticMood = -1 then
  holdBack = 20
  retreatPct = 55
elseif tacticMood = 1 then
  holdBack = 12
end if
tacticFocus = tacticalTarget()
tacticRow = tacticalLane()
""")
  result.replaceOnce("next i\nif target >= 0 then\n  lastSeen", """next i
' Preserve an immediate melee target; prefer the advised enemy otherwise.
if tacticFocus > 0 and targetD2 > 30 then
  for i = 0 to count - 1
    if ids(i) = tacticFocus and alive(i) = 1 and team(i) <> selfTeam and shield(i) = 0 then
      target = i
      targetD2 = (px(i) - selfX) * (px(i) - selfX) + (py(i) - selfY) * (py(i) - selfY)
    end if
  next i
end if
if target >= 0 then
  lastSeen""")
  result.replaceOnce("  moveTo(holdX, lineY)\n", """  if tacticRow > 0 and collector <> me then lineY = tacticRow + juke
  moveTo(holdX, lineY)
""")
