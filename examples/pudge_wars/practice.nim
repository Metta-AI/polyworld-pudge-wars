## Decision-model coach and pilots.
##
## Every tick this reads a seat's fog-clipped view, lists the moves that
## are eligible right now, and once a second asks a System One decision
## model (Jev on TypeSafe, D1 on Liquid, or a local sidecar) one batched
## Choice request: the next action and the plan. For the human seat the
## answer is a HUD cue and the human stays in control. For a pilot seat
## the chosen option is executed through the same human intent queue, so
## the model plays the butcher exactly the way a person would. Either way
## each window closes into a training sample: the observation, the
## eligible options, the model's answer with its probabilities, and what
## the seat actually did. The engine never waits for inference.
##
## Trace layout under the match directory:
##   match.json        when the match started, seat, model, endpoint
##   samples.jsonl     one record per decision window
##   intents.jsonl     every accepted or rejected intent for the seat
##   summary.json      totals, agreement, and the match result
##   replay.pwr        the exact action tape (saved by the game on exit)
##   pilot-N/          the same files for each pilot seat N

import
  std/[json, math, monotimes, os, random, strutils, tables, times],
  polyworld/[llms, oracles, pathing],
  content, maps, replays, sim

const
  PracticeEndpoint* = "https://api.typesafe.ai"
  LiquidEndpoint* = "https://api.liquid.ai/decisions"
  LocalEndpoint* = "http://127.0.0.1:8765"
  PracticeDefaultModel* = "jev-latest"
  LiquidDefaultModel* = "d1"
  LocalDefaultModel* = "d1-local"
  PracticeKeyFile* = "typesafe.key"
  LiquidKeyFile* = "liquid.key"
  AskEveryTicks* = TickRate
    ## Heartbeat: a window opens at least this often.
  AskMinGapTicks* = TickRate div 4
    ## An event opens a window no sooner than this after the last one.
  AttackTiles* = float(MeleeRange + WorldScale) / float(WorldScale)
    ## An enemy this close can be hit in melee.
  RotTiles* = 3.0
    ## Rot is worth running with an enemy this close.
  BlindHookTiles* = 8.0
    ## A speculative hook is offered this close to the lip.
    ## Rot is worth running with an enemy this close.
    ## An event opens a window no sooner than this after the last one.
    ## One Jev read per simulated second; also the sample cadence.
  AnswerMaxAgeTicks* = 2 * TickRate
    ## A cue older than this expires instead of freezing as live advice.
  HoldTicks = (TickRate * 3) div 2
    ## Anti-flicker: keep a still-eligible cue this long.
  RequestTimeoutMs = 2000
    ## Hosted endpoints: a late answer is stale advice.
  LocalTimeoutMs = 10000
    ## A local sidecar shared by several pilots answers in turn.
  ConfidenceFloor = 600'i32
    ## Thousandths. Below this Jev's answer yields to local guidance.
  DirectCueConfidence = 850'i32
    ## Hooks and rescues need this much to be a direct cue.
  HookEnvelopeTiles = 55.0
  HookBlockTiles = 5.0
  NearHookTiles = 12.0
  RegroupTiles = 20.0
  AimMatchTiles = 8.0
  LowHpPercent = 35'i32
  RecoverHpPercent = 85'i32

type
  Sighting* = object
    ## The last enemy a seat saw through its own fog, and how fast it was
    ## moving (tiles per tick), the memory a speculative hook leads from.
    seen*: bool
    tick*: int32
    id*: int32
    x*, z*, vx*, vz*: float

type
  PracticeOption* = object
    id*, title*, why*, control*: string
    targetId*: int32
    urgent*: bool
    threshold*: int32
      ## Jev confidence (thousandths) required for a direct cue.

  PracticeCue* = object
    option*: PracticeOption
    source*: string
      ## "jev", "local", or "" when there is nothing to show.
    confidence*: int32
      ## Thousandths; -1 for local guidance.
    tentative*: bool

  PracticeDecision* = object
    ## The most recent closed sample, for the HUD.
    tick*: int32
    cueId*, cueSource*, humanId*, jevAction*: string
    agreed*: int
      ## 1 followed Jev, 0 chose differently, -1 not comparable.

  PracticeStats* = object
    samples*, compared*, agreed*: int32
    hooksThrown*, hooksLanded*, deaths*, kills*: int32
    requests*, failures*, latencyMs*: int32
    answers*, delegated*: int32
      ## Model answers received, and how many cleared their threshold.
      ## The share is the drift signal: refit when it moves.

  ThresholdTable* = object
    ## Per-class confidence thresholds fitted on shadow traces against the
    ## answer key (`d1/thresholds.py fit`). Thousandths. Without a table
    ## the built-in constants apply.
    loaded*: bool
    path*: string
    model*: string
    default*: int32
    classes*: Table[string, int32]

  PracticeSample = object
    tick: int32
    atMs: int64
    obs: JsonNode
    request: JsonNode
      ## The exact System One request minus the observation, so training
      ## can re-render the prompt the model saw.
    optionIds, strategyIds: seq[string]
    jev: JsonNode
    jevAction: string
    cueId, cueSource: string
    actTick: int32
      ## Pilots: the tick the cue was executed (after the answer landed).
    trigger: string
      ## Why the window opened: periodic, or the event that opened it.
    humanId: string
    humanIntent: JsonNode
    walkId: string

  CoachConfig* = object
    ## One resolved decision-model endpoint.
    endpoint*: string
      ## Base URL; the request path is always /v1/systemone.
    model*: string
    key*: string
    provider*: string
      ## typesafe, liquid, or local.

  Practice* = ref object
    enabled*: bool
    visible*: bool
    slot*: int
    actor*: string
      ## "human" when advising a person, "pilot" when driving the seat.
    acts: bool
    actPending: bool
    sync*: bool
      ## Pilots only: block the tick until the model answers (headless
      ## self-play), instead of acting when the answer lands.
    timeoutMs: int
    dir*: string
    endpoint*: string
    provider*: string
    status*: string
      ## local, ready, connected, auth_error, unavailable, or finished.
    hint*: string
      ## One line for the HUD explaining the status.
    model*: string
    client: LlmClient
    drafter: Oracle
      ## Scratch oracle that renders the recorded request text.
    options: seq[PracticeOption]
    strategies: seq[PracticeOption]
    cue*: PracticeCue
    plan*: PracticeCue
    heldId, heldSource: string
    heldTick: int32
    pendingId: int32
    askedAt: float
    lastAskTick, retryTick, failures: int32
    answerTick: int32
    answerAction, answerStrategy: string
    answerConfidence, answerStrategyConfidence: int32
    answerProbabilities: Table[string, int32]
    open: PracticeSample
    hasOpen: bool
    last*: PracticeDecision
    hasLast*: bool
    stats*: PracticeStats
    samplesFile, intentsFile: File
    seenTick: int32
    seenAtTick: int
    prevAlive: bool
    prevKills, prevThrown, prevLanded: int32
    finished: bool
    forced*: string
      ## Rollouts: the option id the pilot must execute at its first
      ## window ("none" acts on nothing), before local guidance resumes.
    sighting*: Sighting
      ## The last enemy this seat saw, for speculative hooks.
    forcedQueued*: bool
      ## Whether the forced option translated into an intent.
    noise*: int32
      ## Pilots: thousandths chance each window executes a random eligible
      ## option instead of the cue, so traces cover states after mistakes.
    noiseRng: Rand
    pendingTrigger: string
      ## The latest event waiting to open a window.
    prevContact, prevHooked, tracked: bool
    prevAllyHooked: int
    actionIndex: int
      ## Shadow seats: tape actions consumed so far.
    prevObs: JsonNode
    prevTick: int32
      ## Shadow seats: the previous tick's observation, the state a script
      ## decided in before the tick that carried out its action.
    forcedDone*: bool
      ## Whether the forced option has been executed.

var
  thresholds*: ThresholdTable
    ## The active threshold table (see `loadThresholds`).
  askEvents* = true
    ## Events (contact, hooks, deaths) open windows between heartbeats.
  coach*: Practice
    ## The human seat's coach; nil until `practiceBegin`.
  pilots*: seq[Practice]
    ## Model-driven seats; empty until `pilotBegin`.

# --- geometry -------------------------------------------------------------

proc tileX(p: WorldPoint): float =
  float(p.x) / float(WorldScale) + float(GridTiles div 2)

proc tileZ(p: WorldPoint): float =
  float(p.z) / float(WorldScale) + float(GridTiles div 2)

proc tiles(a, b: WorldPoint): float =
  ## Distance in tiles.
  sqrt(float(distanceSquared(a, b))) / float(WorldScale)

proc segmentTiles(px, pz, ax, az, bx, bz: float): float =
  ## Distance from a point to a segment, all in tile units.
  let
    dx = bx - ax
    dz = bz - az
    length = dx * dx + dz * dz
  var u = 0.0
  if length > 0:
    u = clamp(((px - ax) * dx + (pz - az) * dz) / length, 0.0, 1.0)
  sqrt((px - ax - u * dx) * (px - ax - u * dx) +
    (pz - az - u * dz) * (pz - az - u * dz))

proc hpPercent(p: Pudge): int32 =
  if p.maxHp <= 0: 0'i32
  else: int32(100 * int64(max(p.hp, 0)) div int64(p.maxHp))

# --- the human's view ------------------------------------------------------

type HumanView = object
  me: Pudge
  team: int
  pudges: seq[Pudge]
    ## Fog-clipped, own team first in roster order.
  hooks: seq[Hook]
  walls: seq[WorldPoint]

proc humanView(world: World, slot: int): HumanView =
  result.me = world.pudges[slot]
  result.team = result.me.team.ord
  for pudge in world.pudges:
    if fogShownPudgeTeam(world, result.team, pudge):
      result.pudges.add pudge
  for hook in world.hooks:
    if hook.phase == HookIdle:
      continue
    if fogCanSeeTeam(world, result.team, hook.position):
      result.hooks.add hook
  for prop in world.props:
    if prop.kind != PropWall or not prop.alive:
      continue
    if propVisibleTo(prop, result.me.team) and
        fogCanSeeTeam(world, result.team, prop.propCenter):
      result.walls.add prop.propCenter

