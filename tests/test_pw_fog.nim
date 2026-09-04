## Fog of war: team sight from a butcher id (replay spectator POV).

import
  polyworld/pathing,
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

proc hasScriptObject(world: World, viewer, targetId: int32): bool =
  var value: WorldObject
  for i in 0 ..< worldObjectCount(world, viewer):
    if worldObjectAt(world, viewer, i, value) and value.id == targetId:
      return true
  false

echo "Testing worldObjectCount matches renderer fog"
block:
  let game = freshGame()
  let
    west = game.world.pudges[0].id
    east = game.world.pudges[3].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[1].placePudge(22, 40)
  game.world.pudges[2].placePudge(22, 88)
  game.world.pudges[3].placePudge(105, 64)
  game.world.pudges[4].placePudge(105, 40)
  game.world.pudges[5].placePudge(105, 88)
  doAssert hasScriptObject(game.world, west, west)
  doAssert hasScriptObject(game.world, west, game.world.pudges[1].id)
  doAssert not hasScriptObject(game.world, west, east),
    "scripts must not see an enemy on the far bank"
  doAssert not hasScriptObject(game.world, east, west)
  game.world.pudges[0].placePudge(90, 64)
  doAssert hasScriptObject(game.world, west, east),
    "a living teammate on the far bank must share sight with scripts"
  game.world.pudges[3].placePudge(RiverCenterX, 40)
  doAssert hasScriptObject(game.world, west, east),
    "an enemy in the river is always visible"

echo "Testing worldObjectCount hides far-bank walls"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  game.world.props.add Prop(
    id: game.world.nextPropId,
    kind: PropWall,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    tileX: 100,
    tileZ: 64,
    hp: 120,
    maxHp: 120,
    ticksLeft: 100,
    alive: true
  )
  inc game.world.nextPropId
  let wallId = game.world.props[^1].id
  doAssert not hasScriptObject(game.world, west, wallId),
    "an enemy palisade in the dark must not leak through object queries"
  game.world.pudges[0].placePudge(90, 64)
  doAssert hasScriptObject(game.world, west, wallId),
    "shared sight must reveal the same wall a human would see"

echo "Testing worldHookCount hides a hook in the dark"
block:
  let game = freshGame()
  let west = game.world.pudges[0].id
  game.world.pudges[0].placePudge(22, 64)
  game.world.pudges[3].placePudge(105, 64)
  game.world.hooks.add Hook(
    id: game.world.nextHookId,
    ownerId: game.world.pudges[3].id,
    team: EastTeam,
    phase: HookFlying,
    position: worldAtTile(105, 64),
    origin: worldAtTile(105, 64),
    prior: worldAtTile(105, 64),
    heading: heading(-WorldScale, 0),
    range: BaseHookRange,
    speed: BaseHookSpeed,
    peakSpeed: BaseHookSpeed,
    radius: BaseHookRadius,
    damage: BaseHookDamage
  )
  inc game.world.nextHookId
  doAssert worldHookCount(game.world, west) == 0,
    "a hook head on the far bank is in the fog"
  game.world.hooks[^1].position = worldAtTile(RiverCenterX, 64)
  doAssert worldHookCount(game.world, west) == 1,
    "the same hook becomes visible once its head enters the river"

echo "Testing fillTeamVision matches per-tile fogCanSeeTeam"
block:
  let game = freshGame()
  game.world.pudges[0].placePudge(90, 64)
  var mask: seq[uint8]
  fillTeamVision(game.world, WestTeam.ord, mask)
  doAssert mask.len == GridTiles * GridTiles
  for z in 0 ..< GridTiles:
    for x in 0 ..< GridTiles:
      let lit = fogCanSeeTeam(game.world, WestTeam.ord, worldAtTile(x, z))
      doAssert (mask[z * GridTiles + x] == 255) == lit,
        "stamp/scan disagree at " & $x & "," & $z
  fillTeamVision(game.world, -1, mask)
  for value in mask:
    doAssert value == 255

echo "test_pw_fog: all checks passed"
