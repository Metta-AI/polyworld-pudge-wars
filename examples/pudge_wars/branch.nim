## Counterfactual rollouts for decision windows: the answer key.
##
## A recorded match is replayed to the tick a decision window opened, the
## world is cloned, every other seat is handed to the stock bot, and the
## traced seat executes one option under test before local guidance
## resumes. A short horizon later the seat's and both teams' deltas are
## reported. Scoring every eligible option of a window this way gives a
## DecisionGym-style key: which choices were acceptable at that state,
## including states the player only reached after a mistake.
##
## The continuation after the branch is bots, not the people who were
## actually there, so a key is only as faithful as the bots are to them.
## Rollouts are deterministic given the tape, the slot, the option and
## the seed; `seeds > 1` reseeds the world's stream for each extra run.

import
  std/[json, os, strutils],
  polyworld/[cli, rngs],
  bots, content, practice, replays, sim

type
  BranchOptions* = object
    path*: string
      ## Replay tape of the recorded match (`--branch PATH`).
    slot*: int
      ## Roster seat whose windows are scored.
    ticks*: seq[int32]
      ## Window open ticks to branch at, ascending.
    options*: seq[string]
      ## Option ids to score; empty scores every eligible one plus none.
    horizon*: int32
      ## Ticks each rollout runs after the branch.
    seeds*: int
      ## Rollouts per option with different world streams (>= 1).
    botPath*: string
      ## Script that drives every other seat after the branch.
    teachers*: seq[string]
      ## Scripts asked what they would do at each window
      ## (`--branch-teachers A,B`); one `teacher` row each.
    outPath*: string
      ## JSONL output path; empty prints to stdout.

  SeatSnapshot = object
    hp, maxHp, kills, deaths, hooksThrown, hooksLanded, gold: int32
    alive: bool
    teamKills: array[2, int32]

const
  DefaultHorizonTicks* = 5 * TickRate
  NoneOption* = "none"
  TeacherTicks* = 8'i32
    ## Ticks a teacher script gets to commit to a decision at a window.

proc cloneWorld*(world: World): World =
  ## An independent copy: every field of the simulation is a value.
  new result
  result[] = world[]

proc snapshot(world: World, slot: int): SeatSnapshot =
  let me = world.pudges[slot]
  SeatSnapshot(hp: me.hp, maxHp: me.maxHp, kills: me.kills,
    deaths: me.deaths, hooksThrown: me.hooksThrown,
    hooksLanded: me.hooksLanded, gold: me.gold, alive: me.state == Alive,
    teamKills: world.teamKills)

