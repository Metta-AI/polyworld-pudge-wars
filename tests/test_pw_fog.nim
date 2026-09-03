## Fog of war: team sight from a butcher id (replay spectator POV).

import
  ../examples/pudge_wars/[content, fog, maps, replays, sim]

let map = generateMap(2026)

proc freshGame(): Game =
  newGame(map, TickRate * 30, false, ReplayData())

echo "Testing fogTeamOf from a butcher id"
block:
  let game = freshGame()
  let west = game.world.pudges[0]
  let east = game.world.pudges[3]
  doAssert west.team == WestTeam
  doAssert east.team == EastTeam
  doAssert fogTeamOf(game.world, west.id) == WestTeam.ord
  doAssert fogTeamOf(game.world, east.id) == EastTeam.ord
  doAssert fogTeamOf(game.world, 0) == -1
  doAssert fogTeamOf(game.world, 99_999) == -1

echo "Testing omniscient team sees the whole map"
block:
  let game = freshGame()
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(22, 64))
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(105, 64))
  doAssert fogCanSeeTeam(game.world, -1, worldAtTile(RiverCenterX, 64))

echo "Testing home bank and river stay lit without crossing"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(22, 64)),
    "own spawn pad must stay lit"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(PlayWestMax, 64)),
    "the whole home bank stays lit"
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(RiverCenterX, 64)),
    "the river is always terrain-visible"
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "the far enemy fountain is dark until a teammate carries sight"

echo "Testing a living teammate scouts the enemy bank"
block:
  let game = freshGame()
  let westId = game.world.pudges[0].id
  let westTeam = fogTeamOf(game.world, westId)
  game.world.pudges[0].placePudge(90, 64)
  doAssert fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a butcher 15 tiles from the east fountain should light it"
  game.world.pudges[0].state = Dying
  doAssert not fogCanSeeTeam(game.world, westTeam, worldAtTile(105, 64)),
    "a dying butcher must stop scouting"

echo "Testing fogShownPudgeTeam hides enemies in the dark"
block:
  let game = freshGame()
  let westTeam = fogTeamOf(game.world, game.world.pudges[0].id)
  doAssert fogShownPudgeTeam(game.world, westTeam, game.world.pudges[0])
  doAssert not fogShownPudgeTeam(game.world, westTeam, game.world.pudges[3])
  doAssert fogShownPudgeTeam(game.world, -1, game.world.pudges[3])

echo "test_pw_fog: all checks passed"
