import polyworld/pathing, content, maps, sim, replays

let map = generateMap(7)
# 2v2: seats 3 and 6 off (indices 2, 5).
var off: array[PudgeCount, bool]
off[2] = true
off[5] = true
let roster = filteredRoster(off)
doAssert roster.len == 4
let game = newGame(map, TickRate * 30, false, ReplayData(),
  roster = roster)
doAssert game.world.pudges.len == 4
doAssert game.world.worldIndexOfSeat(0) == 0
doAssert game.world.worldIndexOfSeat(2) == -1
doAssert game.world.worldIndexOfSeat(3) == 2
doAssert game.world.worldIndexOfSeat(4) == 3
proc noTurn() = discard
for _ in 0 ..< TickRate * 10:
  tickWorld(game, noTurn)
doAssert not game.world.gameOver
echo "2v2 roster: 4 pudges, seat map correct, 10s ticked clean"
# 1v3 handicap: west keeps only seat 1.
var off2: array[PudgeCount, bool]
off2[1] = true
off2[2] = true
let solo = filteredRoster(off2)
doAssert solo.len == 4
let game2 = newGame(map, TickRate * 30, false, ReplayData(),
  roster = solo)
for _ in 0 ..< TickRate * 5:
  tickWorld(game2, noTurn)
echo "1v3 roster runs; seat toggles pass"
