## Nonblocking tactical advice. BASIC remains the only action executor.
import std/[json, monotimes, os, strutils, tables, times]
import polyworld/[llms, oracles]
import content, practice, sim, tactics

const TacticalQuestions* = ["target", "position", "aggression"]
const TacticalSchema* = "hybrid-tactics-v2"

type
  TacticalChoices* = array[3, seq[string]]
  Hybrid* = ref object
    game: Game
    slot*: int
    dir*: string
    client: LlmClient
    model: string
    log: File
    pending, observed, observedDeaths, lastAsk: int32
    delay: int32
    started: MonoTime
    request, received: JsonNode
    choices: TacticalChoices
    schedule: seq[JsonNode]
    scheduleIndex: int
    requests*, accepted*, rejected*, failures*, expired*: int
    nondefault*, settingsChanges*: int
    finished: bool
    shadow: bool
    startedMs: int64
    clockStarted: MonoTime
    history: seq[JsonNode]

var hybrids*: seq[Hybrid]

proc tacticalChoices*(world: World, slot: int): TacticalChoices =
  result[0] = @["default"]
  let obs = observationJson(world, slot)
  for enemy in obs["visible"]["pudges"]:
    let id = int32(enemy["id"].getInt)
    if visibleEnemy(world, slot, id): result[0].add "enemy_" & $id
  result[1] = @["default", "north", "center", "south"]
  result[2] = @["default", "cautious", "pressure"]

proc tacticalRequest*(oracle: Oracle, game: Game, slot: int, model: string,
    choices: TacticalChoices, history: seq[JsonNode] = @[]): string =
  discard oracle.state("game", %"Pudge Wars. BASIC already plays every tick: aims hooks, fights in melee, dodges, retreats, buys, and rescues. Choose temporary tactical preferences, not immediate actions.")
  discard oracle.state("observation", observationJson(game.world, slot))
  discard oracle.state("recent_history", %history)
  discard oracle.state("contract", %"Advice arrives after a delay and expires four seconds after this observation. Default means original BASIC behavior. Emergencies, melee, recovery and rune collection keep their local priorities. Choose default when there is no clear improvement.")
  let vm = game.heroVms[slot]
  if vm != nil: game.validateTactics(slot)
  discard oracle.state("current_preferences", %*{
    "target_id": (if vm == nil: 0 else: vm.tacticTarget),
    "lane_y": (if vm == nil: 0 else: vm.tacticLane),
    "aggression": (if vm == nil: 0 else: vm.tacticAggression),
    "expires_tick": (if vm == nil: 0 else: vm.tacticUntil)})
  for index, name in TacticalQuestions:
    discard oracle.question(name, int32(ChoiceQuestion.ord),
      case index
      of 0: "Which visible enemy should BASIC prefer for the next exchanges? Immediate melee targets keep priority."
      of 1: "Which lane should BASIC occupy when no higher-priority movement is needed? North y=32, center y=64, south y=96."
      else: "Choose spacing and recovery: default holds 16 tiles behind the lip and retreats below 40% HP; cautious holds 20 and retreats below 55%; pressure holds 12 and keeps the 40% retreat floor.")
    for choice in choices[index]:
      discard oracle.criterion(name, choice,
        if choice == "default": "Keep the original BASIC behavior for this preference."
        else: choice)
  oracle.requestBody(model)

proc write(h: Hybrid, record: JsonNode) =
  record["at_ms"] = %(h.startedMs + (getMonoTime() - h.clockStarted).inMilliseconds)
  record["controller_schema"] = %TacticalSchema
  h.log.writeLine($record)
  h.log.flushFile()

proc proposalSettings*(proposal: JsonNode): tuple[target, lane, aggression: int32] =
  let target = proposal{"target"}.getStr()
  if target != "default":
    if not target.startsWith("enemy_"): raise newException(ValueError, "invalid target")
    result.target = int32(parseInt(target[6 .. ^1]))
    if result.target <= 0: raise newException(ValueError, "invalid target")
  case proposal{"position"}.getStr()
  of "default": discard
  of "north": result.lane = 32
  of "center": result.lane = 64
  of "south": result.lane = 96
  else: raise newException(ValueError, "invalid position")
  case proposal{"aggression"}.getStr()
  of "default": discard
  of "cautious": result.aggression = -1
  of "pressure": result.aggression = 1
  else: raise newException(ValueError, "invalid aggression")

