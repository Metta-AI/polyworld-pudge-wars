## Client-frame cost bench: fog upload, blur, world clone, prediction rebuild.
##
## Headless stand-in for the graphical per-tick work that does not run
## inside `pwheadless`. Same Fluffy defines as the sim trace:
##
##   nim c -d:release -d:profileTracePath=examples/pudge_wars/profiles/clientcost.json \
##     -r tests/bench_pw_clientcost.nim

import
  std/strformat,
  polyworld/[pathing, profiles, visions],
  ../examples/pudge_wars/content,
  ../examples/pudge_wars/fog,
  ../examples/pudge_wars/maps,
  ../examples/pudge_wars/netpredict,
  ../examples/pudge_wars/replays,
  ../examples/pudge_wars/sim

const
  Frames = 100
  ViewTeam = 0  ## West

let
  map = generateMap(7)
  game = newGame(map, int32(Frames * 2), false, ReplayData())

proc fillFogScan(world: World, team: int, values: var seq[uint8]) {.measure.} =
  ## Current graphics path: every tile asks fogCanSeeTeam.
  if values.len != GridTiles * GridTiles:
    values = newSeq[uint8](GridTiles * GridTiles)
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      let index = z * GridTiles + x
      if fogCanSeeTeam(world, team, worldAtTile(x, z)):
        values[index] = 255
      else:
        values[index] = 26

proc fillFogStamp(world: World, team: int, values: var seq[uint8]) {.measure.} =
  ## Shared presentation path: column fills plus ally sight circles.
  fillTeamVision(world, team, values)

proc blurFog(values: seq[uint8], dest: var seq[uint8]) {.measure.} =
  blurVisibilityInto(values, dest, int32(GridTiles), int32(GridTiles))

proc cloneWorld(world: World) {.measure.} =
  discard world.clone()

proc main() =
  startProfileTrace()
  defer:
    finishProfileTrace()
  for _ in 0 ..< Frames:
    tickWorld(game, proc() = discard)
  var scan = newSeq[uint8](GridTiles * GridTiles)
  var stamp = newSeq[uint8](GridTiles * GridTiles)
  var blurred: seq[uint8]
  let pred = newPredictor()
  pred.enable(0, MaxLead)
  for _ in 0 ..< Frames:
    fillFogScan(game.world, ViewTeam, scan)
    fillFogStamp(game.world, ViewTeam, stamp)
    blurFog(scan, blurred)
    cloneWorld(game.world)
    pred.rebuild(game)
  var mismatch = 0
  for i in 0 ..< scan.len:
    let scanLit = scan[i] == 255
    let stampLit = stamp[i] == 255
    if scanLit != stampLit:
      inc mismatch
  echo &"frames {Frames}  fog scan vs stamp mismatches {mismatch}"
  echo &"grid {GridTiles}x{GridTiles}  sight {SightRadiusTiles}  pudges {game.world.pudges.len}"

main()