proc enemies(view: HumanView): seq[Pudge] =
  ## Living, unshielded visible enemies, nearest first (ties by id).
  for p in view.pudges:
    if p.state == Alive and p.team.ord != view.team and p.shieldTicks <= 0:
      result.add p
  let me = view.me
  for i in 1 ..< result.len:
    var j = i
    while j > 0:
      let
        a = result[j - 1]
        b = result[j]
        da = tiles(me.position, a.position)
        db = tiles(me.position, b.position)
      if da > db or (da == db and a.id > b.id):
        swap(result[j - 1], result[j])
        dec j
      else:
        break

proc noteSighting*(s: var Sighting, world: World, slot: int) =
  ## Remembers the nearest enemy `slot` can see this tick, with its speed
  ## from the previous sighting of the same enemy. Fog-fair: only what the
  ## seat's own view shows.
  if s.seen and s.tick == world.tick:
    return
  let seen = enemies(humanView(world, slot))
  if seen.len == 0:
    return
  let
    e = seen[0]
    x = tileX(e.position)
    z = tileZ(e.position)
    dt = world.tick - s.tick
  if s.seen and s.id == e.id and dt > 0 and dt <= 16:
    s.vx = (x - s.x) / float(dt)
    s.vz = (z - s.z) / float(dt)
  else:
    s.vx = 0
    s.vz = 0
  s = Sighting(seen: true, tick: world.tick, id: e.id, x: x, z: z,
    vx: s.vx, vz: s.vz)

proc speculativeAim*(s: Sighting, tick: int32, west: bool,
    mz: float): (float, float) =
  ## Where the league script throws a speculative hook: the last sighting
  ## led by its speed, or straight across from our row when nothing has
  ## been seen; just past the lip once the sighting is three seconds old.
  ## Kept on the enemy bank and inside the arena margins.
  var x = if west: float(RiverCenterX + 10) else: float(RiverCenterX - 10)
  var z = mz
  if s.seen:
    let age = float(tick - s.tick)
    z = s.z + s.vz * age
    x = if age <= 96: s.x + s.vx * age
        elif west: float(RiverCenterX + 2)
        else: float(RiverCenterX - 2)
  let row = int(clamp(z, 0.0, float(GridTiles - 1)))
  let lip = riverHalfWidthAt(row) + 1
  if west: x = clamp(x, float(RiverCenterX + lip), 113.0)
  else: x = clamp(x, 14.0, float(RiverCenterX - lip))
  (x, clamp(z, 16.0, 111.0))

proc allies(view: HumanView): seq[Pudge] =
  for p in view.pudges:
    if p.state == Alive and p.team.ord == view.team and p.id != view.me.id:
      result.add p

proc lineClear(view: HumanView, targetId: int32, bx, bz: float): bool =
  ## No player, wall, or the central fountain rock on the straight line
  ## from the thrower to the tile point `(bx, bz)`. Not a hit model.
  let
    me = view.me
    ax = tileX(me.position)
    az = tileZ(me.position)
  for p in view.pudges:
    if p.state != Alive or p.id == me.id or p.id == targetId:
      continue
    if segmentTiles(tileX(p.position), tileZ(p.position), ax, az, bx, bz) <
        HookBlockTiles:
      return false
  for wall in view.walls:
    if segmentTiles(tileX(wall), tileZ(wall), ax, az, bx, bz) < HookBlockTiles:
      return false
  let centre = float(GridTiles div 2)
  segmentTiles(centre, centre, ax, az, bx, bz) >= HookBlockTiles

proc hookClear(view: HumanView, target: Pudge): bool =
  ## A conservative direct-shot envelope: in range and a clear line to
  ## where the target stands now.
  let me = view.me
  if tiles(me.position, target.position) > HookEnvelopeTiles:
    return false
  view.lineClear(target.id, tileX(target.position), tileZ(target.position))

# --- where to send the hook ----------------------------------------------

type
  HookSolution* = object
    ## Where a hook thrown now would meet a target, from the thrower's
    ## fogged view. Recomputed every frame for the overlay, and used by
    ## pilots to aim.
    targetId*: int32
      ## 0 when there is no target to show.
    primary*: bool
      ## True when the coach's current cue names this target.
    ok*: bool
      ## A throw right now reaches the meeting point with a clear line.
    aimX*, aimZ*: float
      ## Meeting point, in tiles.
    fromX*, fromZ*: float
      ## The target's position now, in tiles.
    ticks*: int32
      ## Windup plus flight ticks to the meeting point.
    distance*: float
      ## Tiles from the thrower to the meeting point.
    rangeTiles*: float
      ## How far this hook can fly.
    leadTiles*: float
      ## How far ahead of the target the aim sits.
    clear*, inRange*, moving*: bool
    reason*: string
      ## "" when ok, else "blocked", "range", or "lost".

proc worldAtTiles*(x, z: float): WorldPoint =
  ## Inverse of `tileX`/`tileZ`: a tile-space point back in world units.
  WorldPoint(
    x: int32((x - float(GridTiles div 2)) * float(WorldScale)),
    z: int32((z - float(GridTiles div 2)) * float(WorldScale))
  )

proc targetVelocity(view: HumanView, target: Pudge): (float, float) =
  ## Tiles per tick. A hooked target slides toward whoever holds it at
  ## the hook's reel speed, whatever its own legs say.
  for hook in view.hooks:
    if hook.victimId == target.id and hook.phase != HookIdle:
      for owner in view.pudges:
        if owner.id == hook.ownerId:
          let
            dx = tileX(owner.position) - tileX(target.position)
            dz = tileZ(owner.position) - tileZ(target.position)
            length = max(0.001, sqrt(dx * dx + dz * dz))
            speed = float(max(hook.peakSpeed, hook.speed)) / float(WorldScale)
          return (dx / length * speed, dz / length * speed)
  (float(target.velX) / float(WorldScale), float(target.velZ) / float(WorldScale))

proc hookSolution*(world: World, slot: int, target: Pudge,
    primary = true): HookSolution =
  ## Steps the hook's real launch profile (windup, then acceleration to
  ## the cap) against the target's straight-line motion until the head
  ## would reach the predicted spot, then checks range and line.
  let
    view = humanView(world, slot)
    me = view.me
  result = HookSolution(targetId: target.id, primary: primary,
    fromX: tileX(target.position), fromZ: tileZ(target.position),
    aimX: tileX(target.position), aimZ: tileZ(target.position),
    reason: "lost")
  if me.state != Alive or target.state != Alive:
    return
  let
    mx = tileX(me.position)
    mz = tileZ(me.position)
    level = me.upgrades[UpgradeSpeed]
    rangeTiles = float(thrownHookRange(me.upgrades[UpgradeDistance],
      me.hasBuff(RuneBigHook))) / float(WorldScale)
    radiusTiles = float(hookRadius(me.upgrades[UpgradeRadius])) /
      float(WorldScale)
    (vx, vz) = targetVelocity(view, target)
    moving = abs(vx) + abs(vz) > 0.001
    limit = float(GridTiles - 1)
  var
    speed = float(thrownHookSpeed(level, me.hasBuff(RuneLightning))) /
      float(WorldScale)
    flown = 0.0
    tick = HookWindupTicks
  result.moving = moving
  result.rangeTiles = rangeTiles
  result.reason = "range"
  # Nothing is thrown during the windup; the target keeps walking.
  while flown < rangeTiles and tick < 8 * TickRate:
    inc tick
    flown += speed
    speed = min(speed + float(HookAccel) / float(WorldScale),
      float(HookSpeedMax) / float(WorldScale))
    let
      px = clamp(result.fromX + vx * float(tick), 0.0, limit)
      pz = clamp(result.fromZ + vz * float(tick), 0.0, limit)
      dx = px - mx
      dz = pz - mz
      need = sqrt(dx * dx + dz * dz)
    if flown + radiusTiles >= need:
      result.aimX = px
      result.aimZ = pz
      result.ticks = tick
      result.distance = need
      result.inRange = need <= rangeTiles + radiusTiles
      result.leadTiles = sqrt((px - result.fromX) * (px - result.fromX) +
        (pz - result.fromZ) * (pz - result.fromZ))
      result.clear = view.lineClear(target.id, px, pz)
      result.ok = result.inRange and result.clear
      result.reason = if result.ok: "" elif not result.clear: "blocked"
        else: "range"
      return
  # Never caught up inside the range: show the last reachable point.
  result.ticks = tick
  result.distance = sqrt((result.aimX - mx) * (result.aimX - mx) +
    (result.aimZ - mz) * (result.aimZ - mz))

proc coachAim*(p: Practice, world: World): HookSolution =
  ## The hook the coach is pointing at right now: the cue's target when
  ## the cue is a hook, otherwise the best local hook option while the
  ## hook is ready, so the marker tracks a live opening between reads.
  if p == nil or not p.enabled or p.slot < 0 or p.slot >= world.pudges.len:
    return
  var
    option: PracticeOption
    found = false
    primary = false
  if p.cue.source.len > 0 and (p.cue.option.id.startsWith("hook_") or
      p.cue.option.id.startsWith("follow_") or
      p.cue.option.id.startsWith("rescue_")):
    option = p.cue.option
    found = true
    primary = true
  else:
    for item in p.options:
      if item.id.startsWith("hook_") or item.id.startsWith("follow_"):
        option = item
        found = true
        break
  if not found:
    return
  let view = humanView(world, p.slot)
  for pudge in view.pudges:
    if pudge.id == option.targetId and pudge.state == Alive:
      return hookSolution(world, p.slot, pudge, primary)