proc apply(h: Hybrid, proposal: JsonNode, observed, deaths: int32): string =
  try:
    let settings = proposalSettings(proposal)
    let vm = h.game.heroVms[h.slot]
    let changed = (vm.tacticTarget, vm.tacticLane, vm.tacticAggression) != settings
    result = applyTactics(h.game, h.slot, observed, deaths,
      settings.target, settings.lane, settings.aggression)
    if result.len == 0:
      if settings != (0'i32, 0'i32, 0'i32): inc h.nondefault
      if changed: inc h.settingsChanges
  except ValueError:
    result = "invalid_settings"
  if result.len == 0: inc h.accepted
  else:
    inc h.rejected
    if result == "expired": inc h.expired

proc recordAnswer(h: Hybrid, reason: string) =
  h.write(%*{"schema_version": 1, "observed_tick": h.observed,
    "observed_deaths": h.observedDeaths, "apply_tick": h.game.world.tick,
    "request": h.request,
    "result": (if h.received == nil: newJNull() else: h.received), "reason": reason,
    "accepted": reason.len == 0})
  h.pending = 0
  h.received = nil

proc poll(h: Hybrid) =
  if h.client == nil or h.pending == 0: return
  let tick = h.game.world.tick
  h.client.beginTick(tick)
  if h.received == nil:
    let status = h.client.oracle.poll(h.pending)
    if status == 0: return
    if status < 0:
      inc h.failures
      h.recordAnswer("request_failed")
      return
    var proposal = newJObject()
    var answers = newJObject()
    var reason = ""
    for index, name in TacticalQuestions:
      let answer = h.client.oracle.answer(h.pending, name)
      if answer.value < 0 or answer.value >= h.choices[index].len:
        reason = "invalid_answer"
        continue
      let choice = h.choices[index][answer.value]
      proposal[name] = %choice
      var probabilities = newJObject()
      for label, probability in answer.probabilities:
        probabilities[label] = %(float(probability) / 1000)
      answers[name] = %*{"choice": choice, "confidence": float(answer.confidence) / 1000,
        "probabilities": probabilities}
      if choice != "default" and answer.confidence < 600 and reason.len == 0:
        reason = "low_confidence"
    h.received = %*{"proposal": proposal, "answers": answers,
      "received_tick": tick, "latency_ms": (getMonoTime() - h.started).inMilliseconds}
    if reason.len > 0:
      inc h.rejected
      h.recordAnswer(reason)
      return
  # A configurable minimum delay supports latency sensitivity tests. No wait.
  if tick < h.observed + h.delay: return
  let reason = h.apply(h.received["proposal"], h.observed, h.observedDeaths)
  h.recordAnswer(reason)

proc hybridTick*(h: Hybrid) =
  if h == nil or h.finished or h.game.historyPlayback or h.game.world.gameOver: return
  let game = h.game
  let tick = game.world.tick
  if game.heroVms[h.slot] != nil: game.validateTactics(h.slot)
  h.poll()
  while h.scheduleIndex < h.schedule.len and
      h.schedule[h.scheduleIndex]["apply_tick"].getInt <= tick:
    let item = h.schedule[h.scheduleIndex]
    let reason = h.apply(item, int32(item["observed_tick"].getInt),
      int32(item["observed_deaths"].getInt))
    h.write(%*{"source": "intervention", "proposal": item,
      "apply_tick": tick, "accepted": reason.len == 0, "reason": reason})
    inc h.scheduleIndex
  if game.world.pudges[h.slot].state != Alive or h.pending != 0 or
      tick - h.lastAsk < TickRate: return
  if h.client != nil:
    h.client.beginTick(tick)
    if h.client.ready != 0: return
  h.lastAsk = tick
  h.observed = tick
  h.observedDeaths = game.world.pudges[h.slot].deaths
  h.choices = tacticalChoices(game.world, h.slot)
  let oracle = if h.client == nil: newOracle() else: h.client.oracle
  let body = tacticalRequest(oracle, game, h.slot, h.model, h.choices, h.history)
  if body.len == 0: return
  h.request = parseJson(body)
  let obs = h.request["state"]["observation"]
  var enemies = newJArray()
  for enemy in obs["visible"]["pudges"]:
    if enemy["team"].getInt != obs["self"]["team"].getInt:
      enemies.add %*{"id": enemy["id"], "x": enemy["x"], "y": enemy["y"], "hp": enemy["hp"]}
  h.history.add %*{"tick": tick, "x": obs["self"]["x"], "y": obs["self"]["y"],
    "hp": obs["self"]["hp"], "score": obs["score"], "visible_enemies": enemies}
  if h.history.len > 3: h.history.delete(0)
  h.write(%*{"source": "observation", "observed_tick": tick,
    "observed_deaths": h.observedDeaths, "request": h.request})
  if h.client == nil: return
  h.started = getMonoTime()
  try:
    h.pending = h.client.ask("POST", "/v1/systemone", body)
    oracle.submit(h.pending)
    if h.pending > 0: inc h.requests
  except LlmError:
    oracle.submit(0)
    inc h.failures

proc hybridTick*(game: Game) =
  for h in hybrids:
    if h.game == game: h.hybridTick()

proc hybridFinish*(game: Game) =
  for h in hybrids:
    if h.game != game or h.finished: continue
    if h.pending != 0: h.recordAnswer("match_ended")
    let me = game.world.pudges[h.slot]
    writeFile(h.dir / "summary.json", pretty(%*{
      "requests": h.requests, "accepted": h.accepted, "rejected": h.rejected,
      "expired": h.expired, "failures": h.failures, "tick": game.world.tick,
      "finished_ms": h.startedMs + (getMonoTime() - h.clockStarted).inMilliseconds,
      "nondefault_applied": h.nondefault, "settings_changes": h.settingsChanges,
      "kills": me.kills, "deaths": me.deaths,
      "team_kills": game.world.teamKills[me.team.ord],
      "enemy_kills": game.world.teamKills[1 - me.team.ord]}))
    h.log.close()
    h.finished = true
    # Any HTTP cleanup happens after play, never inside the tick loop.
    h.client.close()

proc hybridReset*() =
  for h in hybrids:
    hybridFinish(h.game)
  hybrids.setLen(0)

proc hybridBegin*(game: Game, slot: int, matchDir: string,
    endpoint = "none", model = "", delay = 0'i32, planPath = "", shadow = false): Hybrid =
  if slot < 0 or slot >= game.heroVms.len or
      (not shadow and (game.heroVms[slot] == nil or not game.heroVms[slot].tactical)):
    raise newException(ValueError, "hybrid seat needs an adapted BASIC policy")
  result = Hybrid(game: game, slot: slot,
    dir: matchDir / ((if shadow: "tactical-shadow-" else: "hybrid-") & $slot),
    shadow: shadow, startedMs: int64(epochTime() * 1000), clockStarted: getMonoTime(),
    delay: delay, lastAsk: -TickRate)
  let config = coachConfig(endpoint, model)
  result.model = config.model
  if shadow and planPath.len > 0:
    raise newException(ValueError, "tactical shadow recording cannot execute plans")
  if planPath.len > 0:
    let items = parseFile(planPath)
    if items.kind != JArray: raise newException(ValueError, "hybrid plan must be an array")
    var previous = -1
    for item in items:
      for key in ["observed_tick", "observed_deaths", "apply_tick"]:
        if item{key} == nil or item[key].kind != JInt or item[key].getInt < 0:
          raise newException(ValueError, "hybrid plan requires nonnegative integer " & key)
      discard proposalSettings(item)
      let at = item["apply_tick"].getInt
      if at < previous or at < item["observed_tick"].getInt:
        raise newException(ValueError, "hybrid plan must be ordered and cannot precede its observation")
      previous = at
      result.schedule.add item
  elif not shadow and config.endpoint.len > 0:
    if config.provider != "local" and config.key.len == 0:
      raise newException(ValueError, "hybrid coach has no configured API key; use --coach none for BASIC alone")
    result.client = newLlmClient(slot, LlmConfig(baseUrl: config.endpoint,
      key: config.key, oracleModel: config.model, interval: 1, timeoutMs: 10000))
  createDir(result.dir)
  result.log = open(result.dir / "decisions.jsonl", fmWrite)
  writeFile(result.dir / "match.json", pretty(%*{
    "schema_version": 2, "controller_schema": TacticalSchema,
    "actor": (if shadow: "tactical_shadow" else: "hybrid"),
    "executor": (if slot in game.humanSlots: "human" else: "basic"),
    "started_ms": result.startedMs,
    "policy_fingerprint": (if game.heroVms[slot] == nil: "human:no-basic-vm" else: game.heroVms[slot].policyFingerprint),
    "bot_every": game.botEvery, "slot": slot, "map_seed": game.map.seed,
    "model": config.model, "endpoint": config.endpoint, "delay_ticks": delay,
    "lifetime_ticks": TacticalLifetime, "plan_path": planPath,
    "connected": result.client != nil, "pudges": game.world.pudges.len}))
  hybrids.add result
