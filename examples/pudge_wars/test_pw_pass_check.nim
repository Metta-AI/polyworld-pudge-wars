## Scratch check: two butchers ordered straight through each other must
## slip past instead of jamming chest-to-chest.

import polyworld/pathing, content, maps, sim, replays

let map = generateMap(7)
let game = newGame(map, TickRate * 60, false, ReplayData(), duel = true)
let world = game.world

# Park both on the same west-bank line, 8 tiles apart, then order each
# to walk through the other to the far side.
let
  z = 64
  westA = 30
  westB = 38
world.pudges[0].placePudge(westA, z)
world.pudges[1].placePudge(westB, z)
doAssert applyWalkTo(world, world.pudges[0].id, int32(westB + 8), int32(z))
doAssert applyWalkTo(world, world.pudges[1].id, int32(westA - 8), int32(z))

proc noTurn() = discard
for _ in 0 ..< TickRate * 12:
  tickWorld(game, noTurn)

let
  a = tileOf(world.pudges[0].position)
  b = tileOf(world.pudges[1].position)
echo "A reached ", a.x, ",", a.z, " (wanted ", westB + 8, ")"
echo "B reached ", b.x, ",", b.z, " (wanted ", westA - 8, ")"
doAssert abs(a.x - (westB + 8)) <= 1 and abs(a.z - z) <= 2,
  "A jammed at " & $a.x & "," & $a.z
doAssert abs(b.x - (westA - 8)) <= 1 and abs(b.z - z) <= 2,
  "B jammed at " & $b.x & "," & $b.z
echo "pass-through check passed"