proc aimAdvice*(aim: HookSolution): string =
  ## One HUD line that changes as the target moves.
  if aim.targetId == 0:
    return ""
  let seconds = float(aim.ticks) / float(TickRate)
  let landing = "lands in " & formatFloat(seconds, ffDecimal, 1) & " s"
  if aim.ok:
    if aim.leadTiles >= 1.0:
      "Throw at the marker, " & $int(aim.leadTiles + 0.5) &
        " tiles ahead of them, " & landing
    else:
      "Throw at the marker now, " & landing
  elif aim.reason == "blocked":
    "Line is blocked right now, step sideways for a clean lane"
  elif aim.reason == "range":
    "Out of reach by about " &
      $int(max(1.0, aim.distance - aim.rangeTiles) + 0.5) &
      " tiles, close in before throwing"
  else:
    "Lost sight of them, hold the throw"

proc pudgeJson(p: Pudge, slot: int, public: bool): JsonNode =
  let home = p.spawnTile
  result = %*{
    "id": p.id, "slot": slot, "team": p.team.ord,
    "x": round(tileX(p.position), 3), "y": round(tileZ(p.position), 3),
    "hp": max(p.hp, 0), "max_hp": p.maxHp, "alive": p.state == Alive,
    "hooked": p.hookedBy != 0, "shield": max(p.shieldTicks, 0),
    "in_river": p.inRiver, "layer": p.layer
  }
  if public:
    return
  var upgrades = newJArray()
  for kind in UpgradeKind:
    upgrades.add %p.upgrades[kind]
  result["hook_ready"] = %(p.hookCooldown <= 0 and p.windupTicks <= 0)
  result["blink_ready"] = %(p.blinkCooldown <= 0 and p.windupTicks <= 0 and
    p.hookedBy == 0)
  result["points"] = %p.points
  result["kills"] = %p.kills
  result["deaths"] = %p.deaths
  result["home_x"] = %home.x
  result["home_y"] = %home.z
  result["upgrades"] = upgrades

proc observationJson*(world: World, slot: int): JsonNode =
  ## The human-visible facts only: own seat in full, every visible butcher
  ## with its rendered public fields, visible hooks, and the score.
  let view = humanView(world, slot)
  var pudges = newJArray()
  for p in view.pudges:
    pudges.add pudgeJson(p, p.slot, public = p.id != view.me.id)
  var hooks = newJArray()
  for hook in view.hooks:
    hooks.add %*{
      "owner_id": hook.ownerId, "team": hook.team.ord,
      "x": round(tileX(hook.position), 3), "y": round(tileZ(hook.position), 3),
      "victim": hook.victimId, "flying": hook.phase == HookFlying
    }
  %*{
    "tick": world.tick,
    "score": {"west": world.teamKills[WestTeam.ord],
              "east": world.teamKills[EastTeam.ord]},
    "kill_goal": world.killGoal,
    "self": pudgeJson(view.me, slot, public = false),
    "visible": {"pudges": pudges, "hooks": hooks}
  }

# --- eligible options ------------------------------------------------------