proc rolloutGame(source: Game, world: World, slot: int,
    botPath: string): Game =
  ## A live game over the cloned world: the traced seat takes intents,
  ## every other seat runs `botPath`.
  let total = world.pudges.len
  result = Game(world: world, map: source.map,
    maximumTicks: source.maximumTicks, botEvery: max(source.botEvery, 1'i32),
    botAimNoise: max(source.botAimNoise, 0'i32),
    botSpeech: newSeq[BotSpeech](total), humanSlots: @[slot])
  loadBots(result, [BotGroup(path: botPath, count: total - 1)])

proc rollout*(source: Game, base: World, slot: int, option: string,
    horizon: int32, seed: int, botPath: string,
    sighting = Sighting()): JsonNode =
  ## Runs one counterfactual from `base` and reports the deltas.
  let world = cloneWorld(base)
  if seed > 0:
    world.rng = initRng(source.map.seed, salt = uint64(seed) * 0x9E3779B97F4A7C15'u64)
  let game = rolloutGame(source, world, slot, botPath)
  let pilot = rolloutPilot(game, slot, forced = option, sighting = sighting)
  let before = snapshot(world, slot)
  var steps = 0'i32
  while steps < horizon and not world.gameOver:
    tickWorld(game, proc() = runBotDecisions(game))
    rolloutTick(pilot, game)
    inc steps
  closeBotServices(game)
  let
    after = snapshot(world, slot)
    team = world.pudges[slot].team.ord
    enemy = 1 - team
  result = %*{
    "tick": base.tick, "slot": slot, "option": option, "seed": seed,
    "horizon": steps,
    "queued": pilot.forcedQueued,
    "game_over": world.gameOver,
    "hp_before": before.hp, "hp_after": after.hp, "max_hp": after.maxHp,
    "alive_before": before.alive, "alive_after": after.alive,
    "kills": after.kills - before.kills,
    "deaths": after.deaths - before.deaths,
    "hooks_thrown": after.hooksThrown - before.hooksThrown,
    "hooks_landed": after.hooksLanded - before.hooksLanded,
    "gold": after.gold - before.gold,
    "team_kills": after.teamKills[team] - before.teamKills[team],
    "enemy_kills": after.teamKills[enemy] - before.teamKills[enemy]
  }
  if world.gameOver:
    result["won"] = %(world.winner.ord == team)

proc teacherName*(path: string): string =
  ## "players/sniper.bas" is the teacher "sniper".
  path.splitFile.name

proc teacherLabel*(source: Game, base: World, slot: int,
    teacherPath, botPath: string): string =
  ## What a script would do at this state: on a clone with its own tape,
  ## the window's seat runs `teacherPath` and every other seat `botPath`
  ## for a few ticks; the first decision the seat records, read against
  ## the options eligible at `base`, is the label. Scripts keep little
  ## state between ticks, so a cold start here is close to their live
  ## decision. Empty when the script recorded nothing.
  let world = cloneWorld(base)
  let total = world.pudges.len
  let game = Game(world: world, map: source.map,
    maximumTicks: source.maximumTicks, botEvery: 1, botAimNoise: 0,
    botSpeech: newSeq[BotSpeech](total))
  game.recorder = initReplayRecorder(
    currentSetup(game, uint32(max(source.maximumTicks, 1'i32))))
  var groups: seq[BotGroup]
  for i in 0 ..< total:
    groups.add BotGroup(path: (if i == slot: teacherPath else: botPath),
      count: 1)
  loadBots(game, groups)
  var steps = 0'i32
  while steps < TeacherTicks and not world.gameOver:
    tickWorld(game, proc() = runBotDecisions(game))
    inc steps
    result = tapeDecision(game, slot, base)
    if result.len > 0 and result notin
        ["scout", "reposition", "wait_hook", "regroup", "none"]:
      break
  closeBotServices(game)

proc windowOptions*(world: World, slot: int): seq[string] =
  ## Every eligible option at this state, plus none.
  let (actions, _) = practiceOptions(world, slot)
  for item in actions:
    result.add item.id
  result.add NoneOption

proc scoreWindow*(source: Game, slot: int, options: seq[string],
    horizon: int32, seeds: int, botPath: string,
    teachers: seq[string] = @[], sighting = Sighting()): seq[JsonNode] =
  ## Scores one window at the replay game's current tick, then asks each
  ## teacher script what it would do there. The game is left untouched:
  ## every rollout runs on a clone.
  let base = cloneWorld(source.world)
  let ids = if options.len > 0: options else: windowOptions(base, slot)
  for id in ids:
    for seed in 0 ..< max(seeds, 1):
      result.add rollout(source, base, slot, id, horizon, seed, botPath,
        sighting)
  for path in teachers:
    result.add %*{"tick": base.tick, "slot": slot,
      "teacher": teacherName(path),
      "label": teacherLabel(source, base, slot, path, botPath)}

proc runBranch*(game: Game, opts: BranchOptions) =
  ## Replays `game` (a replay-mode game) to each requested tick and scores
  ## that window, writing one JSON line per rollout.
  doAssert game.replayMode, "branching needs a replay-mode game"
  var output: File
  let toFile = opts.outPath.len > 0
  if toFile:
    output = open(opts.outPath, fmWrite)
  defer:
    if toFile:
      output.close()
  var targets = opts.ticks
  var next = 0
  let last = if targets.len > 0: targets[^1] else: 0'i32
  var scored = 0
  # What the seat had seen by each tick, as its own pilot would remember it.
  var sighting: Sighting
  while next < targets.len and game.world.tick <= last:
    sighting.noteSighting(game.world, opts.slot)
    if game.world.tick == targets[next]:
      for row in scoreWindow(game, opts.slot, opts.options, opts.horizon,
          opts.seeds, opts.botPath, opts.teachers, sighting):
        if toFile:
          output.writeLine($row)
        else:
          echo $row
      inc scored
      inc next
      continue
    if game.world.tick >= game.replayData.hashes.len:
      break
    tickWorld(game, proc() = discard)
  stderr.writeLine("branch: scored " & $scored & " of " & $targets.len &
    " windows at tick " & $game.world.tick)

proc parseTicks*(text: string): seq[int32] =
  for part in text.split(','):
    let item = part.strip()
    if item.len > 0:
      result.add int32(parseInt(item))
