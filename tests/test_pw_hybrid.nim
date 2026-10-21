## Real simulator checks for asynchronous tactical control over BASIC.
import std/[json, os]
import polyworld/cli
import ../examples/pudge_wars/[bots, hybrid, maps, replays, sim, tactics]

let policy = currentSourcePath().parentDir.parentDir /
  "examples/pudge_wars/players/base.bas"
let root = getTempDir() / ("pw-hybrid-test-" & $getCurrentProcessId())
createDir(root)

proc fresh(adapted = true, teamSize = 1): Game =
  result = newGame(generateMap(41, teamSize), 1920, false, ReplayData())
  loadBots(result, [BotGroup(path: policy, count: result.world.pudges.len)],
    if adapted: @[0] else: @[])
  result.recorder = initReplayRecorder(currentSetup(result, 1920))

proc step(game: Game) =
  hybridTick(game)
  tickWorld(game, proc() = runBotDecisions(game))
  for vm in game.heroVms:
    doAssert not vm.failed, vm.lastError

echo "Default hybrid preserves every state hash and action for a full short match"
for teamSize in [1, 3]:
  let baseline = fresh(false, teamSize)
  let adapted = fresh(true, teamSize)
  discard hybridBegin(adapted, 0, root / ("default-" & $teamSize), endpoint = "none")
  for _ in 0 ..< 1920:
    baseline.step()
    adapted.step()
    doAssert baseline.stateHash() == adapted.stateHash()
  doAssert baseline.recorder.data.actions == adapted.recorder.data.actions
  doAssert adapted.heroVms[0].decisions == baseline.heroVms[0].decisions
  hybridFinish(adapted)
  closeBotServices(baseline)
  closeBotServices(adapted)
  hybridReset()

echo "Interventions take effect after delay while BASIC keeps deciding"
block:
  let baseline = fresh(false)
  let adapted = fresh()
  let plan = root / "plan.json"
  writeFile(plan, $(%*[{"observed_tick": 32, "apply_tick": 52,
    "observed_deaths": 0, "target": "default", "position": "north",
    "aggression": "cautious"}]))
  let h = hybridBegin(adapted, 0, root / "delayed", planPath = plan)
  for _ in 0 ..< 52:
    baseline.step()
    adapted.step()
    doAssert baseline.stateHash() == adapted.stateHash()
  baseline.step()
  adapted.step()
  doAssert h.accepted == 1
  doAssert adapted.heroVms[0].tacticLane == 32
  doAssert adapted.heroVms[0].tacticAggression == -1
  doAssert adapted.heroVms[0].decisions == 53
  var diverged = false
  for _ in 53 ..< 160:
    baseline.step()
    adapted.step()
    if baseline.stateHash() != adapted.stateHash(): diverged = true
  doAssert diverged, "accepted preferences must influence actual play"
  adapted.step()
  doAssert adapted.heroVms[0].tacticUntil == 0, "expiry uses observation tick"
  hybridFinish(adapted)
  closeBotServices(baseline)
  closeBotServices(adapted)
  hybridReset()

echo "Expired observations and changed lives cannot control the policy"
block:
  let game = fresh()
  game.world.tick = TacticalLifetime
  doAssert applyTactics(game, 0, 0, 0, 0, 32, -1) == "expired"
  doAssert applyTactics(game, 0, game.world.tick + 1, 0, 0, 32, -1) == "expired"
  doAssert applyTactics(game, 0, game.world.tick, 1, 0, 32, -1) == "life_changed"
  doAssert applyTactics(game, 0, game.world.tick, 0, 0, 32, -1) == ""
  inc game.world.pudges[0].deaths
  game.validateTactics(0)
  doAssert game.heroVms[0].tacticUntil == 0
  closeBotServices(game)

