## N vs N rosters: 1v1 through 5v5 tick, 3v3 hash identity, 2v2 seat filter.

import
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

proc noTurn() = discard

echo "Testing default 3v3 still seats six"
block threeVThree:
  let game = newGame(generateMap(2026), TickRate * 8, false, ReplayData())
  doAssert game.world.pudges.len == PudgeCount
  doAssert game.world.spawnLayout.west.len == TeamSize
  doAssert rosterModeName(game.world) == "3v3"
  for _ in 0 ..< TickRate * 4:
    tickWorld(game, noTurn)
  doAssert not game.world.gameOver

echo "Testing 4v4 and 5v5 tick on N-pad maps"
block fourAndFive:
  for n in [4, 5]:
    let
      map = generateMap(7, n)
      game = newGame(map, TickRate * 16, false, ReplayData())
    doAssert map.teamSize == n
    doAssert game.world.pudges.len == matchPudgeCount(n)
    doAssert game.world.spawnLayout.west.len == n
    doAssert rosterModeName(game.world) == $n & "v" & $n
    var west, east = 0
    for pudge in game.world.pudges:
      if pudge.team == WestTeam: inc west
      else: inc east
    doAssert west == n and east == n
    for _ in 0 ..< TickRate * 8:
      tickWorld(game, noTurn)
    doAssert not game.world.gameOver

echo "Testing --team-size 2 is four butchers on two pads"
block trueTwoVTwo:
  let
    map = generateMap(9, 2)
    game = newGame(map, TickRate * 8, false, ReplayData())
  doAssert game.world.pudges.len == 4
  doAssert game.world.spawnLayout.west.len == 2
  doAssert rosterModeName(game.world) == "2v2"
  for _ in 0 ..< TickRate * 4:
    tickWorld(game, noTurn)

echo "Testing --team-size 1 is slot 0, not the duel slot 1"
block trueOneVOne:
  let
    map = generateMap(11, 1)
    game = newGame(map, TickRate * 8, false, ReplayData())
  doAssert game.world.pudges.len == 2
  doAssert game.world.pudges[0].slot == 0
  doAssert game.world.pudges[1].slot == 0
  doAssert rosterModeName(game.world) == "1v1"
  for _ in 0 ..< TickRate * 4:
    tickWorld(game, noTurn)

echo "Testing duel still uses slot 1 on a 3-pad map"
block duelUnchanged:
  let
    map = generateMap(2026)
    game = newGame(map, TickRate * 8, false, ReplayData(), duel = true)
  doAssert game.world.pudges.len == DuelPudgeCount
  doAssert game.world.pudges[0].slot == 1
  doAssert game.world.spawnLayout.west.len == TeamSize
  doAssert rosterModeName(game.world) == "duel"

echo "test_pw_nvn: all checks passed"
