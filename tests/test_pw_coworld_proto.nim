## Exercises the JSON /player protocol surface of the coworld host
## without a socket: acceptance echoes (true / reject tokens / arrays,
## filtered to what the seat sent), rot as a set (no flicker), shield
## as ticks, items aliasing item_ranks, the flat BASIC-order objects
## list, ally_ping.age, and the print -> say intent bubble.

import
  std/json,
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/bots,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim,
  ../examples/pudge_wars/coworld_host

const Ticks = 400'i32

proc bootProtoGame() =
  ## The coworld host's world: 3v3 roster, every seat human, no tape.
  game = newGame(generateMap(7), Ticks, false, ReplayData(), killGoal = 3)
  game.humanSlots.setLen(0)
  for i in 0 ..< game.world.pudges.len:
    game.humanSlots.add i
  maxTicks = Ticks

proc step() =
  ## One host tick the way main() runs it: sim step, then snapshot the
  ## acceptance echoes, then drop the results like forwardGameResults.
  tickWorld(game, proc() = runBotDecisions(game))
  snapshotAccepted()
  game.intentResults.setLen(0)

bootProtoGame()

echo "Testing accepted echoes: true, reject tokens, sent-key filter"
block:
  applyAction(0, %*{"hook_to": [64.0, 64.0]})
  step()
  var obs = observation(0)
  doAssert obs["game_version"].getInt == int(ReplayGameVersion)
  doAssert obs["accepted"]["hook_to"] == %true,
    "a legal hook echoes true, got " & $obs["accepted"]
  # Only the sent key appears; nothing else leaks into the echo.
  doAssert obs["accepted"].len == 1,
    "echo carries exactly the sent keys, got " & $obs["accepted"]

  # Same-tick second ask: the windup is running, so the token says why.
  applyAction(0, %*{"hook_to": [64.0, 64.0]})
  step()
  obs = observation(0)
  doAssert obs["accepted"]["hook_to"] == %"casting",
    "a hook during windup echoes casting, got " & $obs["accepted"]

  # A tick with no reply echoes an empty object (auto-acquire included).
  step()
  obs = observation(0)
  doAssert obs["accepted"].len == 0,
    "an idle tick echoes nothing, got " & $obs["accepted"]

echo "Testing array purchases echo as arrays in send order"
block:
  game.world.pudges[1].points = 2
  applyAction(1, %*{"buy_upgrade": [0, 0, 0]})
  step()
  let obs = observation(1)
  doAssert obs["accepted"]["buy_upgrade"] == %[%true, %true, %"points"],
    "two points buy two ranks then reject, got " & $obs["accepted"]
  doAssert obs["self"]["upgrades"][0] == %2,
    "damage rank climbed to 2, got " & $obs["self"]["upgrades"]

echo "Testing rot as a set: no flicker, matched state still answers"
block:
  applyAction(2, %*{"rot": true})
  step()
  var obs = observation(2)
  doAssert obs["self"]["rot"] == %true, "rot true turns Rot on"
  doAssert obs["accepted"]["rot"] == %true, "the set is acknowledged"

  # Asking again for the same state queues nothing and cannot flicker.
  applyAction(2, %*{"rot": true})
  step()
  obs = observation(2)
  doAssert obs["self"]["rot"] == %true, "a repeated rot:true stays on"
  doAssert obs["accepted"]["rot"] == %true,
    "a matched rot ask still echoes true, got " & $obs["accepted"]

  applyAction(2, %*{"rot": false})
  step()
  obs = observation(2)
  doAssert obs["self"]["rot"] == %false, "rot false turns Rot off"
  doAssert obs["accepted"]["rot"] == %true, "the off set is acknowledged"

echo "Testing shield as ticks, items alias, play edges"
block:
  # The initial spawn carries no shield; respawns do. Grant one directly
  # to pin the wire type: a tick count, not a boolean.
  game.world.pudges[3].shieldTicks = 40
  let obs = observation(3)
  doAssert obs["self"]["shield"].kind == JInt,
    "shield is a tick count, got " & $obs["self"]["shield"]
  doAssert obs["self"]["shield"].getInt == 40,
    "shield reports the remaining ticks, got " & $obs["self"]["shield"]
  applyAction(3, %*{"rot": true})
  step()
  doAssert observation(3)["self"]["shield"].getInt == 0,
    "acting breaks the spawn shield"
  doAssert obs["self"]["items"] == obs["self"]["item_ranks"],
    "items aliases item_ranks"
  doAssert obs["self"]["items"].len == 5,
    "five permanent families (treads, longflight, palisade, hooktrap, ward)"
  doAssert obs["play_west_max"] == %PlayWestMax and
    obs["play_east_min"] == %PlayEastMin,
    "land lips ride beside the water columns"
  doAssert obs["river_west"] == %RiverWestX and
    obs["river_east"] == %RiverEastX,
    "river columns stay the inclusive water bounds"

echo "Testing objects mirrors the BASIC scriptObjects walk"
block:
  let
    obs = observation(0)
    viewerId = game.world.pudges[0].id
    count = worldObjectCount(game.world, viewerId)
  doAssert obs["objects"].len == count,
    "objects length matches worldObjectCount: " &
      $obs["objects"].len & " vs " & $count
  var wobj: WorldObject
  for i in 0 ..< count:
    doAssert worldObjectAt(game.world, viewerId, i, wobj)
    doAssert obs["objects"][i]["id"] == %wobj.id,
      "object order matches BASIC index " & $i
    doAssert obs["objects"][i]["kind"] == %wobj.kind,
      "object kind matches BASIC objectKind"
  doAssert count >= 3, "own team is always visible through fog"
  doAssert obs["objects"][0]["kind"] == %PudgeObjectKind,
    "butchers lead the list"

echo "Testing ally_ping.age and the print -> say bubble"
block:
  applyAction(1, %*{"ping": [64.0, 64.0], "print": "diving the catch"})
  step()
  let obs = observation(0)
  doAssert obs["ally_ping"].kind != JNull, "the team saw the ping"
  doAssert obs["ally_ping"]["age"] ==
    %(game.world.tick - obs["ally_ping"]["tick"].getInt),
    "age is tick minus ping tick, got " & $obs["ally_ping"]
  let mate = observation(1)
  doAssert mate["self"]["say"] == %"diving the catch",
    "print echoes on self.say, got " & $mate["self"]["say"]
  doAssert mate["print"] == %"diving the catch",
    "the top-level print echo stays"
  doAssert mate["self"]["say_tick"].getInt >= 0, "say_tick stamps the line"

echo "Testing file:// artifact URIs resolve to /coworld/replay"
block:
  doAssert artifactPath("file:///coworld/replay") == "/coworld/replay"
  doAssert artifactPath("file:///coworld/results.json") ==
    "/coworld/results.json"
  doAssert artifactPath("file://coworld/replay") == "/coworld/replay"
  doAssert artifactPath("/tmp/replay") == "/tmp/replay"

echo "test_pw_coworld_proto: all checks passed"