echo "Target preference remains fog-clipped and invalidates on lost contact"
block:
  let game = fresh(teamSize = 3)
  for p in game.world.pudges.mitems: p.shieldTicks = 0
  game.world.pudges[0].placePudge(55, 40)
  game.world.pudges[3].placePudge(65, 40)
  let target = game.world.pudges[3].id
  doAssert visibleEnemy(game.world, 0, target)
  doAssert ("enemy_" & $target) in tacticalChoices(game.world, 0)[0]
  doAssert applyTactics(game, 0, 0, 0, target, 0, 0) == ""
  game.world.pudges[3].placePudge(110, 110)
  doAssert not visibleEnemy(game.world, 0, target)
  game.validateTactics(0)
  doAssert game.heroVms[0].tacticTarget == 0
  doAssert applyTactics(game, 0, 0, 0, target, 0, 0) == "target_unavailable"
  closeBotServices(game)

echo "Unsupported policy adapters fail explicitly"
block:
  var rejected = false
  try: discard tacticalSource("walkTo(64, 64)")
  except ValueError: rejected = true
  doAssert rejected

echo "Unavailable inference preserves BASIC and records failures without crashing"
block:
  let baseline = fresh(false)
  let adapted = fresh()
  let h = hybridBegin(adapted, 0, root / "unavailable", endpoint = "http://127.0.0.1:1")
  for _ in 0 ..< 64:
    baseline.step()
    adapted.step()
    sleep(1)
    doAssert baseline.stateHash() == adapted.stateHash()
  doAssert h.failures > 0
  hybridFinish(adapted)
  for line in lines(h.dir / "decisions.jsonl"):
    let record = parseJson(line)
    if record.hasKey("accepted"):
      doAssert not record["accepted"].getBool
      doAssert record["result"].kind == JNull
  closeBotServices(baseline)
  closeBotServices(adapted)
  hybridReset()

echo "A pending request at match end is logged and closed"
block:
  let game = fresh()
  let h = hybridBegin(game, 0, root / "pending", endpoint = "http://127.0.0.1:1")
  h.hybridTick()
  doAssert h.requests == 1
  hybridFinish(game)
  var ended = false
  for line in lines(h.dir / "decisions.jsonl"):
    if parseJson(line){"reason"}.getStr == "match_ended": ended = true
  doAssert ended
  closeBotServices(game)
  hybridReset()

echo "Tactical shadow capture never controls BASIC and records causal history"
block:
  let baseline = fresh(false)
  let observed = fresh(false)
  let h = hybridBegin(observed, 0, root / "shadow", endpoint = "http://127.0.0.1:1", shadow = true)
  for _ in 0 ..< 192:
    baseline.step()
    observed.step()
    doAssert baseline.stateHash() == observed.stateHash()
  doAssert baseline.recorder.data.actions == observed.recorder.data.actions
  doAssert h.requests == 0 and h.accepted == 0 and h.failures == 0
  hybridFinish(observed)
  let meta = parseFile(h.dir / "match.json")
  doAssert meta["controller_schema"].getStr == TacticalSchema
  doAssert meta["policy_fingerprint"].getStr.len > 5
  doAssert meta["executor"].getStr == "basic"
  var count = 0
  var lastMs = meta["started_ms"].getBiggestInt
  for line in lines(h.dir / "decisions.jsonl"):
    let record = parseJson(line)
    doAssert record["at_ms"].getBiggestInt >= lastMs
    lastMs = record["at_ms"].getBiggestInt
    let history = record["request"]["state"]["recent_history"]
    doAssert history.len == min(count, 3)
    for prior in history:
      doAssert prior["tick"].getInt < record["observed_tick"].getInt
    inc count
  doAssert count == 6
  closeBotServices(baseline)
  closeBotServices(observed)
  hybridReset()

echo "Human seats without a BASIC VM can supply tactical observations"
block:
  let game = fresh(false)
  game.humanSlots = @[0]
  closeBotServices(game)
  game.heroVms[0] = nil
  let h = hybridBegin(game, 0, root / "human", shadow = true)
  h.hybridTick()
  hybridFinish(game)
  let meta = parseFile(h.dir / "match.json")
  doAssert meta["executor"].getStr == "human"
  doAssert meta["policy_fingerprint"].getStr == "human:no-basic-vm"
  var count = 0
  for line in lines(h.dir / "decisions.jsonl"):
    doAssert parseJson(line)["request"]["state"]["current_preferences"]["target_id"].getInt == 0
    inc count
  doAssert count == 1
  hybridReset()

removeDir(root)
echo "Hybrid checks passed"