proc add(list: var seq[PracticeOption], id, title, why: string,
    control = "", target = 0'i32, urgent = false, threshold = ConfidenceFloor) =
  list.add PracticeOption(id: id, title: title, why: why, control: control,
    targetId: target, urgent: urgent, threshold: threshold)

proc has(list: seq[PracticeOption], id: string): bool =
  for item in list:
    if item.id == id:
      return true

proc find*(list: seq[PracticeOption], id: string): PracticeOption =
  for item in list:
    if item.id == id:
      return item

proc practiceOptions*(world: World, slot: int):
    tuple[actions, strategies: seq[PracticeOption]] =
  ## Eligible moves in local fallback priority order, plus plans. Mirrors
  ## the web coach so traces from both share one vocabulary.
  let
    view = humanView(world, slot)
    me = view.me
    hp = hpPercent(me)
    foes = view.enemies
    friends = view.allies
  var actions, strategies: seq[PracticeOption]
  strategies.add("coordinate", "Make the next exchange a team play",
    "Take separate throwing lanes. Follow a teammate's catch when your " &
    "hook has a clear path.")
  if me.state != Alive:
    actions.add("respawn", "Plan your return",
      "You're down. Locate your teammate before the next engagement.")
    strategies.setLen(0)
    strategies.add("reset", "Return together",
      "Rejoin your teammate after respawning and find a fresh throwing lane.")
    return (actions, strategies)
  if me.hookedBy != 0:
    actions.add("hooked", "Prepare to escape when released",
      "You're on a hook. Movement and blink cannot free you mid-pull.",
      urgent = true)
    return (actions, strategies)
  var nearHook = false
  for hook in view.hooks:
    if hook.team.ord != view.team and hook.phase == HookFlying and
        hook.victimId == 0 and tiles(me.position, hook.position) < NearHookTiles:
      nearHook = true
  if nearHook and me.shieldTicks <= 0:
    actions.add("dodge", "Watch the hook, move off its line",
      "An enemy hook is close. Move sideways to its visible path.",
      "WASD / right-click", urgent = true)
  if hp <= LowHpPercent:
    actions.add("retreat", "Fall back toward your healing pad",
      "You're at " & $hp & "% health. Recover before taking another exchange.",
      "WASD / right-click", urgent = true)
  let
    inRiver = abs(tileX(me.position) - float(RiverCenterX)) <=
      float(riverHalfWidthAt(int(clamp(tileZ(me.position), 0.0,
        float(GridTiles - 1)))))
  if me.blinkCooldown <= 0 and (nearHook or hp <= LowHpPercent or inRiver):
    actions.add("blink",
      (if inRiver: "Blink out of the river" else: "Blink away"),
      (if inRiver: "Blink is ready and you are in the river. Jump back to " &
          "your bank before a hook finds you."
       else: "Blink is ready. Jump clear of the exchange toward your bank."),
      "Space")
  var closest = 1.0e9
  for enemy in foes:
    if enemy.state == Alive:
      closest = min(closest, tiles(me.position, enemy.position))
      if tiles(me.position, enemy.position) <= AttackTiles and
          enemy.shieldTicks <= 0:
        actions.add("attack_" & $enemy.id, "Attack enemy " & $(enemy.slot + 1),
          "This enemy is in melee reach. Cleave while they are close.",
          "Right-click enemy", enemy.id)
  if closest <= RotTiles and not me.rotOn:
    actions.add("rot", "Turn Rot on",
      "An enemy is beside you. Rot damages everyone around you each pulse.",
      "R")
  elif me.rotOn and closest > RotTiles + 1:
    actions.add("rot", "Turn Rot off",
      "No enemy is close enough for Rot to pay for itself.", "R")
  if hp < RecoverHpPercent:
    strategies.add("recover", "Recover before committing",
      "Use your healing pad, then return with enough health for another " &
      "exchange.")
    let home = me.spawnTile
    if abs(tileX(me.position) - float(home.x)) <= 2 and
        abs(tileZ(me.position) - float(home.z)) <= 2:
      actions.add("heal", "Stay on your healing pad",
        "You're at " & $hp & "% health and within your home pad's healing area.")
  var ownHook = false
  for hook in view.hooks:
    if hook.ownerId == me.id:
      ownHook = true
  let ready = me.hookCooldown <= 0 and me.windupTicks <= 0 and not ownHook
  if ready:
    var caught, endangered: seq[int32]
    for hook in view.hooks:
      if hook.victimId == 0:
        continue
      if hook.team.ord == view.team and hook.ownerId != me.id:
        caught.add hook.victimId
      elif hook.team.ord != view.team:
        endangered.add hook.victimId
    for ally in friends:
      if ally.id in endangered and view.hookClear(ally):
        actions.add("rescue_" & $ally.id,
          "Try a rescue hook on ally " & $(ally.slot + 1),
          "Your teammate is being pulled by an enemy. An ally hook can pull " &
          "them back and heal them.", "Aim at ally, then Q", ally.id,
          threshold = DirectCueConfidence)
    if hp > LowHpPercent:
      for enemy in foes:
        if not view.hookClear(enemy):
          continue
        let follow = enemy.id in caught
        actions.add((if follow: "follow_" else: "hook_") & $enemy.id,
          (if follow: "Follow up on" else: "Line up a hook on") &
            " enemy " & $(enemy.slot + 1),
          if follow:
            "Your teammate has this enemy on their hook. Check the moving " &
            "target's path before throwing."
          else:
            "Your hook is ready and this enemy is nearby. Check terrain and " &
            "lead their movement before throwing.",
          "Aim with cursor, then Q", enemy.id, threshold = DirectCueConfidence)
    var anyHook = false
    for item in actions:
      if item.id.startsWith("hook_") or item.id.startsWith("follow_"):
        anyHook = true
    if not anyHook and hp > LowHpPercent:
      let
        mx = tileX(me.position)
        mz = tileZ(me.position)
        row = int(clamp(mz, 0.0, float(GridTiles - 1)))
        lip = if view.team == WestTeam.ord:
            float(RiverCenterX - riverHalfWidthAt(row) - 1)
          else: float(RiverCenterX + riverHalfWidthAt(row) + 1)
      # Half the hook's travel: thrown from here it still crosses the
      # river with distance to spare, which is where the scripts throw.
      let reach = max(BlindHookTiles,
        float(thrownHookRange(me.upgrades[UpgradeDistance],
          me.hasBuff(RuneBigHook))) / float(WorldScale) / 2)
      if abs(mx - lip) <= reach:
        actions.add("hook_blind", "Throw a speculative hook across",
          "No enemy is in sight. A hook thrown across the river can catch " &
          "someone hiding in the fog.", "Aim across, then Q",
          threshold = DirectCueConfidence)
  else:
    actions.add("wait_hook", "Reposition while your hook returns",
      "Your hook is cooling down, casting, or already in flight. Set up " &
      "your next angle.", "WASD / right-click")
  if friends.len > 0:
    var nearest = 1.0e9
    for ally in friends:
      nearest = min(nearest, tiles(me.position, ally.position))
    if nearest > RegroupTiles:
      actions.add("regroup", "Move closer to your teammate",
        "Your living teammate is over 20 tiles away. Close the gap while " &
        "keeping separate throwing lanes.", "WASD / right-click")
  var canUpgrade = false
  for kind in UpgradeKind:
    if me.upgrades[kind] < MaxUpgradeLevel:
      canUpgrade = true
  if me.points > 0 and canUpgrade:
    actions.add("upgrade", "Spend your hook upgrade point",
      "You have an unspent point. Choose damage, range, speed, or radius " &
      "in the ability bar.", "Keys 1-4")
  if hp < RecoverHpPercent and not actions.has("retreat") and
      not actions.has("heal"):
    actions.add("retreat", "Head back toward your healing pad",
      "You're at " & $hp & "% health. Topping up now beats losing the " &
      "next exchange.", "WASD / right-click")
  if me.blinkCooldown <= 0 and foes.len > 0 and not actions.has("blink"):
    actions.add("blink", "Blink to a new angle",
      "Blink is ready. A jump can open a throwing lane or break contact.",
      "Space")
  if foes.len > 0:
    actions.add("reposition", "Find a fresh throwing angle",
      "Keep moving between throws. Use visible enemies and your teammate " &
      "to choose a lane.", "WASD / right-click")
  else:
    actions.add("scout", "Scout along your riverbank",
      "No enemies are visible. Move toward the river edge and scan along " &
      "your bank for an opening.", "WASD / right-click")
  if friends.len == 0:
    var kept: seq[PracticeOption]
    for item in strategies:
      if item.id != "coordinate":
        kept.add item
    strategies = kept
  strategies.add("fish", "Create a clean hook opportunity",
    "Stay near your bank, vary your angle, and avoid throwing through " &
    "other players or the fountain.")
  if hp <= LowHpPercent and strategies.has("recover"):
    var ordered = @[strategies.find("recover")]
    for item in strategies:
      if item.id != "recover":
        ordered.add item
    strategies = ordered
  (actions, strategies)

# --- the Jev request -------------------------------------------------------

proc optionsJson(list: seq[PracticeOption]): JsonNode =
  result = newJObject()
  for item in list:
    result[item.id] = %*{"title": item.title, "why": item.why}

proc practiceRequest*(oracle: Oracle, model: string, obs: JsonNode,
    actions, strategies: seq[PracticeOption]): string =
  ## Drafts one batched System One request: the human's view and two
  ## Choice questions, each with an explicit `none`.
  discard oracle.state("game", %("Fresh Meat. A human skillshot team " &
    "arena. Advise only; never control the player."))
  discard oracle.state("view", %("Current human self and team-shared " &
    "visible entities only. Unseen enemies are unknown."))
  discard oracle.state("observation", obs)
  discard oracle.state("actions", optionsJson(actions))
  discard oracle.state("strategies", optionsJson(strategies))
  discard oracle.question("action", int32(ChoiceQuestion.ord),
    "Choose the most useful next action for the HUMAN self now. " &
    "Prioritize survival, ally rescues and coordinated catches. Only " &
    "choose from supplied eligible actions. A potential hook is not a " &
    "guaranteed hit. Choose none when uncertain.")
  for item in actions:
    discard oracle.criterion("action", item.id, item.title & ". " & item.why)
  discard oracle.criterion("action", "none", "No clear action to recommend.")
  discard oracle.question("strategy", int32(ChoiceQuestion.ord),
    "Choose a useful plan for the HUMAN's next few exchanges, based on " &
    "health, team spacing and visible opportunities. Treat the immediate " &
    "action and longer plan as separate judgments. Choose none when " &
    "uncertain.")
  for item in strategies:
    discard oracle.criterion("strategy", item.id, item.title & ". " & item.why)
  discard oracle.criterion("strategy", "none", "No clear strategy to recommend.")
  oracle.requestBody(model)

# --- configuration ---------------------------------------------------------

proc practiceDataDir*(): string =
  ## Where the desktop app keeps practice traces and the TypeSafe key.
  when defined(macosx):
    getHomeDir() / "Library/Application Support/Pudge Wars"
  else:
    getHomeDir() / ".pudge-wars"

proc readKeyFile(path: string): string =
  if not fileExists(path):
    return
  for line in path.readFile.splitLines:
    let text = line.strip
    if text.len > 0 and not text.startsWith("#"):
      return text.strip(chars = {'"', '\''})

proc readEnvLocal(path, name: string): string =
  if not fileExists(path):
    return
  for line in path.readFile.splitLines:
    let text = line.strip
    if text.startsWith(name & "="):
      return text[name.len + 1 .. ^1].strip.strip(chars = {'"', '\''})

proc keyFor(envName, fileName: string): string =
  ## Environment first, then the user data dir, then a repository
  ## `.env.local` for development runs.
  result = getEnv(envName).strip
  if result.len == 0:
    result = readKeyFile(practiceDataDir() / fileName)
  if result.len == 0:
    result = readEnvLocal(getCurrentDir() / ".env.local", envName)

proc practiceKey*(): string =
  ## The TypeSafe key for Jev.
  keyFor("TYPESAFE_API_KEY", PracticeKeyFile)

proc liquidKey*(): string =
  ## The Liquid key for hosted D1.
  keyFor("LIQUID_API_KEY", LiquidKeyFile)

proc coachConfig*(endpoint = "", model = ""): CoachConfig =
  ## Resolves a coach endpoint name or URL. `jev` (the default) is
  ## TypeSafe, `d1` is Liquid's hosted D1, `local` is a sidecar on
  ## 127.0.0.1:8765 (`d1/serve.py`), `none` is local guidance alone (the
  ## control arm for pilots), and any loopback or allowed base URL is used
  ## as given. `COACH_ENDPOINT` and `COACH_MODEL` set defaults.
  var name = endpoint.strip
  if name.len == 0:
    name = getEnv("COACH_ENDPOINT").strip
  case name.toLowerAscii
  of "", "jev", "typesafe":
    result = CoachConfig(endpoint: PracticeEndpoint, provider: "typesafe",
      key: practiceKey(),
      model: getEnv("TYPESAFE_MODEL", PracticeDefaultModel))
  of "d1", "liquid":
    result = CoachConfig(endpoint: LiquidEndpoint, provider: "liquid",
      key: liquidKey(), model: getEnv("LIQUID_MODEL", LiquidDefaultModel))
  of "local", "sidecar":
    result = CoachConfig(endpoint: LocalEndpoint, provider: "local",
      key: getEnv("COACH_API_KEY"), model: LocalDefaultModel)
  of "none", "off", "drafter":
    result = CoachConfig(provider: "drafter", model: "local-drafter")
  else:
    result = CoachConfig(endpoint: name.strip(leading = false,
      trailing = true, chars = {'/'}), key: getEnv("COACH_API_KEY"))
    if result.endpoint == PracticeEndpoint:
      result.provider = "typesafe"
      result.model = getEnv("TYPESAFE_MODEL", PracticeDefaultModel)
      if result.key.len == 0:
        result.key = practiceKey()
    elif result.endpoint == LiquidEndpoint:
      result.provider = "liquid"
      result.model = getEnv("LIQUID_MODEL", LiquidDefaultModel)
      if result.key.len == 0:
        result.key = liquidKey()
    else:
      result.provider = "local"
      result.model = LocalDefaultModel
  let chosen = if model.len > 0: model else: getEnv("COACH_MODEL")
  if chosen.len > 0:
    result.model = chosen

proc epochMs(): int64 =
  int64(epochTime() * 1000)

# --- thresholds ------------------------------------------------------------

proc optionClass*(id: string): string =
  ## The decision class an option id belongs to; thresholds are fitted
  ## per class because a hook and a walk carry different stakes.
  if id.startsWith("hook_") or id.startsWith("follow_") or
      id.startsWith("rescue_"):
    "hook"
  elif id in ["retreat", "dodge", "heal", "hold"]:
    "safety"
  elif id in ["regroup", "scout", "reposition", "wait_hook"]:
    "move"
  elif id == "upgrade":
    "economy"
  elif id == "none":
    "none"
  else:
    "other"

proc thousandths(node: JsonNode): int32 =
  if node == nil: -1'i32
  elif node.kind == JFloat: int32(round(node.getFloat * 1000))
  elif node.kind == JInt: int32(node.getInt * 1000)
  else: -1'i32

proc parseThresholds*(text: string, path = ""): ThresholdTable =
  ## Reads a `thresholds.json`: `{"default": 0.6, "classes": {"hook": 0.85}}`,
  ## plus the model it was fitted for. Unknown classes fall back to default.
  let doc = parseJson(text)
  result.path = path
  result.model = doc{"model"}.getStr("")
  result.default = thousandths(doc{"default"})
  if result.default < 0:
    result.default = ConfidenceFloor
  if doc{"classes"} != nil and doc{"classes"}.kind == JObject:
    for name, node in doc["classes"]:
      let value = if node.kind == JObject: thousandths(node{"threshold"})
        else: thousandths(node)
      if value >= 0:
        result.classes[name] = min(value, 1000'i32)
  result.loaded = true

proc loadThresholds*(path = ""): ThresholdTable =
  ## Installs the table at `path` (default `<data dir>/thresholds.json`)
  ## as the active one. A missing file keeps the constants.
  let file = if path.len > 0: path else: practiceDataDir() / "thresholds.json"
  result = ThresholdTable()
  if fileExists(file):
    try:
      result = parseThresholds(readFile(file), file)
    except JsonParsingError, ValueError, KeyError:
      result = ThresholdTable()
  thresholds = result

proc thresholdFor*(option: PracticeOption): int32 =
  ## Confidence a model answer needs to be acted on or shown as the cue.
  if not thresholds.loaded:
    return option.threshold
  thresholds.classes.getOrDefault(optionClass(option.id), thresholds.default)

proc strategyThreshold*(): int32 =
  if not thresholds.loaded:
    return ConfidenceFloor
  thresholds.classes.getOrDefault("strategy", thresholds.default)

# --- lifecycle -------------------------------------------------------------

proc writeLine(file: File, node: JsonNode) =
  if file != nil:
    file.writeLine($node)
    file.flushFile()

proc release(p: Practice) =
  if p == nil:
    return
  if p.samplesFile != nil:
    p.samplesFile.close()
    p.samplesFile = nil
  if p.intentsFile != nil:
    p.intentsFile.close()
    p.intentsFile = nil
  p.client.close()

proc newMatchDir*(baseDir = ""): string =
  ## A fresh timestamped trace directory under `baseDir` (default the
  ## user data dir).
  let base = if baseDir.len > 0: baseDir else: practiceDataDir() / "practice"
  result = base / now().format("yyyyMMdd-HHmmss")
  var suffix = 1
  while dirExists(result):
    inc suffix
    result = base / (now().format("yyyyMMdd-HHmmss") & "-" & $suffix)
  createDir(result)

proc connect(p: Practice, game: Game, config: CoachConfig, offline: bool) =
  ## Opens the trace files and, when the endpoint needs no key or has
  ## one, an isolated HTTP client for this seat.
  p.endpoint = config.endpoint
  p.provider = config.provider
  p.model = config.model
  p.samplesFile = open(p.dir / "samples.jsonl", fmAppend)
  p.intentsFile = open(p.dir / "intents.jsonl", fmAppend)
  let keyed = config.key.len > 0 or config.provider == "local"
  p.timeoutMs = if config.provider == "local": LocalTimeoutMs
    else: RequestTimeoutMs
  if not offline and keyed and NativeRequests:
    try:
      p.client = newLlmClient(p.slot, LlmConfig(
        baseUrl: config.endpoint, key: config.key, oracleModel: config.model,
        interval: 1, timeoutMs: p.timeoutMs))
      p.status = "ready"
      p.hint = "The model reads the next exchange once a second."
    except LlmError as error:
      p.status = "local"
      p.hint = "Local cues only. " & error.msg
  else:
    p.status = "local"
    p.hint =
      if config.provider == "liquid":
        "Local cues only. Put a Liquid key in " &
          (practiceDataDir() / LiquidKeyFile) & " to connect D1."
      else:
        "Local cues only. Put a TypeSafe key in " &
          (practiceDataDir() / PracticeKeyFile) & " to connect Jev."
  var meta = %*{
    "started_at": now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    "started_ms": epochMs(), "slot": p.slot, "actor": p.actor,
    "model": p.model, "endpoint": p.endpoint, "provider": p.provider,
    "connected": p.client != nil, "tick": game.world.tick,
    "map_seed": game.map.seed, "pudges": game.world.pudges.len
  }
  writeFile(p.dir / "match.json", pretty(meta))
  let me = game.world.pudges[p.slot]
  p.prevAlive = me.state == Alive
  p.prevKills = me.kills
  p.prevThrown = me.hooksThrown
  p.prevLanded = me.hooksLanded
  p.seenTick = -1
  p.answerTick = -1
  p.lastAskTick = -AskEveryTicks
  p.cue.confidence = -1
  p.plan.confidence = -1

proc practiceBegin*(game: Game, baseDir = "", enabled = true, key = "",
    model = "", offline = false, endpoint = ""): Practice =
  ## Starts coaching the first human seat of `game`. Opens a fresh trace
  ## directory and, with a key, one isolated HTTP client. Safe to call
  ## again for a rematch: the previous coach is finished first.
  coach.release()
  var config = coachConfig(endpoint, model)
  if key.len > 0:
    config.key = key
  result = Practice(enabled: enabled, visible: true, slot: -1,
    actor: "human", status: "off", model: config.model,
    endpoint: config.endpoint, provider: config.provider)
  coach = result
  if not enabled or game == nil or game.humanSlots.len == 0 or
      game.replayMode:
    result.enabled = false
    return
  result.slot = game.humanSlots[0]
  result.dir = newMatchDir(baseDir)
  result.connect(game, config, offline or config.provider == "drafter")

proc pilotBegin*(game: Game, slot: int, matchDir = "", key = "",
    model = "", offline = false, endpoint = "", sync = false): Practice =
  ## Starts a model-driven pilot on `slot`, which must be a human seat of
  ## `game` (the pilot queues intents like a person). Its trace lives in
  ## `matchDir/pilot-<slot>`; an empty `matchDir` opens a fresh one.
  var config = coachConfig(endpoint, model)
  if key.len > 0:
    config.key = key
  result = Practice(enabled: true, visible: true, slot: slot,
    actor: "pilot", acts: true, sync: sync, status: "off",
    model: config.model, endpoint: config.endpoint,
    provider: config.provider)
  if game == nil or game.replayMode or slot notin game.humanSlots or
      slot < 0 or slot >= game.world.pudges.len:
    result.enabled = false
    return
  for existing in pilots:
    if existing.slot == slot and not existing.finished:
      existing.release()
      existing.finished = true
  let base = if matchDir.len > 0: matchDir else: newMatchDir()
  result.dir = base / ("pilot-" & $slot)
  createDir(result.dir)
  result.connect(game, config, offline or config.provider == "drafter")
  pilots.add result

proc shadowBegin*(game: Game, slot: int, matchDir = ""): Practice =
  ## Records a script-driven seat as a teacher: every window keeps the
  ## eligible options and what the script did, labelled like a person's
  ## play (`actor` "bot"). Needs the match to be recording, since the
  ## script's actions are read off the tape. Trace in `matchDir/bot-<slot>`.
  result = Practice(enabled: true, visible: false, slot: slot,
    actor: "bot", status: "off", model: "", endpoint: "", provider: "script")
  if game == nil or game.replayMode or slot in game.humanSlots or
      slot < 0 or slot >= game.world.pudges.len:
    result.enabled = false
    return
  for existing in pilots:
    if existing.slot == slot and not existing.finished:
      existing.release()
      existing.finished = true
  let base = if matchDir.len > 0: matchDir else: newMatchDir()
  result.dir = base / ("bot-" & $slot)
  createDir(result.dir)
  result.connect(game, CoachConfig(provider: "script",
    model: "script"), offline = true)
  result.status = "shadow"
  result.hint = "Recording the script's decisions."
  result.actionIndex = if game.recorder != nil: game.recorder.data.actions.len
    else: 0
  pilots.add result

proc pilotsEnd() =
  ## Forgets finished pilots so a rematch starts clean.
  var kept: seq[Practice]
  for p in pilots:
    if not p.finished:
      kept.add p
  pilots = kept
proc decisionFrom(p: Practice): PracticeDecision =
  let s = p.open
  result = PracticeDecision(tick: s.tick, cueId: s.cueId,
    cueSource: s.cueSource, humanId: s.humanId, jevAction: s.jevAction,
    agreed: -1)
  # A pilot's decision is the cue it executed; a person's is what they did.
  let chosen = if p.acts: s.cueId else: s.humanId
  if s.jevAction.len > 0 and s.jevAction != "none" and chosen.len > 0 and
      chosen != "none":
    result.agreed = int(chosen == s.jevAction)

proc closeSample(p: Practice, tick: int32) =
  ## Writes the open sample. Walk-only windows close with their last walk
  ## class; a window with no decisive intent closes as `none`.
  if not p.hasOpen:
    return
  if p.open.humanId.len == 0:
    p.open.humanId = if p.open.walkId.len > 0: p.open.walkId else: "none"
    if p.open.humanId notin p.open.optionIds:
      # The walk read as a class this window did not offer (the enemy
      # left sight, health dipped mid-window): keep the label answerable.
      p.open.humanId = "none"
      for id in ["reposition", "wait_hook", "scout", "regroup"]:
        if id in p.open.optionIds:
          p.open.humanId = id
          break
  let decision = p.decisionFrom
  p.last = decision
  p.hasLast = true
  inc p.stats.samples
  if decision.agreed >= 0:
    inc p.stats.compared
    if decision.agreed == 1:
      inc p.stats.agreed
  var record = %*{
    "tick": p.open.tick, "closed_tick": tick, "slot": p.slot,
    "actor": p.actor, "at_ms": p.open.atMs, "closed_ms": epochMs(),
    "trigger": p.open.trigger,
    "observation": p.open.obs,
    "request": (if p.open.request == nil: newJNull() else: p.open.request),
    "options": p.open.optionIds, "strategies": p.open.strategyIds,
    "jev": (if p.open.jev == nil: newJNull() else: p.open.jev),
    "cue": {"id": p.open.cueId, "source": p.open.cueSource,
            "tick": (if p.acts and p.open.actTick > 0: %p.open.actTick
                     else: newJNull())},
    "human": {"id": p.open.humanId,
              "intent": (if p.open.humanIntent == nil: newJNull()
                         else: p.open.humanIntent)},
    "agreed": (if decision.agreed < 0: newJNull() else: %(decision.agreed == 1))
  }
  p.samplesFile.writeLine(record)
  p.hasOpen = false
  p.open = PracticeSample()

proc openSample(p: Practice, world: World, tick: int32, trigger = "periodic",
    observed: JsonNode = nil) =
  ## Opens a window on the current options. `observed` replaces the live
  ## observation when the window describes an earlier state.
  p.closeSample(tick)
  var optionIds, strategyIds: seq[string]
  for item in p.options:
    optionIds.add item.id
  for item in p.strategies:
    strategyIds.add item.id
  let obs = if observed != nil: observed else: observationJson(world, p.slot)
  if p.drafter == nil:
    p.drafter = newOracle()
  p.drafter.beginTick(tick)
  var request: JsonNode
  let body = practiceRequest(p.drafter, p.model, obs, p.options, p.strategies)
  if body.len > 0:
    try:
      request = parseJson(body)
      request["state"].delete("observation")
    except JsonParsingError, KeyError:
      request = nil
  p.open = PracticeSample(tick: tick, atMs: epochMs(), obs: obs,
    request: request, optionIds: optionIds, strategyIds: strategyIds,
    cueId: p.cue.option.id, cueSource: p.cue.source, trigger: trigger)
  p.hasOpen = true
  p.actPending = p.acts

proc practiceBindAnswer*(p: Practice, tick: int32, action, strategy: string,
    confidence, strategyConfidence: int32,
    probabilities: Table[string, int32], latencyMs = -1'i32) =
  ## Accepts one Jev answer for the current window. Tests use this directly;
  ## the HTTP path calls it after validating the response.
  p.answerTick = tick
  p.answerAction = action
  p.answerStrategy = strategy
  p.answerConfidence = confidence
  p.answerStrategyConfidence = strategyConfidence
  p.answerProbabilities = probabilities
  p.status = "connected"
  p.hint = "You're in control. Cues refresh as the situation changes."
  if latencyMs >= 0:
    p.stats.latencyMs = latencyMs
  inc p.stats.answers
  var needed = ConfidenceFloor
  if p.options.has(action):
    needed = thresholdFor(p.options.find(action))
  elif thresholds.loaded:
    needed = thresholds.classes.getOrDefault("none", thresholds.default)
  let delegated = confidence >= needed
  if delegated:
    inc p.stats.delegated
  if p.hasOpen:
    var probs = newJObject()
    for key, value in probabilities:
      probs[key] = %(float(value) / 1000)
    p.open.jev = %*{
      "model": p.model, "endpoint": p.endpoint, "action": action,
      "confidence": float(confidence) / 1000, "probabilities": probs,
      "strategy": strategy,
      "strategy_confidence": float(strategyConfidence) / 1000,
      "latency_ms": latencyMs,
      "threshold": float(needed) / 1000, "delegated": delegated,
      "thresholds": (if thresholds.loaded: %thresholds.path else: newJNull())
    }
    p.open.jevAction = action

proc backoff(p: Practice, tick: int32, auth: bool) =
  inc p.failures
  inc p.stats.failures
  p.answerTick = -1
  if auth:
    p.status = "auth_error"
    p.hint = "Jev couldn't authenticate. Local cues continue. Check the key."
    p.retryTick = int32.high
  else:
    p.status = "unavailable"
    p.hint = "Jev is temporarily unavailable. Local cues continue."
    p.retryTick = tick + TickRate * int32(min(30, 1 shl min(int(p.failures), 5)))

proc pollJev(p: Practice, tick: int32) =
  if p.client == nil or p.pendingId == 0:
    return
  let oracle = p.client.oracle
  case oracle.poll(p.pendingId)
  of 0:
    return
  else:
    let
      id = p.pendingId
      latency = int32((epochTime() - p.askedAt) * 1000)
    p.pendingId = 0
    let action = oracle.answer(id, "action")
    let strategy = oracle.answer(id, "strategy")
    if oracle.poll(id) < 0 or action.value < 0:
      let status = p.client.status(id)
      p.backoff(tick, auth = status in [401, 403])
      return
    # Criteria were added in option order with `none` last.
    var actionIds, strategyIds: seq[string]
    for item in p.options:
      actionIds.add item.id
    actionIds.add "none"
    for item in p.strategies:
      strategyIds.add item.id
    strategyIds.add "none"
    if p.hasOpen:
      actionIds = p.open.optionIds & @["none"]
      strategyIds = p.open.strategyIds & @["none"]
    let
      chosen = if action.value < actionIds.len: actionIds[action.value]
        else: "none"
      plan = if strategy.value >= 0 and strategy.value < strategyIds.len:
          strategyIds[strategy.value]
        else: "none"
    p.failures = 0
    p.practiceBindAnswer(tick, chosen, plan, action.confidence,
      strategy.confidence, action.probabilities, latency)

proc askJev(p: Practice, world: World, tick: int32) =
  if p.client == nil or p.pendingId != 0 or tick < p.retryTick:
    return
  if p.client.ready != 0:
    return
  let body = practiceRequest(p.client.oracle, p.model,
    p.open.obs, p.options, p.strategies)
  if body.len == 0:
    return
  var id = 0'i32
  try:
    id = p.client.ask("POST", "/v1/systemone", body)
  except LlmError:
    p.backoff(tick, auth = false)
    return
  p.client.oracle.submit(id)
  if id == 0:
    return
  p.pendingId = id
  p.askedAt = epochTime()
  inc p.stats.requests

proc pilotNoise*(p: Practice, chance: float, seed: int64 = 0) =
  ## Makes a pilot execute a random eligible option instead of its cue
  ## with probability `chance` per window (deterministic given `seed`).
  p.noise = int32(clamp(chance, 0.0, 1.0) * 1000)
  p.noiseRng = initRand(if seed != 0: seed else: 0x5EED'i64 + int64(p.slot))

proc offered*(p: Practice): seq[PracticeOption] =
  ## The options local guidance drafted for the current tick.
  p.options

proc pickCue(p: Practice, tick: int32) =
  ## Jev's answer when fresh, eligible, and confident; otherwise the first
  ## local option. Urgent local cues always win. A still-eligible cue is
  ## held briefly so the panel does not flicker.
  let usable = p.answerTick >= 0 and tick - p.answerTick <= AnswerMaxAgeTicks
  if p.options.len == 0:
    p.cue = PracticeCue(confidence: -1)
    p.plan = PracticeCue(confidence: -1)
    return
  var cue = PracticeCue(option: p.options[0], source: "local", confidence: -1)
  if p.forced.len > 0 and not p.forcedDone:
    # A counterfactual rollout executes exactly the option under test,
    # urgent local cues included or not; "none" issues no order.
    if p.options.has(p.forced):
      cue = PracticeCue(option: p.options.find(p.forced), source: "forced",
        confidence: -1)
    else:
      cue = PracticeCue(confidence: -1)
    p.cue = cue
    p.plan = PracticeCue(confidence: -1)
    if p.hasOpen:
      p.open.cueId = cue.option.id
      p.open.cueSource = cue.source
    return
  if usable and p.options.has(p.answerAction):
    let option = p.options.find(p.answerAction)
    let needed = thresholdFor(option)
    if thresholds.loaded:
      # Fitted: the answer is the cue only above its class threshold.
      if p.answerConfidence >= needed:
        cue = PracticeCue(option: option, source: "jev",
          confidence: p.answerConfidence)
    elif p.answerConfidence >= ConfidenceFloor:
      cue = PracticeCue(option: option, source: "jev",
        confidence: p.answerConfidence,
        tentative: p.answerConfidence < needed)
  var urgent = false
  for item in p.options:
    if item.urgent:
      cue = PracticeCue(option: item, source: "local", confidence: -1)
      urgent = true
      break
  # A model answer newer than the held cue always replaces it: the hold
  # only smooths local guidance (and a pilot must act on each answer).
  let freshAnswer = cue.source == "jev" and p.answerTick > p.heldTick
  if not urgent and not freshAnswer and p.heldId.len > 0 and
      p.options.has(p.heldId) and tick - p.heldTick < HoldTicks and
      (p.heldSource == "local" or usable) and cue.option.id != p.heldId:
    let held = p.options.find(p.heldId)
    if not held.urgent:
      cue = PracticeCue(option: held, source: p.heldSource,
        confidence: if p.heldSource == "jev": p.answerConfidence else: -1,
        tentative: p.heldSource == "jev" and not thresholds.loaded and
          p.answerConfidence < thresholdFor(held))
  if cue.option.id != p.heldId or cue.source != p.heldSource:
    p.heldId = cue.option.id
    p.heldSource = cue.source
    p.heldTick = tick
  p.cue = cue
  # The sample keeps the cue the window closed with, except for a pilot,
  # whose sample keeps the cue it acted on.
  if p.hasOpen and p.open.jev != nil and not (p.acts and p.open.actTick > 0):
    p.open.cueId = cue.option.id
    p.open.cueSource = cue.source
  var plan = PracticeCue(confidence: -1)
  if p.strategies.len > 0:
    plan = PracticeCue(option: p.strategies[0], source: "local", confidence: -1)
    if usable and p.answerStrategyConfidence >= strategyThreshold() and
        p.strategies.has(p.answerStrategy):
      plan = PracticeCue(option: p.strategies.find(p.answerStrategy),
        source: "jev", confidence: p.answerStrategyConfidence)
  p.plan = plan

proc classifyWalk(p: Practice, world: World, x, z: int32): string =
  ## What a walk order means in the option vocabulary.
  let
    view = humanView(world, p.slot)
    me = view.me
    home = me.spawnTile
    tx = float(x)
    tz = float(z)
    mx = tileX(me.position)
    mz = tileZ(me.position)
  proc dist(ax, az, bx, bz: float): float =
    sqrt((ax - bx) * (ax - bx) + (az - bz) * (az - bz))
  let
    homeNow = dist(mx, mz, float(home.x), float(home.z))
    homeThen = dist(tx, tz, float(home.x), float(home.z))
  if hpPercent(me) < RecoverHpPercent and homeThen + 3 < homeNow:
    return if p.options.has("heal"): "heal" else: "retreat"
  if p.options.has("heal") and homeThen <= 2:
    return "heal"
  for ally in view.allies:
    let
      ax = tileX(ally.position)
      az = tileZ(ally.position)
    if dist(tx, tz, ax, az) + 3 < dist(mx, mz, ax, az) and
        p.options.has("regroup"):
      return "regroup"
  if p.options.has("scout"):
    return "scout"
  if p.options.has("wait_hook") and not p.options.has("reposition"):
    return "wait_hook"
  "reposition"

proc classifyAim(p: Practice, world: World, x, z: float, grapple: bool): string =
  ## Which visible butcher a hook was aimed at, in option terms.
  let view = humanView(world, p.slot)
  var
    best = 0'i32
    bestTeam = -1
    bestDist = AimMatchTiles
  for pudge in view.pudges:
    if pudge.state != Alive or pudge.id == view.me.id:
      continue
    let d = sqrt((tileX(pudge.position) - x) * (tileX(pudge.position) - x) +
      (tileZ(pudge.position) - z) * (tileZ(pudge.position) - z))
    if d < bestDist:
      bestDist = d
      best = pudge.id
      bestTeam = pudge.team.ord
  if grapple:
    return "grapple"
  if best == 0:
    return "hook_blind"
  if bestTeam == view.team:
    return "rescue_" & $best
  if p.options.has("follow_" & $best):
    return "follow_" & $best
  "hook_" & $best

proc labelAction(p: Practice, world: World, kind: uint8, a, b: int32): string =
  ## A tape action in option terms (the same vocabulary as a person's
  ## intents). Empty for actions that carry no decision.
  case kind
  of ActionHookTo:
    p.classifyAim(world, float(a), float(b), false)
  of ActionHookToFine:
    p.classifyAim(world, float(a) / 256, float(b) / 256, false)
  of ActionGrappleTo:
    p.classifyAim(world, float(a), float(b), true)
  of ActionGrappleToFine:
    p.classifyAim(world, float(a) / 256, float(b) / 256, true)
  of ActionBlinkTo, ActionBlinkToFine:
    if p.options.has("dodge"): "dodge" elif p.options.has("blink"): "blink"
    else: "blink"
  of ActionBuyUpgrade, ActionBuyPower:
    "upgrade"
  of ActionAttackTarget:
    if a == 0: ""
    elif p.options.has("attack_" & $a): "attack_" & $a
    else: "attack"
  of ActionRotToggle:
    "rot"
  of ActionStop:
    "hold"
  else:
    ""

const ActionNames = ["", "walkTo", "hookTo", "attackTarget", "buyUpgrade",
  "stop", "ping", "takeOver", "hookToFine", "grappleTo", "grappleToFine",
  "buyPower", "blinkTo", "blinkToFine", "placeWall", "placeMine", "cheat",
  "rotToggle", "placeWard"]

proc consumeTapeActions(p: Practice, game: Game, tick: int32) =
  ## Shadow seats: reads the actions the seat's script recorded on the
  ## tape since the last tick and labels the open window with them, as
  ## `consumeIntents` does for a person.
  if game.recorder == nil:
    return
  let
    actions = game.recorder.data.actions
    me = game.world.pudges[p.slot]
  while p.actionIndex < actions.len:
    let item = actions[p.actionIndex]
    inc p.actionIndex
    if item.pudgeId != me.id:
      continue
    let name = if int(item.kind) < ActionNames.len: ActionNames[item.kind]
      else: $item.kind
    let record = %*{"tick": int(item.tick), "at_ms": epochMs(),
      "kind": name, "a": item.first, "b": item.second, "accepted": true}
    p.intentsFile.writeLine(record)
    if not p.hasOpen or p.open.humanId.len > 0:
      continue
    if item.kind == ActionWalkTo:
      p.open.walkId = p.classifyWalk(game.world, item.first, item.second)
      if p.open.humanIntent == nil:
        p.open.humanIntent = record
      continue
    var id = p.labelAction(game.world, item.kind, item.first, item.second)
    if id.startsWith("hook_") and not p.options.has(id) and
        p.options.has("hook_blind"):
      id = "hook_blind"
    # The tape keeps every attempt, including hooks thrown on cooldown and
    # buys without a point. Only an offered option is a decision the
    # script could act on, so the rest are no-ops to the label.
    if id.len == 0 or not p.options.has(id):
      continue
    if id notin p.open.optionIds:
      # The window opened before this became possible (the hook came
      # back, a point landed). Label the state the script decided in: the
      # previous tick, whose options these are; this tick already carried
      # the action out.
      p.openSample(game.world, p.prevTick, "action", p.prevObs)
    p.open.humanId = id
    p.open.humanIntent = record
    p.closeSample(tick)

proc tapeDecision*(game: Game, slot: int, base: World, fromIndex = 0): string =
  ## The first decision a seat recorded on the game's tape since
  ## `fromIndex`, in option terms against the options eligible at `base`
  ## (the state a window opened in). As for shadowed seats, an attempt the
  ## state did not offer is a no-op; a walk alone reads as its movement
  ## class; empty when the seat recorded nothing. This is how a script
  ## answers "what would you do here?" for any recorded window.
  if game.recorder == nil or slot < 0 or slot >= base.pudges.len:
    return ""
  var p = Practice(slot: slot)
  (p.options, p.strategies) = practiceOptions(base, slot)
  let me = base.pudges[slot]
  var walk = ""
  let actions = game.recorder.data.actions
  for i in max(fromIndex, 0) ..< actions.len:
    let item = actions[i]
    if item.pudgeId != me.id:
      continue
    if item.kind == ActionWalkTo:
      if walk.len == 0:
        walk = p.classifyWalk(base, item.first, item.second)
      continue
    var id = p.labelAction(base, item.kind, item.first, item.second)
    if id.startsWith("hook_") and not p.options.has(id) and
        p.options.has("hook_blind"):
      id = "hook_blind"
    if id.len > 0 and p.options.has(id):
      return id
  if walk.len > 0:
    if p.options.has(walk):
      return walk
    for id in ["reposition", "wait_hook", "scout", "regroup"]:
      if p.options.has(id):
        return id
    return "none"
  ""

proc consumeIntents(p: Practice, game: Game, tick: int32) =
  ## Reads the sim's drained intents for the human seat exactly once each.
  let results = game.intentResults
  var atTick = 0
  for i, item in results:
    if item.tick < p.seenTick:
      continue
    if item.tick == p.seenTick:
      inc atTick
      if atTick <= p.seenAtTick:
        continue
    if int(item.slot) != p.slot:
      continue
    let intent = %*{"tick": item.tick, "at_ms": epochMs(),
      "kind": $item.kind, "a": item.a, "b": item.b,
      "accepted": item.accepted}
    p.intentsFile.writeLine(intent)
    if not item.accepted or not p.hasOpen or p.open.humanId.len > 0:
      continue
    var id = ""
    case item.kind
    of IntentHook, IntentGrapple:
      id = p.classifyAim(game.world, float(item.a), float(item.b),
        item.kind == IntentGrapple)
    of IntentHookFine, IntentGrappleFine:
      id = p.classifyAim(game.world, float(item.a) / 256, float(item.b) / 256,
        item.kind == IntentGrappleFine)
    of IntentBlink, IntentBlinkFine:
      id = if p.options.has("dodge"): "dodge" else: "blink"
    of IntentBuy, IntentBuyPower:
      id = "upgrade"
    of IntentAttack:
      id = if p.options.has("attack_" & $item.a): "attack_" & $item.a
        else: "attack"
    of IntentRot:
      id = "rot"
    of IntentStop:
      id = "hold"
    of IntentWalk:
      p.open.walkId = p.classifyWalk(game.world, item.a, item.b)
      if p.open.humanIntent == nil:
        p.open.humanIntent = intent
      continue
    else:
      continue
    p.open.humanId = id
    p.open.humanIntent = intent
    p.closeSample(tick)
  var newest = p.seenTick
  var count = 0
  for item in results:
    if item.tick > newest:
      newest = item.tick
      count = 0
    if item.tick == newest:
      inc count
  p.seenTick = newest
  p.seenAtTick = count

proc trackOutcomes(p: Practice, world: World, me: Pudge) =
  ## Running totals for the summary, and the events that open windows.
  let alive = me.state == Alive
  if p.prevAlive and not alive:
    inc p.stats.deaths
    p.pendingTrigger = "death"
  elif alive and not p.prevAlive and p.tracked:
    p.pendingTrigger = "respawn"
  p.prevAlive = alive
  if me.kills > p.prevKills:
    p.stats.kills += me.kills - p.prevKills
  p.prevKills = me.kills
  if me.hooksThrown > p.prevThrown:
    p.stats.hooksThrown += me.hooksThrown - p.prevThrown
    p.pendingTrigger = "hook_thrown"
  p.prevThrown = me.hooksThrown
  let hooked = me.hookedBy != 0
  if hooked and not p.prevHooked:
    p.pendingTrigger = "hooked"
  p.prevHooked = hooked
  var allyHooked = 0
  for other in world.pudges:
    if other.team == me.team and other.id != me.id and other.hookedBy != 0:
      inc allyHooked
  if allyHooked > p.prevAllyHooked:
    p.pendingTrigger = "ally_hooked"
  p.prevAllyHooked = allyHooked
  var contact = false
  for item in p.options:
    if item.id.startsWith("hook_") and item.id != "hook_blind":
      contact = true
      break
  if contact != p.prevContact and p.tracked:
    p.pendingTrigger = if contact: "contact" else: "contact_lost"
  p.prevContact = contact
  p.tracked = true
  if me.hooksLanded > p.prevLanded:
    p.stats.hooksLanded += me.hooksLanded - p.prevLanded
  p.prevLanded = me.hooksLanded

proc finishOne(p: Practice, game: Game) =
  if p == nil or not p.enabled or p.finished:
    return
  p.finished = true
  let tick = if game != nil: game.world.tick else: 0'i32
  p.closeSample(tick)
  var summary = %*{
    "slot": p.slot, "actor": p.actor, "model": p.model,
    "endpoint": p.endpoint, "provider": p.provider, "status": p.status,
    "ticks": tick, "finished_ms": epochMs(),
    "samples": p.stats.samples, "compared": p.stats.compared,
    "agreed": p.stats.agreed,
    "hooks_thrown": p.stats.hooksThrown, "hooks_landed": p.stats.hooksLanded,
    "kills": p.stats.kills, "deaths": p.stats.deaths,
    "requests": p.stats.requests, "failures": p.stats.failures,
    "answers": p.stats.answers, "delegated": p.stats.delegated,
    "thresholds": (if thresholds.loaded: %thresholds.path else: newJNull())
  }
  if game != nil:
    summary["game_over"] = %game.world.gameOver
    summary["score"] = %*{"west": game.world.teamKills[WestTeam.ord],
                          "east": game.world.teamKills[EastTeam.ord]}
    if game.world.gameOver:
      summary["winner"] = %game.world.winner.ord
  if p.dir.len > 0:
    writeFile(p.dir / "summary.json", pretty(summary))
  if p.samplesFile != nil:
    p.samplesFile.close()
    p.samplesFile = nil
  if p.intentsFile != nil:
    p.intentsFile.close()
    p.intentsFile = nil
  if p.client != nil:
    p.client.close()
  p.status = "finished"
  p.hint = "Match complete. Start a new match to keep practicing."
  p.cue = PracticeCue(confidence: -1)
  p.plan = PracticeCue(confidence: -1)

proc practiceFinish*(game: Game) =
  ## Closes every open window and writes the summaries. Idempotent.
  finishOne(coach, game)
  for p in pilots:
    finishOne(p, game)

# --- pilots ----------------------------------------------------------------

proc pilotIntent*(p: Practice, world: World, tick: int32,
    option: PracticeOption, intent: var HumanIntent): bool =
  ## Translates one option into the intent a person would issue for it.
  ## Returns false for options that are advice only (respawn, hooked).
  let
    view = humanView(world, p.slot)
    me = view.me
    mx = tileX(me.position)
    mz = tileZ(me.position)
    west = view.team == WestTeam.ord
  intent = HumanIntent(slot: int32(p.slot))
  proc lipX(z: float): float =
    let row = int(clamp(z, 0.0, float(GridTiles - 1)))
    if west: float(RiverCenterX - riverHalfWidthAt(row) - 1)
    else: float(RiverCenterX + riverHalfWidthAt(row) + 1)
  template walkTo(x, z: float) =
    intent.kind = IntentWalk
    intent.a = int32(clamp(x, 0.0, float(GridTiles - 1)))
    intent.b = int32(clamp(z, 0.0, float(GridTiles - 1)))
  template hookAt(target: Pudge) =
    # Aim where the hook meets the target, in 1/256 tiles.
    let aim = hookSolution(world, p.slot, target)
    intent.kind = IntentHookFine
    intent.a = int32(clamp(aim.aimX, 0.0, float(GridTiles - 1)) * 256.0)
    intent.b = int32(clamp(aim.aimZ, 0.0, float(GridTiles - 1)) * 256.0)
  let id = option.id
  if id == "hook_blind":
    let (ax, az) = speculativeAim(p.sighting, tick, west, mz)
    intent.kind = IntentHookFine
    intent.a = int32(clamp(ax, 0.0, float(GridTiles - 1)) * 256.0)
    intent.b = int32(clamp(az, 0.0, float(GridTiles - 1)) * 256.0)
    return true
  if id.startsWith("hook_") or id.startsWith("follow_") or
      id.startsWith("rescue_"):
    for pudge in view.pudges:
      if pudge.id == option.targetId and pudge.state == Alive:
        hookAt(pudge)
        return true
    return false
  if id.startsWith("attack_"):
    intent.kind = IntentAttack
    intent.a = option.targetId
    return true
  case id
  of "rot":
    intent.kind = IntentRot
    return true
  of "blink":
    # Away from the nearest enemy, toward home when none is visible.
    var ax = float(me.spawnTile.x)
    var az = float(me.spawnTile.z)
    var nearest = 1.0e9
    for enemy in view.enemies:
      let d = tiles(me.position, enemy.position)
      if d < nearest:
        nearest = d
        ax = mx - (tileX(enemy.position) - mx)
        az = mz - (tileZ(enemy.position) - mz)
    let
      dx = ax - mx
      dz = az - mz
      length = max(1.0, sqrt(dx * dx + dz * dz))
      reach = float(BlinkRangeTiles) * 0.8
    intent.kind = IntentBlink
    intent.a = int32(clamp(mx + dx / length * reach, 0.0, float(GridTiles - 1)))
    intent.b = int32(clamp(mz + dz / length * reach, 0.0, float(GridTiles - 1)))
    return true
  of "dodge":
    # Step off the nearest flying enemy hook's line.
    for hook in view.hooks:
      if hook.team.ord != view.team and hook.phase == HookFlying:
        let
          hx = tileX(hook.position)
          hz = tileZ(hook.position)
          dx = mx - hx
          dz = mz - hz
          length = max(1.0, sqrt(dx * dx + dz * dz))
          side = if (tick div 64) mod 2 == 0: 1.0 else: -1.0
        walkTo(mx - dz / length * 4 * side, mz + dx / length * 4 * side)
        return true
    return false
  of "retreat":
    let home = me.spawnTile
    walkTo(float(home.x), float(home.z))
    return true
  of "heal":
    intent.kind = IntentStop
    return true
  of "regroup":
    var best: Pudge
    var bestDist = 1.0e9
    for ally in view.allies:
      let d = tiles(me.position, ally.position)
      if d < bestDist:
        bestDist = d
        best = ally
    if bestDist >= 1.0e9:
      return false
    let
      ax = tileX(best.position)
      az = tileZ(best.position)
      length = max(1.0, bestDist)
    # Close to about 12 tiles while keeping a separate lane.
    walkTo(ax + (mx - ax) / length * 12, az + (mz - az) / length * 12)
    return true
  of "wait_hook", "reposition":
    let drift = if (tick div 64) mod 2 == 0: 6.0 else: -6.0
    walkTo(lipX(mz + drift), mz + drift)
    return true
  of "scout":
    let toward = if mz < float(IslandCenterZ): 10.0 else: -10.0
    walkTo(lipX(mz + toward), mz + toward)
    return true
  of "upgrade":
    var kind = UpgradeDamage
    for candidate in UpgradeKind:
      if me.upgrades[candidate] < me.upgrades[kind]:
        kind = candidate
    intent.kind = IntentBuy
    intent.a = int32(kind.ord)
    return true
  else:
    return false

proc pilotAct(p: Practice, game: Game, tick: int32) =
  ## Executes the current cue once per window, as soon as the model has
  ## answered (or local guidance is all there is).
  if not p.acts or not p.actPending or not p.hasOpen:
    return
  if p.client != nil and p.pendingId != 0:
    if not p.sync:
      return
    # Headless self-play: wait for this window's answer (bounded by the
    # request timeout, after which local guidance acts).
    let started = getMonoTime()
    while p.pendingId != 0 and
        (getMonoTime() - started).inMilliseconds <= p.timeoutMs + 250:
      sleep(2)
      p.client.beginTick(tick)
      p.pollJev(tick)
    if p.pendingId != 0:
      return
    p.pickCue(tick)
  p.actPending = false
  let forcedNow = p.forced.len > 0 and not p.forcedDone
  if forcedNow:
    p.forcedDone = true
  if p.cue.source.len == 0:
    return
  var chosen = p.cue.option
  var source = p.cue.source
  if p.noise > 0 and not forcedNow and p.options.len > 1 and
      p.noiseRng.rand(999) < p.noise:
    # A deliberate mistake: any eligible option but the cue.
    var others: seq[PracticeOption]
    for item in p.options:
      if item.id != chosen.id:
        others.add item
    chosen = others[p.noiseRng.rand(others.len - 1)]
    source = "noise"
  p.open.cueId = chosen.id
  p.open.cueSource = source
  p.open.actTick = tick
  var intent: HumanIntent
  if p.pilotIntent(game.world, tick, chosen, intent):
    queueIntent(game, intent)
    if forcedNow:
      p.forcedQueued = true

proc tickOne(p: Practice, game: Game) =
  if p == nil or not p.enabled or p.finished or game == nil:
    return
  if game.historyPlayback or p.slot < 0 or p.slot >= game.world.pudges.len:
    return
  let
    world = game.world
    tick = world.tick
    me = world.pudges[p.slot]
  if p.client != nil:
    p.client.beginTick(tick)
  p.sighting.noteSighting(world, p.slot)
  if p.actor == "bot":
    p.consumeTapeActions(game, tick)
  else:
    p.consumeIntents(game, tick)
  if world.gameOver:
    p.trackOutcomes(world, me)
    practiceFinish(game)
    return
  (p.options, p.strategies) = practiceOptions(world, p.slot)
  if p.actor == "bot":
    p.prevObs = observationJson(world, p.slot)
    p.prevTick = tick
  p.trackOutcomes(world, me)
  p.pollJev(tick)
  if p.hasOpen and tick - p.open.tick >= AskEveryTicks:
    p.closeSample(tick)
  var trigger = ""
  if tick - p.lastAskTick >= AskEveryTicks:
    trigger = "periodic"
  elif askEvents and p.pendingTrigger.len > 0 and
      tick - p.lastAskTick >= AskMinGapTicks:
    trigger = p.pendingTrigger
  if trigger.len > 0:
    p.lastAskTick = tick
    p.pendingTrigger = ""
    p.openSample(world, tick, trigger)
    p.askJev(world, tick)
  p.pickCue(tick)
  p.pilotAct(game, tick)

proc practiceTick*(game: Game) =
  ## Runs after each simulated tick of a live match: the human coach,
  ## then every pilot.
  tickOne(coach, game)
  for p in pilots:
    tickOne(p, game)
  if game != nil and game.world.gameOver:
    pilotsEnd()

proc rolloutPilot*(game: Game, slot: int, forced = "",
    sighting = Sighting()): Practice =
  ## A silent pilot for counterfactual rollouts: no model, no trace files,
  ## local guidance after the forced first option. `sighting` carries what
  ## the seat remembered at the branch, so speculative hooks aim as they
  ## would have. It is not registered with the match; drive it with
  ## `rolloutTick`.
  result = Practice(enabled: true, visible: false, slot: slot,
    actor: "rollout", acts: true, status: "local", provider: "local",
    model: "local", forced: forced, sighting: sighting)
  let me = game.world.pudges[slot]
  result.prevAlive = me.state == Alive
  result.prevKills = me.kills
  result.prevThrown = me.hooksThrown
  result.prevLanded = me.hooksLanded
  result.seenTick = -1
  result.answerTick = -1
  result.lastAskTick = -AskEveryTicks
  result.cue.confidence = -1
  result.plan.confidence = -1

proc rolloutTick*(p: Practice, game: Game) =
  ## One tick of a rollout pilot, after `tickWorld`.
  tickOne(p, game)

proc practiceToggle*() =
  if coach != nil:
    coach.visible = not coach.visible
  for p in pilots:
    p.visible = not p.visible

proc practiceActive*(): bool =
  ## Whether any coach or pilot is running on this match.
  (coach != nil and coach.enabled and not coach.finished) or
    pilots.len > 0

proc hudPractice*(): Practice =
  ## What the HUD plate shows: the human coach, else the first pilot.
  if coach != nil and coach.enabled:
    return coach
  for p in pilots:
    if p.enabled:
      return p
  nil

proc agreementPercent*(stats: PracticeStats): int =
  if stats.compared <= 0: -1
  else: int(100 * stats.agreed div stats.compared)
